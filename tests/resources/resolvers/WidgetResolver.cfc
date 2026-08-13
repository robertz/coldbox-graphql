component {

	// Explicit resolver: must take precedence over PropertyDataFetcher for `name`.
	string function upperName( required any source, required struct args, required any context, required any env ){
		return ucase( arguments.source.name );
	}

}
