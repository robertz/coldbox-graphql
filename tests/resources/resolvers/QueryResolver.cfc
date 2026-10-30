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

	any function echo( any source, required struct args, required any context, required any env ){
		var input = arguments.args.input;
		var tags  = [];
		if( !isNull( input.tags ) ){
			// an index loop: Lucee's map() skips null elements
			for( var i = 1; i <= arrayLen( input.tags ); i++ ){
				arrayAppend( tags, arrayIsDefined( input.tags, i ) ? input.tags[ i ] : "null" );
			}
		}
		return input.name
			& "|" & ( isNull( input.tags ) ? "none" : arrayToList( tags ) )
			& "|" & ( isNull( input.note ) ? "null" : input.note )
			& "|" & ( isNull( input.child ) ? "null" : input.child.label );
	}

}
