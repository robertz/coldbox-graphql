/**
 * Config-validation specs. These build a SEPARATE, manually-autowired GraphQLService
 * instance per test (not the app's real singleton) so each test can override settings
 * with a deliberately bad config and assert on the resulting failure — the real
 * singleton is already built once, successfully, at app startup, and shouldn't be
 * touched by these tests.
 */
component extends="coldbox.system.testing.BaseTestCase" appMapping="/tests/resources/App" {

	function run(){
		describe( "GraphQLService config validation", function(){

			it( "fails fast when a wildcard schemaPaths entry's directory doesn't exist", function(){
				// Regression test: this used to silently resolve to zero files for that one
				// entry instead of throwing, as long as at least one other schemaPaths entry
				// resolved successfully.
				var badSettings = duplicate( getRealSettings() );
				badSettings.schemaPaths = [ badSettings.schemaPaths[ 1 ], "/does/not/exist/*.graphqls" ];

				expect( function(){
					buildServiceWithSettings( badSettings );
				} ).toThrow( type = "ColdboxGraphQL.ConfigurationException" );
			} );

			it( "still builds successfully with valid schemaPaths (sanity check on the test harness itself)", function(){
				expect( function(){
					buildServiceWithSettings( duplicate( getRealSettings() ) );
				} ).notToThrow();
			} );

		} );
	}

	private struct function getRealSettings(){
		return getWireBox().getInstance( "GraphQLService@coldbox-graphql" ).getSettings();
	}

	/**
	 * Builds a fresh, independently-autowired GraphQLService (not the app's real
	 * singleton) with the given settings, and triggers the same buildSchema() call the
	 * real singleton gets at startup via onDIComplete().
	 */
	private void function buildServiceWithSettings( required struct settings ){
		var service = createObject( "component", "modroot.coldbox-graphql.models.GraphQLService" );
		getWireBox().autowire( service );
		service.setSettings( arguments.settings );
		service.onDIComplete();
	}

}
