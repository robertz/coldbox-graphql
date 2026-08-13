/**
 * Resolves graphql-java classes consistently for the running engine.
 *
 * On BoxLang 1.8.0+, cbjavaloader uses BoxLang's native request classloader, so classes
 * it loads and classes createDynamicProxy() resolves share the same classloader — safe
 * to use loader.create() everywhere.
 *
 * On Lucee/Adobe ColdFusion, cbjavaloader uses an isolated URLClassLoader. Mixing objects
 * from that loader with a createDynamicProxy() result (which can only resolve interfaces
 * via the real application classpath) throws "No matching Method/Function" at the
 * boundary — same class name, same jar, but two different classloaders produced
 * incompatible runtime types. So on these engines we use plain createObject()
 * exclusively instead, which requires this.javaSettings in the consuming app (see
 * README) but keeps every graphql-java object on the one classloader that
 * createDynamicProxy() also uses.
 */
component singleton {

	property name="loader" inject="loader@cbjavaloader";

	variables.isBoxLang  = false;
	// Class handles are cached by name — cheap and safe to reuse: create() only resolves
	// the class reference, it never instantiates. Every caller still calls .init(...)/a
	// static factory method (e.g. PropertyDataFetcher.fetching(fieldName)) on the returned
	// handle themselves, so a cached handle still produces an independent result each time.
	variables.classCache = {};

	function onDIComplete(){
		variables.isBoxLang = structKeyExists( server, "boxlang" );
	}

	any function create( required string className ){
		if( !structKeyExists( variables.classCache, arguments.className ) ){
			variables.classCache[ arguments.className ] = variables.isBoxLang
				? loader.create( arguments.className )
				: createObject( "java", arguments.className );
		}
		return variables.classCache[ arguments.className ];
	}

}
