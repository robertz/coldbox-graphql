component extends="coldbox.system.testing.BaseTestCase" appMapping="/tests/resources/App" {

	function run(){
		describe( "GraphQLService", function(){

			it( "resolves a scalar field via the PropertyDataFetcher fallback when no resolver method exists", function(){
				var spec = executeTestQuery( '{ widget(id: "1") { description } }' );

				expect( spec.errors ?: [] ).toBeEmpty();
				expect( spec.data.widget.description ).toBe( "A widget used for module tests." );
			} );

			it( "invokes the explicit resolver method in precedence over the PropertyDataFetcher fallback", function(){
				var spec = executeTestQuery( '{ widget(id: "1") { name upperName } }' );

				expect( spec.errors ?: [] ).toBeEmpty();
				expect( spec.data.widget.name ).toBe( "Test Widget" );
				expect( spec.data.widget.upperName ).toBe( "TEST WIDGET" );
			} );

			it( "falls back correctly when no resolver class exists at all for the type", function(){
				var spec = executeTestQuery( "{ meta { version } }" );

				expect( spec.errors ?: [] ).toBeEmpty();
				expect( spec.data.meta.version ).toBe( "1.0.0" );
			} );

			it( "produces a properly formatted error response for an invalid query", function(){
				var spec = executeTestQuery( '{ widget(id: "1") { doesNotExist } }' );

				expect( isNull( spec.data ) || isSimpleValue( spec.data ) ).toBeTrue();
				expect( spec.errors ).toBeArray();
				expect( arrayLen( spec.errors ) ).toBeGT( 0 );
				expect( spec.errors[ 1 ] ).toHaveKey( "message" );
			} );

		} );
	}

	/**
	 * Executes a query against the module's GraphQL singleton and returns the
	 * standard {data, errors} response, round-tripped through JSON so the raw
	 * java.util.Map that graphql-java returns becomes a normal CFML struct for
	 * assertions — the same conversion path GraphQLHandler relies on in production.
	 */
	private struct function executeTestQuery( required string query ){
		var engine = getWireBox().getInstance( "GraphQLService@coldbox-graphql" ).getEngine();
		var result = engine.execute(
			createObject( "java", "graphql.ExecutionInput" )
				.newExecutionInput()
				.query( arguments.query )
				.build()
		);
		return deserializeJSON( serializeJSON( result.toSpecification() ) );
	}

}
