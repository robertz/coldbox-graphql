/**
 * Deliberately has its own broken WireBox dependency. Used to prove
 * DataFetcherAdapter.ensureResolverResolved() surfaces this as a real error instead of
 * silently treating it the same as "no resolver exists for this type."
 */
component {

	property name="doesNotExist" inject="totallyMissingMapping@nowhere";

	any function brokenField( any source, required struct args, any context, any env ){
		return "unreachable";
	}

}
