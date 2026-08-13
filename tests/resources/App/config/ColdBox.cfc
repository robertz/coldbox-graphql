component {

	function configure(){

		coldbox = {
			appName                  : "coldboxGraphqlTestHarness",
			handlersIndexAutoReload  : true,
			conventions              : {
				modulesLocation : "modules_app"
			},
			modulesExternalLocation : [ "/modroot", "/localmodules" ]
		};

		// Scanning modulesExternalLocation's real parent directory would otherwise pick up
		// unrelated sibling projects on disk — load only this module (+ cbjavaloader, for
		// the createDynamicProxy-compatibility experiment).
		modules = {
			include : [ "coldbox-graphql", "cbjavaloader" ]
		};

		moduleSettings = {
			"coldbox-graphql" = {
				schemaPaths          : [ getDirectoryFromPath( getCurrentTemplatePath() ) & "../../test-schema.graphqls" ],
				resolverBasePackage  : "resolvers",
				basePath             : "/graphql",
				enableIntrospection  : true
			}
			// NOTE: deliberately no "cbjavaloader" moduleSettings here — a real consuming
			// app wouldn't configure this either. Only our own module's ModuleConfig.cfc
			// onLoad() -> appendPaths() call should be responsible for this.
		};

	}

}
