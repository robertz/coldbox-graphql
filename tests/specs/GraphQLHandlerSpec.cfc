/**
 * True end-to-end spec: issues a real HTTP POST against the actual /graphql route
 * (as configured by the harness app's basePath setting), rather than invoking
 * ColdBox/WireBox in-process. Requires the harness app to actually be serving
 * requests (see tests/resources/App).
 */
component extends="testbox.system.BaseSpec" {

	function run(){
		describe( "POST /graphql", function(){

			it( "executes a valid query and returns the standard { data, errors } shape", function(){
				var httpResult = postGraphQL( serializeJSON( { "query" : '{ widget(id: "1") { name upperName } }' } ) );

				expect( httpResult.statusCode ).toInclude( "200" );

				var body = deserializeJSON( httpResult.fileContent );
				expect( body.errors ?: [] ).toBeEmpty();
				expect( body.data.widget.name ).toBe( "Test Widget" );
				expect( body.data.widget.upperName ).toBe( "TEST WIDGET" );
			} );

			it( "returns a spec-shaped error array for an invalid query", function(){
				var httpResult = postGraphQL( serializeJSON( { "query" : '{ widget(id: "1") { doesNotExist } }' } ) );

				var body = deserializeJSON( httpResult.fileContent );
				expect( isNull( body.data ) || isSimpleValue( body.data ) ).toBeTrue();
				expect( body.errors ).toBeArray();
				expect( arrayLen( body.errors ) ).toBeGT( 0 );
				expect( body.errors[ 1 ] ).toHaveKey( "message" );
			} );

			it( "returns a 400 with a spec-shaped error for a malformed request body", function(){
				var httpResult = postGraphQL( "not json" );

				expect( httpResult.statusCode ).toInclude( "400" );

				var body = deserializeJSON( httpResult.fileContent );
				expect( isNull( body.data ) || isSimpleValue( body.data ) ).toBeTrue();
				expect( body.errors[ 1 ] ).toHaveKey( "message" );
			} );

			it( "returns a 400 with a spec-shaped error when 'query' is valid JSON but not a string", function(){
				// Regression test: trim() on a non-string query used to throw uncaught,
				// outside the handler's error handling, instead of this graceful 400.
				var httpResult = postGraphQL( serializeJSON( { "query" : { "nested" : "object" } } ) );

				expect( httpResult.statusCode ).toInclude( "400" );

				var body = deserializeJSON( httpResult.fileContent );
				expect( isNull( body.data ) || isSimpleValue( body.data ) ).toBeTrue();
				expect( body.errors[ 1 ] ).toHaveKey( "message" );
			} );

			it( "treats a non-string 'operationName' as not provided rather than crashing", function(){
				var httpResult = postGraphQL( serializeJSON( { "query" : "{ meta { version } }", "operationName" : [ "a", "b" ] } ) );

				expect( httpResult.statusCode ).toInclude( "200" );

				var body = deserializeJSON( httpResult.fileContent );
				expect( body.errors ?: [] ).toBeEmpty();
				expect( body.data.meta.version ).toBe( "1.0.0" );
			} );

			it( "gives resolvers the ColdBox event as 'context', not null", function(){
				var httpResult = postGraphQL( serializeJSON( { "query" : "{ contextCheck }" } ) );

				var body = deserializeJSON( httpResult.fileContent );
				expect( body.errors ?: [] ).toBeEmpty();
				expect( body.data.contextCheck ).toBe( "has-request-context" );
			} );

			it( "surfaces a resolver's own broken dependency as a real error instead of silently falling back", function(){
				// Regression test: DataFetcherAdapter used to catch every
				// Injector.InstanceNotFoundException and treat it as "no resolver for this
				// type," which also silently swallowed a resolver that exists but has ITS OWN
				// broken WireBox dependency (BrokenResolver.cfc injects a mapping that doesn't
				// exist).
				var httpResult = postGraphQL( serializeJSON( { "query" : "{ broken { brokenField } }" } ) );

				var body = deserializeJSON( httpResult.fileContent );
				expect( body.errors ).toBeArray();
				expect( arrayLen( body.errors ) ).toBeGT( 0 );
				expect( body.errors[ 1 ] ).toHaveKey( "message" );
			} );

		} );
	}

	private any function postGraphQL( required string requestBody ){
		// /index.cfm/graphql rather than clean /graphql — SES URL rewriting is a host
		// server concern (Apache/IIS/CommandBox --rewritesEnable), not this module's.
		var baseURL = "http://" & cgi.server_name & ":" & cgi.server_port;
		cfhttp( url = baseURL & "/index.cfm/graphql", method = "POST", result = "local.httpResult" ){
			cfhttpparam( type = "header", name = "Content-Type", value = "application/json" );
			cfhttpparam( type = "body", value = arguments.requestBody );
		}

		return local.httpResult;
	}

}
