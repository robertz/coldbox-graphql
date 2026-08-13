/**
 * Resolves the consuming app's optional customScalarProvider setting into an array
 * of already-built graphql.schema.GraphQLScalarType instances, ready to register
 * against RuntimeWiring at schema-build time.
 *
 * The module ships with zero custom scalars. The provider CFC (WireBox mapping named
 * by customScalarProvider) must implement getScalars(), returning an array of
 * graphql.schema.GraphQLScalarType Java objects it builds itself (see README for an
 * example using createDynamicProxy against graphql.schema.Coercing).
 *
 * IMPORTANT: the provider must build its GraphQLScalarType via
 * JavaClassFactory@coldbox-graphql (inject it — see README), not raw createObject() or
 * cbjavaloader directly. It has to resolve graphql-java classes through the exact same
 * classloader GraphQLService used for everything else, or registering the scalar throws
 * a "No matching Method/Function" type mismatch (confirmed empirically — see
 * models/JavaClassFactory.cfc for why).
 */
component singleton {

	property name="wirebox" inject="wirebox";

	array function getScalars( required string providerMapping ){
		if( !len( trim( arguments.providerMapping ) ) ){
			return [];
		}

		var provider = "";
		try{
			provider = wirebox.getInstance( arguments.providerMapping );
		} catch( "Injector.InstanceNotFoundException" e ){
			throw(
				type    = "ColdboxGraphQL.ConfigurationException",
				message = "customScalarProvider WireBox mapping does not exist: " & arguments.providerMapping
			);
		}

		if( !structKeyExists( provider, "getScalars" ) ){
			throw(
				type    = "ColdboxGraphQL.ConfigurationException",
				message = "customScalarProvider '" & arguments.providerMapping & "' must implement getScalars()."
			);
		}

		var scalars = provider.getScalars();

		if( !isArray( scalars ) ){
			throw(
				type    = "ColdboxGraphQL.ConfigurationException",
				message = "customScalarProvider.getScalars() must return an array of graphql.schema.GraphQLScalarType instances."
			);
		}

		return scalars;
	}

}
