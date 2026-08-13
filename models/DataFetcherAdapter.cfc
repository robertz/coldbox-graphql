/**
 * Bridges a single graphql-java DataFetcher call to WireBox-resolved resolver CFCs,
 * per the module's resolver convention. One instance is created per schema type at
 * schema-build time (see GraphQLService.buildSchema) and wrapped as a Java
 * graphql.schema.DataFetcher via createDynamicProxy.
 *
 * Convention: {resolverBasePackage}.{TypeName}Resolver, method {fieldName}().
 * Falls back to graphql-java's PropertyDataFetcher when no resolver class exists,
 * or the resolver class exists but doesn't implement the specific field method.
 *
 * Deferred (not implemented in v1): interface/union TypeResolver wiring.
 */
component accessors="true" {

	property name="typeName";
	property name="resolverBasePackage";
	property name="wirebox";
	property name="javaClass";

	variables.resolverInstance         = "";
	variables.hasResolver              = false;
	variables.resolverChecked          = false;
	variables.propertyDataFetcherCache = {};

	function init(
		required string typeName,
		required string resolverBasePackage,
		required any wirebox,
		required any javaClass
	){
		variables.typeName             = arguments.typeName;
		variables.resolverBasePackage  = arguments.resolverBasePackage;
		variables.wirebox              = arguments.wirebox;
		variables.javaClass            = arguments.javaClass;
		return this;
	}

	/**
	 * Single abstract method of graphql.schema.DataFetcher.
	 * `environment` is a raw graphql.schema.DataFetchingEnvironment.
	 */
	any function get( required any environment ){
		var fieldName = arguments.environment.getField().getName();

		ensureResolverResolved();

		if( variables.hasResolver && structKeyExists( variables.resolverInstance, fieldName ) ){
			return variables.resolverInstance[ fieldName ](
				source  = arguments.environment.getSource(),
				// getArguments() is a raw, case-sensitive java.util.Map — round-trip it
				// through JSON so resolver authors get an ordinary CFML struct/array.
				args    = deserializeJSON( serializeJSON( arguments.environment.getArguments() ) ),
				context = arguments.environment.getContext(),
				env     = arguments.environment
			);
		}

		// PropertyDataFetcher.fetching(fieldName) is a stateless static factory — safe to
		// build once per field and reuse, same as the resolver lookup above is memoized.
		if( !structKeyExists( variables.propertyDataFetcherCache, fieldName ) ){
			variables.propertyDataFetcherCache[ fieldName ] = variables.javaClass.create( "graphql.schema.PropertyDataFetcher" ).fetching( fieldName );
		}
		return variables.propertyDataFetcherCache[ fieldName ].get( arguments.environment );
	}

	private void function ensureResolverResolved(){
		if( variables.resolverChecked ){
			return;
		}
		variables.resolverChecked = true;

		// WireBox only registers a mapping for a dotted CFC path the first time it is
		// requested (resolved lazily via scan-location discovery) — mappingExists() would
		// wrongly report "not found" for a real, not-yet-discovered resolver. So we attempt
		// resolution directly and treat a not-found exception as "no resolver for this type."
		var mappingName = variables.resolverBasePackage & "." & variables.typeName & "Resolver";
		try{
			variables.resolverInstance = variables.wirebox.getInstance( mappingName );
			variables.hasResolver      = true;
		} catch( "Injector.InstanceNotFoundException" e ){
			// WireBox throws this same exception type both when THIS mapping doesn't exist
			// (the valid "no resolver for this type" case — its message names our own
			// mappingName) and when a resolver that DOES exist fails because one of ITS OWN
			// nested dependencies can't be found (message names that other mapping instead).
			// Only the former is safe to swallow — rethrow anything else so a genuinely
			// broken resolver doesn't silently, invisibly fall back to PropertyDataFetcher.
			if( !findNoCase( "'" & mappingName & "'", e.message ) ){
				rethrow;
			}
			variables.hasResolver = false;
		}
	}

}
