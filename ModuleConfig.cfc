/**
 * ColdBox GraphQL module.
 * Wraps graphql-java (vendored in /lib) to serve a GraphQL endpoint from
 * consumer-supplied SDL files. Ships with zero domain schema of its own.
 *
 * Depends on cbjavaloader, which loads this module's vendored jars at boot (see
 * onLoad() below). How graphql-java classes actually get instantiated is engine-aware
 * (see models/JavaClassFactory.cfc):
 *
 * - On BoxLang 1.8.0+, cbjavaloader uses BoxLang's native request classloader, so
 *   loader.create() and createDynamicProxy() share one classloader — no Application.bx
 *   changes needed at all.
 * - On Lucee / Adobe ColdFusion, cbjavaloader uses an isolated classloader. Mixing its
 *   objects with a createDynamicProxy() result throws "No matching Method/Function" —
 *   same class, two classloaders, incompatible runtime types (confirmed empirically).
 *   createDynamicProxy() has no per-call classpath override, so on these engines the
 *   whole module instead uses plain createObject() exclusively, which means the
 *   consuming app's own Application.cfc must still add this module's lib/ folder to
 *   this.javaSettings.loadPaths (see README) — cbjavaloader is loaded as a dependency
 *   but genuinely unused for object creation on these two engines.
 */
component {

	this.title              = "ColdBox GraphQL";
	this.author             = "Robert Zehnder";
	this.webURL              = "";
	this.description        = "Schema-agnostic GraphQL server module wrapping graphql-java.";
	this.version             = "0.1.0";

	// ColdBox module conventions
	this.cfmapping           = "coldbox-graphql";
	this.autoMapModels       = true;
	this.dependencies        = [ "cbjavaloader" ];

	/**
	 * Module settings. All overridable from the consuming app's config/ColdBox.cfc
	 * via moduleSettings["coldbox-graphql"] = { ... }.
	 */
	function configure(){

		settings = {
			// Required: array of paths (files, directories, or wildcard globs) to .graphqls SDL files.
			schemaPaths          : [],
			// Required: WireBox package resolvers live under, e.g. "models.resolvers".
			// Convention: {resolverBasePackage}.{TypeName}Resolver, method {fieldName}().
			resolverBasePackage  : "models.resolvers",
			// HTTP path the GraphQL endpoint is exposed at.
			basePath             : "/graphql",
			// Whether introspection (__schema/__type) is enabled. Default true; set explicitly in prod.
			enableIntrospection  : true,
			// Optional WireBox mapping name of a CFC that returns an array of prebuilt
			// graphql.schema.GraphQLScalarType instances, invoked once at schema-build time.
			customScalarProvider : ""
		};

		// Wire the GraphQL engine as a WireBox singleton. Construction itself (schema
		// parse + wiring) is deferred to GraphQLService, and is forced to happen eagerly
		// at startup (not on first request) from onLoad() below.
		binder.map( "GraphQLService@coldbox-graphql" )
			.to( "#moduleMapping#.models.GraphQLService" )
			.asSingleton();

		binder.map( "ScalarRegistry@coldbox-graphql" )
			.to( "#moduleMapping#.models.ScalarRegistry" )
			.asSingleton();

		binder.map( "JavaClassFactory@coldbox-graphql" )
			.to( "#moduleMapping#.models.JavaClassFactory" )
			.asSingleton();
	}

	function onLoad(){
		// Append our vendored jars to the shared cbjavaloader instance (additive — does
		// not disturb loadPaths any other module or the consuming app has configured).
		// Must happen before GraphQLService is built. this.dependencies above guarantees
		// cbjavaloader itself is already loaded and activated by this point. Harmless on
		// Lucee/ACF even though unused there for object creation (see class doc above).
		wirebox.getInstance( "loader@cbjavaloader" ).appendPaths( modulePath & "/lib" );

		// Force eager construction of the GraphQL singleton so schema parsing and
		// resolver wiring happen once, at application startup.
		wirebox.getInstance( "GraphQLService@coldbox-graphql" );

		// Self-register the HTTP route directly against the app's live router, mirroring
		// basePath exactly. Deliberately NOT using ColdBox's module Router.cfc/entryPoint
		// convention: that mechanism only activates when this.entryPoint is set, and it
		// then forces every route the module owns under a "/{entryPoint}/..." URL prefix —
		// incompatible with an arbitrary, consumer-configurable top-level basePath.
		var graphQLBasePath = controller.getModuleSettings(
			module       = "coldbox-graphql",
			setting      = "basePath",
			defaultValue = "/graphql"
		);
		// Prepended (append=false): the default convention route (/:handler/:action)
		// is checked first-match-wins and would otherwise swallow our pattern, since
		// it's registered before any module gets a chance to add its own routes.
		var appRouter = wirebox.getInstance( "router@coldbox" );
		appRouter.addRoute(
			pattern = graphQLBasePath,
			event   = "coldbox-graphql:GraphQLHandler.execute",
			verbs   = "POST",
			append  = false
		);
	}

	function onUnload(){
	}

}
