component {

	this.name               = "coldboxGraphqlTestHarness";
	this.sessionManagement   = true;
	this.setClientCookies    = true;
	this.applicationTimeout  = createTimeSpan( 0, 1, 0, 0 );
	this.sessionTimeout      = createTimeSpan( 0, 1, 0, 0 );

	this.mappings[ "/testharness" ] = getDirectoryFromPath( getCurrentTemplatePath() );
	this.mappings[ "/coldbox" ]     = getDirectoryFromPath( getCurrentTemplatePath() ) & "../../../coldbox";
	this.mappings[ "/testbox" ]     = getDirectoryFromPath( getCurrentTemplatePath() ) & "../../../testbox";
	this.mappings[ "/specs" ]       = getDirectoryFromPath( getCurrentTemplatePath() ) & "../../../tests/specs";
	// Parent of the module's own repo root, so ColdBox discovers the real module
	// directory directly (avoids a modules_app symlink, which breaks handler
	// discovery — Lucee canonicalizes symlinked paths when deriving dotted
	// invocation paths from a directory scan).
	this.mappings[ "/modroot" ]     = getDirectoryFromPath( getCurrentTemplatePath() ) & "../../../..";
	this.mappings[ "/localmodules" ] = getDirectoryFromPath( getCurrentTemplatePath() ) & "../../../modules";

	// Still required on Lucee/ACF — see ModuleConfig.cfc / README. cbjavaloader loads the
	// module's jars for everything except createDynamicProxy(), which has no per-call
	// classpath override and needs the classes on the real app classpath.
	// Still required on Lucee/ACF — see ModuleConfig.cfc / README. cbjavaloader loads the
	// module's jars for everything except createDynamicProxy(), which has no per-call
	// classpath override and needs the classes on the real app classpath.
	this.javaSettings = {
		loadPaths               : [ getDirectoryFromPath( getCurrentTemplatePath() ) & "../../../lib" ],
		loadColdFusionClassPath : true,
		reloadOnChange          : false
	};

	function onApplicationStart(){
		application.cbBootstrap = new coldbox.system.Bootstrap(
			COLDBOX_CONFIG_FILE   = "",
			COLDBOX_APP_ROOT_PATH = getDirectoryFromPath( getCurrentTemplatePath() ),
			COLDBOX_APP_MAPPING   = ""
		);
		application.cbBootstrap.loadColdbox();
		return true;
	}

	function onRequestStart( targetPage ){
		if( structKeyExists( url, "fwreinit" ) ){
			application.cbBootstrap.loadColdbox();
		}
		application.cbBootstrap.onRequestStart( arguments.targetPage );
		return true;
	}

}
