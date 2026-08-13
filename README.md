# coldbox-graphql

A schema-agnostic ColdBox module that wraps [graphql-java](https://www.graphql-java.com/) (vendored, v26.0) to serve a GraphQL API from SDL files you supply. The module ships with zero domain schema of its own — it parses your `.graphqls` files, wires resolvers by convention, and exposes a standard `POST /graphql` endpoint.

Depends on [cbjavaloader](https://forgebox.io/view/cbjavaloader) to load its vendored jars at boot. Verified end-to-end (schema build, resolver wiring, real HTTP round-trip) on both Lucee 5.4.8.2 and BoxLang 1.16.0. See **Engine compatibility** below before deploying to Adobe ColdFusion.

## Installation

```bash
box install coldbox-graphql
```

The HTTP route is registered automatically at startup, mirroring whatever you set as `basePath` (default `/graphql`) — nothing to wire up.

### BoxLang 1.8.0+

Nothing else to do. cbjavaloader uses BoxLang's native request classloader, so the module loads and wires everything — including implementing `graphql.schema.DataFetcher` from your resolver CFCs — without touching `Application.bx`. Verified end-to-end on BoxLang 1.16.0 with zero `Application.bx` changes: schema build, explicit-resolver precedence, `PropertyDataFetcher` fallback, and a real HTTP round-trip through `POST /graphql` all pass.

Note: ColdBox 7.5.2 does not boot cleanly on BoxLang 1.16.0 in this testing (an internal interceptor-metadata mismatch fails before any module even loads) — use **ColdBox 8+** with BoxLang. Likewise TestBox needs **7+** for BoxLang (5.x assumes a `server.coldfusion` key that doesn't exist on BoxLang's `server` scope). Neither is specific to this module; both are noted here because they'll block you before you get anywhere near it.

### Lucee / Adobe ColdFusion — one required step

In your app's `Application.cfc`:

```cfscript
this.javaSettings = {
    loadPaths               : [ "/modules_app/coldbox-graphql/lib" ], // adjust to your module install path
    loadColdFusionClassPath : true,
    reloadOnChange          : false
};
```

This is required because `createDynamicProxy()` — used to implement `graphql.schema.DataFetcher` from your resolver CFCs — has no per-call classpath override the way `createObject()` or cbjavaloader do; it can only resolve interfaces already on the real application classpath. This isn't a config choice within the module's control: on these two engines, cbjavaloader loads jars into an *isolated* classloader, and mixing objects from that loader with a `createDynamicProxy()` result throws a "No matching Method/Function" error at the first point they interact — same class, same jar, but two different classloaders producing incompatible runtime types (confirmed empirically while building this). So on Lucee/ACF the module uses plain `createObject()` exclusively instead — cbjavaloader is still loaded as a dependency but genuinely unused for object creation on these two engines — and that requires the classes on the real classpath via `this.javaSettings`.

## Adding your schema

Create a `graphql/schema/` directory at your app root and put your `.graphqls` files there:

```
myapp/
├── config/
├── graphql/
│   └── schema/
│       ├── schema.graphqls
│       └── widgets.graphqls
├── handlers/
├── models/
└── ...
```

Point `schemaPaths` at the directory — every `*.graphqls` file in it is parsed and merged into one schema automatically (see `resolveSchemaFiles()` in `models/GraphQLService.cfc`):

```cfscript
moduleSettings = {
    "coldbox-graphql" = {
        schemaPaths : [ "/graphql/schema" ]
    }
};
```

### Example: splitting a schema across files

`graphql/schema/schema.graphqls` — operations:

```graphql
type Query {
    widget(id: ID!): Widget
    widgets: [Widget!]!
}

type Mutation {
    createWidget(name: String!): Widget!
}
```

`graphql/schema/widgets.graphqls` — the domain type it refers to:

```graphql
type Widget {
    id: ID!
    name: String!
    slug: String
}
```

Both files get parsed and merged before validation, so forward references across files (`Widget` used in `schema.graphqls`, defined in `widgets.graphqls`) resolve fine regardless of file order. You can also split operations themselves across files with GraphQL's `extend` keyword — e.g. a `widgets.graphqls` that starts with `extend type Query { widget(id: ID!): Widget }` instead of defining `Query` directly — useful once you have enough domains that a single growing `Query`/`Mutation` block gets unwieldy.

A single `schemaPaths` entry can also point directly at one file, or a wildcard like `/graphql/schema/*.graphqls`, if you'd rather be explicit than glob a whole directory.

## Module settings

Set these in your app's `config/ColdBox.cfc`:

```cfscript
moduleSettings = {
    "coldbox-graphql" = {
        schemaPaths          : [ "/graphql/schema" ],
        resolverBasePackage  : "models.resolvers",
        basePath             : "/graphql",
        enableIntrospection  : true,
        customScalarProvider : ""
    }
};
```

| Setting | Required | Default | Description |
|---|---|---|---|
| `schemaPaths` | Yes | — | Array of paths to `.graphqls` files. Each entry may be a literal file, a directory (all `*.graphqls` files in it), or a wildcard (`/path/*.graphqls`). All files are parsed and merged into one schema. Module load fails fast if this is empty or any path doesn't resolve to a file. See *Adding your schema* above for the recommended `graphql/schema/` layout. |
| `resolverBasePackage` | Yes | — | WireBox package resolvers live under, e.g. `models.resolvers`. Must point to a directory reachable from your app root (WireBox resolves it the same way it resolves any dotted component path). |
| `basePath` | No | `/graphql` | The URL the module registers `POST` for automatically at startup. |
| `enableIntrospection` | No | `true` | Set `false` in production if you don't want `__schema`/`__type` queries answered. |
| `customScalarProvider` | No | `""` | WireBox mapping name of a CFC that returns custom `GraphQLScalarType` instances (see below). |

## Resolver convention

For a schema type `TypeName` with field `fieldName`, the module looks for a WireBox mapping at `{resolverBasePackage}.{TypeName}Resolver` and, if it exists and implements a `fieldName()` method, calls it. Otherwise it falls back to graphql-java's `PropertyDataFetcher` — reading a same-named key off the parent object. This means **you only write a resolver for fields that need custom logic**; a struct with matching keys just works.

Resolver methods receive four named arguments:

```cfscript
any function fieldName( any source, struct args, any context, any env ){
    // source  — the parent object (struct/whatever the parent resolver returned).
    //           NULL for root Query/Mutation fields — don't mark it `required`.
    // args    — the field's GraphQL arguments, as an ordinary CFML struct/array
    //           (already converted from graphql-java's raw Map — case-insensitive
    //           dot access works as normal).
    // context — the ColdBox `event` (RequestContext) for the current request, so you can
    //           reach rc/prc, headers, session, etc. via the normal ColdBox API.
    // env     — the raw graphql.schema.DataFetchingEnvironment, for advanced use.
}
```

### Example

`schema.graphqls`:

```graphql
type Query {
    widget(id: ID!): Widget
}

type Widget {
    id: ID!
    name: String
    slug: String
}
```

`models/resolvers/QueryResolver.cfc`:

```cfscript
component {
    property name="widgetService" inject="WidgetService";

    any function widget( any source, required struct args, any context, any env ){
        return widgetService.get( args.id ); // returns a struct with id/name/slug
    }
}
```

No `WidgetResolver.cfc` is needed at all — `id`, `name`, and `slug` all resolve via `PropertyDataFetcher` off the struct `widget()` returned. If you later need `slug` computed rather than stored, add `models/resolvers/WidgetResolver.cfc` with just a `slug()` method; `id` and `name` keep resolving automatically.

### Mutations

`Mutation` gets no special treatment — it's just another object type name to the wiring loop in `GraphQLService.wireResolvers()`, so it follows the exact same `{resolverBasePackage}.{TypeName}Resolver` convention as `Query`, with the exact same four named arguments (`source`, `args`, `context`, `env`).

Extending the schema above with a mutation:

```graphql
type Mutation {
    createWidget(name: String!): Widget!
    deleteWidget(id: ID!): Boolean!
}
```

`models/resolvers/MutationResolver.cfc`:

```cfscript
component {
    property name="widgetService" inject="WidgetService";

    any function createWidget( any source, required struct args, any context, any env ){
        return widgetService.create( args.name ); // returns a struct with id/name/slug
    }

    boolean function deleteWidget( any source, required struct args, any context, any env ){
        return widgetService.delete( args.id );
    }
}
```

The result of `createWidget` flows back through the schema exactly like a query result does — since it returns a struct shaped like `Widget`, the `id`/`name`/`slug` fields on the response resolve via the same `PropertyDataFetcher` fallback, no extra wiring needed.

One thing the module does *not* do anything special for: per the GraphQL spec, top-level mutation fields in a single request execute serially, in the order they appear in the query, rather than in parallel like top-level query fields. That's handled entirely by graphql-java's own execution strategy once it sees a `Mutation` root type — nothing to configure here.

**Not implemented in this version:** interface/union `TypeResolver` wiring — every object type gets its own convention-based resolver, but resolving *which* concrete type implements an interface/union at runtime is not wired up.

## Custom scalars

The module ships no custom scalars. To add one, point `customScalarProvider` at a WireBox mapping for a CFC implementing `getScalars()`, returning an array of already-built `graphql.schema.GraphQLScalarType` instances. Build them via the module's own `JavaClassFactory@coldbox-graphql` — not raw `createObject()` — so your scalar resolves graphql-java classes through the exact same classloader as everything else in the module (see *Design notes*: mixing classloaders throws a "No matching Method/Function" error where they interact):

```cfscript
// moduleSettings["coldbox-graphql"].customScalarProvider = "models.MyScalarProvider"
component {
    property name="javaClass" inject="JavaClassFactory@coldbox-graphql";

    array function getScalars(){
        var coercing = createDynamicProxy( new DateTimeCoercing(), "graphql.schema.Coercing" );
        var scalar = javaClass.create( "graphql.schema.GraphQLScalarType" )
            .newScalar()
            .name( "DateTime" )
            .description( "ISO-8601 date-time" )
            .coercing( coercing )
            .build();
        return [ scalar ];
    }
}
```

`DateTimeCoercing.cfc` implements `graphql.schema.Coercing`'s three methods (`serialize`, `parseValue`, `parseLiteral`) as ordinary CFML functions.

## HTTP endpoint

`POST {basePath}` (default `/graphql`) accepts the standard GraphQL request body:

```json
{ "query": "...", "variables": {}, "operationName": null }
```

and returns the standard shape:

```json
{ "data": { ... }, "errors": [ { "message": "..." } ] }
```

Validation errors and resolver exceptions are captured by graphql-java itself into the `errors` array — they never surface as raw ColdBox exception pages. A malformed request body (not valid JSON, or missing `query`) returns HTTP 400 in the same shape.

## Exposing the schema programmatically

`GraphQLService.getSchema()` returns the raw `graphql.schema.GraphQLSchema` object the module built from your `.graphqls` files — inject `GraphQLService@coldbox-graphql` anywhere and call it:

```cfscript
property name="graphQLService" inject="GraphQLService@coldbox-graphql";

var schema = graphQLService.getSchema();
```

That's a live graphql-java object, useful for anything graphql-java itself supports — most commonly, printing it back out as SDL text via `graphql.schema.idl.SchemaPrinter`, e.g. for docs, `graphql-codegen`-style client tooling, or a `GET /schema` endpoint. Build it via `JavaClassFactory@coldbox-graphql`, same as everywhere else in the module (see *Design notes* on why that matters):

```cfscript
component {
    property name="javaClass"      inject="JavaClassFactory@coldbox-graphql";
    property name="graphQLService" inject="GraphQLService@coldbox-graphql";

    function execute( event, rc, prc ){
        // Options suppress graphql-java's built-in directives (@skip, @include, etc.)
        // and the `schema { query: Query }` block — left in, they're valid SDL but
        // noisy for anything meant to be read or fed to codegen.
        var options = javaClass.create( "graphql.schema.idl.SchemaPrinter$Options" )
            .defaultOptions()
            .includeDirectiveDefinitions( false )
            .includeSchemaDefinition( false );

        var printer = javaClass.create( "graphql.schema.idl.SchemaPrinter" ).init( options );
        var sdl = printer.print( graphQLService.getSchema() );

        event.renderData( type = "text", data = sdl );
    }
}
```

This is separate from GraphQL's own introspection (`__schema`/`__type` queries over `POST {basePath}`, controlled by `enableIntrospection`) — introspection answers questions about the schema at query time over the wire; `getSchema()`/`SchemaPrinter` give you the schema itself, in CFML, for anything that needs the actual `.graphqls` text or the schema object directly.

## Engine compatibility

- **Lucee**: fully tested (5.4.8.2), including the cbjavaloader + `this.javaSettings` split described above.
- **BoxLang**: fully tested (1.16.0) against a real running server — schema build, resolver wiring (both `PropertyDataFetcher` fallback and explicit-resolver precedence), and a real HTTP round-trip through `POST /graphql` all pass with zero `Application.bx` changes. Requires ColdBox 8+ and TestBox 7+ (see install notes above) — those constraints are about ColdBox/TestBox's own BoxLang support, not this module.
- **Adobe ColdFusion**: not tested. ACF supports `createDynamicProxy()`, `this.javaSettings`, and cbjavaloader, so the same Lucee code path should work, but has not been verified.

## Running the module's own tests

```bash
box install
```

then start `tests/resources/App` as a CommandBox server (webroot = that directory) and hit `/testrunner.cfm`. See `tests/resources/App/config/ColdBox.cfc` for the exact settings a consuming app needs (it *is* a minimal consuming app).

### What's covered

13 specs across three files, verified live on both Lucee and BoxLang:

- **`tests/specs/GraphQLServiceSpec.cfc`** — the resolver convention in-process: `PropertyDataFetcher` fallback, explicit-resolver precedence, missing-resolver-class fallback, and spec-shaped errors for an invalid query.
- **`tests/specs/GraphQLHandlerSpec.cfc`** — the real thing end-to-end, real HTTP POSTs against the running `/graphql` route: the happy path, a malformed request body, and a handful of regression tests for specific bugs found and fixed during a code review — a non-string `query`/`operationName` (used to crash uncaught instead of returning a graceful 400), resolvers actually receiving the ColdBox `event` as `context` (used to always be null), and a resolver with its own broken WireBox dependency surfacing as a real error (used to silently fall back to `PropertyDataFetcher` instead).
- **`tests/specs/GraphQLServiceConfigSpec.cfc`** — startup config validation: a bad wildcard `schemaPaths` directory now fails fast at build time instead of silently dropping that schema fragment. These specs build their own throwaway `GraphQLService` instance (via `getWireBox().autowire()` + `setSettings()`) rather than touching the app's real singleton — the reason `GraphQLService.cfc` has `accessors="true"`.

Not covered by dedicated tests: two internal caching optimizations (`JavaClassFactory`'s class-handle cache, `DataFetcherAdapter`'s per-field `PropertyDataFetcher` cache) — both are already exercised indirectly by every other spec (many distinct classes/fields resolving correctly across dozens of calls), so a dedicated test would mostly be reflecting into cache internals rather than asserting on observable behavior.
