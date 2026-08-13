/**
 * Builds and holds the singleton graphql.GraphQL engine: parses/merges the consumer's
 * SDL files, wires convention-based DataFetchers, registers custom scalars, and
 * applies introspection visibility. Built once, at application startup (see
 * ModuleConfig.onLoad()) — not per request.
 *
 * Deferred (not implemented in v1): interface/union TypeResolver wiring, subscriptions,
 * a programmatic (non-SDL) schema-building extension hook.
 */
component singleton accessors="true" {

	property name="wirebox"        inject="wirebox";
	property name="settings"       inject="coldbox:moduleSettings:coldbox-graphql";
	property name="scalarRegistry" inject="ScalarRegistry@coldbox-graphql";
	// Resolves graphql-java classes consistently for the running engine — see
	// models/JavaClassFactory.cfc for why this can't simply be cbjavaloader everywhere.
	property name="javaClass"      inject="JavaClassFactory@coldbox-graphql";

	variables.engine = "";

	function onDIComplete(){
		buildSchema();
	}

	any function getEngine(){
		return variables.engine;
	}

	/**
	 * The raw graphql.schema.GraphQLSchema this module built — for SDL printing
	 * (graphql.schema.idl.SchemaPrinter), codegen tooling, or any other programmatic
	 * inspection. See README "Exposing the schema programmatically" for an example.
	 */
	any function getSchema(){
		return variables.engine.getGraphQLSchema();
	}

	private void function buildSchema(){
		validateSettings();

		var schemaFiles = resolveSchemaFiles( settings.schemaPaths );
		if( arrayLen( schemaFiles ) == 0 ){
			throw(
				type    = "ColdboxGraphQL.ConfigurationException",
				message = "schemaPaths did not resolve to any .graphqls files.",
				detail  = "Paths checked: " & arrayToList( settings.schemaPaths, ", " )
			);
		}

		var mergedRegistry = parseAndMergeSchemas( schemaFiles );
		var runtimeWiringBuilder = javaClass.create( "graphql.schema.idl.RuntimeWiring" ).newRuntimeWiring();

		wireResolvers( runtimeWiringBuilder, mergedRegistry );
		wireScalars( runtimeWiringBuilder );

		if( !( settings.enableIntrospection ?: true ) ){
			runtimeWiringBuilder.fieldVisibility(
				javaClass.create( "graphql.schema.visibility.NoIntrospectionGraphqlFieldVisibility" ).NO_INTROSPECTION_FIELD_VISIBILITY
			);
		}

		var runtimeWiring    = runtimeWiringBuilder.build();
		var schemaGenerator  = javaClass.create( "graphql.schema.idl.SchemaGenerator" ).init();
		var graphQLSchema    = schemaGenerator.makeExecutableSchema( mergedRegistry, runtimeWiring );

		variables.engine = javaClass.create( "graphql.GraphQL" ).newGraphQL( graphQLSchema ).build();
	}

	private void function validateSettings(){
		if( !structKeyExists( settings, "schemaPaths" ) || !isArray( settings.schemaPaths ) || arrayLen( settings.schemaPaths ) == 0 ){
			throw(
				type    = "ColdboxGraphQL.ConfigurationException",
				message = "No schemaPaths configured for the coldbox-graphql module.",
				detail  = "Set moduleSettings['coldbox-graphql'].schemaPaths to an array of .graphqls file paths in your app's config/ColdBox.cfc."
			);
		}
		if( !len( trim( settings.resolverBasePackage ?: "" ) ) ){
			throw(
				type    = "ColdboxGraphQL.ConfigurationException",
				message = "No resolverBasePackage configured for the coldbox-graphql module.",
				detail  = "Set moduleSettings['coldbox-graphql'].resolverBasePackage in your app's config/ColdBox.cfc, e.g. 'models.resolvers'."
			);
		}
	}

	private array function resolveSchemaFiles( required array configuredPaths ){
		var resolved = [];

		for( var rawPath in arguments.configuredPaths ){
			var expandedPath = expandPath( rawPath );

			if( directoryExists( expandedPath ) ){
				arrayAppend( resolved, directoryList( expandedPath, false, "path", "*.graphqls" ), true );
			} else if( find( "*", expandedPath ) ){
				var baseDir = getDirectoryFromPath( expandedPath );
				var filter  = getFileFromPath( expandedPath );
				if( directoryExists( baseDir ) ){
					arrayAppend( resolved, directoryList( baseDir, false, "path", filter ), true );
				} else {
					throw(
						type    = "ColdboxGraphQL.ConfigurationException",
						message = "Configured schema path does not exist: " & rawPath & " (resolved directory " & baseDir & " does not exist)"
					);
				}
			} else if( fileExists( expandedPath ) ){
				arrayAppend( resolved, expandedPath );
			} else {
				throw(
					type    = "ColdboxGraphQL.ConfigurationException",
					message = "Configured schema path does not exist: " & rawPath & " (resolved to " & expandedPath & ")"
				);
			}
		}

		return resolved;
	}

	private any function parseAndMergeSchemas( required array schemaFiles ){
		var schemaParser    = javaClass.create( "graphql.schema.idl.SchemaParser" ).init();
		var mergedRegistry  = javaClass.create( "graphql.schema.idl.TypeDefinitionRegistry" ).init();

		for( var filePath in arguments.schemaFiles ){
			var sdl      = fileRead( filePath );
			var registry = schemaParser.parse( sdl );
			mergedRegistry = mergedRegistry.merge( registry );
		}

		return mergedRegistry;
	}

	private void function wireResolvers( required any runtimeWiringBuilder, required any typeRegistry ){
		// Iterate via a raw java.util.Iterator rather than CFML for-in over the Map,
		// since for-in support over java.util.Map varies across CFML engines.
		// Only object types have fields/DataFetchers; interfaces/unions/enums/scalars/
		// inputs are skipped (interface field resolution needs a TypeResolver — deferred, see class doc).
		var entryIterator = arguments.typeRegistry.types().entrySet().iterator();

		while( entryIterator.hasNext() ){
			var entry = entryIterator.next();
			if( !isInstanceOf( entry.getValue(), "graphql.language.ObjectTypeDefinition" ) ){
				continue;
			}
			var typeName = entry.getKey();

			var adapter = new DataFetcherAdapter(
				typeName            = typeName,
				resolverBasePackage = settings.resolverBasePackage,
				wirebox             = wirebox,
				javaClass           = javaClass
			);
			// createDynamicProxy() has no per-call classpath override — unlike javaClass.create()
			// above, it can only see classes already on the real application classpath. This
			// is why Lucee/ACF still require the this.javaSettings install step (see README);
			// on BoxLang 1.8.0+ cbjavaloader uses the native request classloader, so this
			// resolves with no extra configuration at all.
			var dataFetcherProxy = createDynamicProxy( adapter, "graphql.schema.DataFetcher" );

			var typeWiring = javaClass.create( "graphql.schema.idl.TypeRuntimeWiring" )
				.newTypeWiring( typeName )
				.defaultDataFetcher( dataFetcherProxy )
				.build();

			arguments.runtimeWiringBuilder.type( typeWiring );
		}
	}

	private void function wireScalars( required any runtimeWiringBuilder ){
		var scalars = scalarRegistry.getScalars( settings.customScalarProvider ?: "" );
		for( var scalarType in scalars ){
			arguments.runtimeWiringBuilder.scalar( scalarType );
		}
	}

}
