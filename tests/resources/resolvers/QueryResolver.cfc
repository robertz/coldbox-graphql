component {

	any function widget( any source, required struct args, required any context, required any env ){
		return {
			"id"          : arguments.args.id,
			"name"        : "Test Widget",
			"description" : "A widget used for module tests."
		};
	}

	any function meta( any source, required struct args, required any context, required any env ){
		return { "version" : "1.0.0" };
	}

	any function contextCheck( any source, required struct args, required any context, required any env ){
		return isInstanceOf( arguments.context, "coldbox.system.web.context.RequestContext" ) ? "has-request-context" : "missing-context";
	}

	any function broken( any source, required struct args, required any context, required any env ){
		return { "brokenField" : "should never be reached" };
	}

}
