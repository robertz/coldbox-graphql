/**
 * POST /graphql (configurable via the basePath module setting; route self-registered
 * in ModuleConfig.cfc's onLoad()). Accepts the standard GraphQL request body
 * { query, variables, operationName } and returns the standard GraphQL response
 * shape { data, errors }.
 *
 * Validation errors and DataFetcher exceptions are already captured by graphql-java
 * into ExecutionResult.errors (surfaced via toSpecification()) — the try/catch here is
 * only a safety net for unexpected engine-level failures (e.g. a malformed request body).
 */
component {

	property name="graphQLService" inject="GraphQLService@coldbox-graphql";
	// Must resolve graphql.ExecutionInput the same way GraphQLService resolved the
	// engine itself — see models/JavaClassFactory.cfc.
	property name="javaClass"      inject="JavaClassFactory@coldbox-graphql";

	function execute( event, rc, prc ){
		var requestBody = {};

		try{
			requestBody = deserializeJSON( len( trim( event.getHTTPContent() ?: "" ) ) ? event.getHTTPContent() : "{}" );
		} catch( any e ){
			return renderGraphQLError( event, "Invalid JSON request body: " & e.message, 400 );
		}

		// isSimpleValue() guards against `query`/`operationName` deserializing to a JSON
		// object/array — trim() on a complex value throws uncaught (this whole block runs
		// outside the JSON-parse try/catch above), which would otherwise escape as a raw
		// unhandled exception instead of this handler's documented error envelope.
		if( !isStruct( requestBody ) || !structKeyExists( requestBody, "query" ) || !isSimpleValue( requestBody.query ) || !len( trim( requestBody.query ) ) ){
			return renderGraphQLError( event, "Missing required 'query' field.", 400 );
		}

		var executionInputBuilder = javaClass.create( "graphql.ExecutionInput" )
			.newExecutionInput()
			.query( requestBody.query )
			// Populates DataFetchingEnvironment.getContext() (resolvers' `context` arg — see
			// README) with the ColdBox event, so resolvers can reach rc/prc/headers/session
			// via the normal ColdBox RequestContext API instead of always getting null.
			.context( event );

		if( structKeyExists( requestBody, "variables" ) && isStruct( requestBody.variables ) ){
			executionInputBuilder.variables( toJavaMap( requestBody.variables ) );
		}
		if( structKeyExists( requestBody, "operationName" ) && isSimpleValue( requestBody.operationName ) && len( trim( requestBody.operationName ) ) ){
			executionInputBuilder.operationName( requestBody.operationName );
		}

		try{
			var executionResult = graphQLService.getEngine().execute( executionInputBuilder.build() );
			event.renderData( type = "json", data = executionResult.toSpecification() );
		} catch( any e ){
			return renderGraphQLError( event, "GraphQL execution error: " & e.message, 500 );
		}
	}

	/**
	 * graphql-java's ExecutionInput.Builder.variables() defensively copies the incoming
	 * map via `new LinkedHashMap<>(yourMap)`, which builds itself by iterating entrySet().
	 * BoxLang's IStruct implements java.util.Map<Key, Object> (not <String, Object>) — its
	 * entrySet() yields ortus.boxlang.runtime.scopes.Key objects as keys, even though it also
	 * exposes convenience get(String)/containsKey(String) overloads for CFML-side code. The
	 * defensive copy ends up keyed by Key instances, so graphql-java's later containsKey("x")
	 * lookups (plain String) silently miss and every variable reads as "not provided" — for a
	 * NonNull variable that surfaces as "coerced Null value for NonNull type". Converting to a
	 * real java.util.LinkedHashMap/ArrayList with actual String keys before handing it to
	 * graphql-java sidesteps the mismatch.
	 */
	private any function toJavaMap( required struct source ){
		var target = createObject( "java", "java.util.LinkedHashMap" ).init();
		for( var key in structKeyArray( arguments.source ) ){
			target.put( key, toJavaValue( arguments.source[ key ] ) );
		}
		return target;
	}

	private any function toJavaValue( required any value ){
		if( isNull( arguments.value ) ){
			return javaCast( "null", "" );
		}
		if( isStruct( arguments.value ) ){
			return toJavaMap( arguments.value );
		}
		if( isArray( arguments.value ) ){
			var target = createObject( "java", "java.util.ArrayList" ).init();
			for( var item in arguments.value ){
				target.add( toJavaValue( item ) );
			}
			return target;
		}
		return arguments.value;
	}

	private void function renderGraphQLError( required any event, required string message, numeric statusCode = 400 ){
		arguments.event.renderData(
			type       = "json",
			statusCode = arguments.statusCode,
			data       = {
				"data"   : javaCast( "null", "" ),
				"errors" : [ { "message" : arguments.message } ]
			}
		);
	}

}
