<cfscript>
	testbox = new testbox.system.TestBox( directory = { mapping = "/specs", recurse = true }, reporter = "json" );
	writeOutput( testbox.run() );
</cfscript>
