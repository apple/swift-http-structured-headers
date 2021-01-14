# swift-http-structured-headers

A Swift implementation of the HTTP Structured Header Field specification.

Provides parsing and serialization facilities for structured header fields, as well as implementations of `Encoder` and `Decoder` to allow using `Codable` data types as the payloads of HTTP structured header fields.

## About Structured Header Fields

HTTP Structured Header fields are [a draft specification](https://tools.ietf.org/html/draft-ietf-httpbis-header-structure-19) being worked on by the IETF. They provide a set of data types and algorithms for handling HTTP header field values in a consistent way, allowing a single parser and serializer to handle a wide range of header field values.

## Swift HTTP Structured Header Fields

This package provides a parser and serializer that match draft 19 of the working group's draft specification. They are entirely complete, able to handle all valid HTTP structured header fields. This package also provides `Encoder` and `Decoder` objects for working with Codable in Swift. This allows rapid prototyping and experimentation with HTTP structured header fields, as well as interaction with the wider Swift Codable community.

This package provides two top-level modules: `StructuredHeaders` and `CodableStructuredHeaders`.

The base module, `StructuredHeaders`, provides a low-level implementation of a serializer and parser. Both of these have been written to avoid using Foundation, making them suitable for a range of use-cases where Foundation is not available. They rely entirely on the Swift standard library and are implemented as generically as possible. One of the limitations due to the absence of Foundation is that this interface is not capable of performing Base64 encoding or decoding: users are free to bring whatever encoder and decoder they choose to use.

This API is low-level, exposing the raw parse tree as the format for the serializer and parser. This allows high-performance and high-flexibility parsing and serialization, at the cost of being verbose and complex. Users are required to understand the structured header format and to operate the slightly awkward types, but maximal fidelity is retained and the performance overhead is low.

The upper-level module, `CodableStructuredHeaders`, brings along the `Encoder` and `Decoder` and also adds a dependency on Foundation. This Foundation dependency is necessary to correctly handle the base64 formatting, as well as to provide a good natural container for binary data: `Data`. This interface is substantially friendlier and easier to work with, using Swift's `Codable` support to provide a great user experience.

In most cases users should prefer to use `CodableStructuredHeaders` unless they know they need the performance advantages of  `StructuredHeaders`. The experience will be much better.

## Working with Structured Header Fields

`swift-http-structured-headers` has a simply, easy-to-use high-level API for working with structured header fields. To begin with, let's consider the [HTTP Client Hints draft specification](https://tools.ietf.org/html/draft-ietf-httpbis-client-hints-15). This defines the following new header field:

>    The Accept-CH response header field indicates server support for the hints indicated in its value.  Servers wishing to receive user agent information through Client Hints SHOULD add Accept-CH response header to their responses as early as possible.
>
> Accept-CH is a Structured Header. Its value MUST be an sf-list whose members are tokens. Its ABNF is:
>
>     Accept-CH = sf-list
>
> For example:
>
>     Accept-CH: Sec-CH-Example, Sec-CH-Example-2

`swift-http-structured-headers` can parse and serialize this field very simply:

```swift
let field = Array("Sec-CH-Example, Sec-CH-Example-2".utf8)

struct AcceptCH: StructuredHeaderField {
    static let structuredFiedType: StructuredHeaderFieldType = .list
    
    var items: [String]
}

// Decoding
let decoder = StructuredFieldDecoder()
let parsed = try decoder.decode(AcceptCH.self, from: field)

// Encoding
let encoder = StructuredFieldEncoder()
let serialized = try encoder.encode(AcceptCH(items: ["Sec-CH-Example", "Sec-CH-Example-2"]))
```

However, structured header fields can be substantially more complex. Structured header fields can make use of 4 containers and 6 base item types. The containers are:

1. Dictionaries. These are top-level elements and associate token keys with values. The values may be items, or may be inner lists, and each value may also have parameters associated with them. `CodableStructuredHeaders` can model dictionaries as either Swift objects (where the property names are dictionary keys).
2. Lists. These are top-level elements, providing a sequence of items or inner lists. Each item or inner list may have parameters associated with them. `CodableStructuredHeaders` models these as Swift objects with one key, `items`, that must be a collection of entries.
3. Inner Lists. These are lists that may be sub-entries of a dictionary or a list. The list entries are items, which may have parameters associated with them: additionally, an inner list may have parameters associated with itself as well. `CodableStructuredHeaders` models these as either Swift `Array`s _or_, if it's important to extract parameters, as a two-field Swift `struct` where one field is called `items` and contains an `Array`, and other field is called `parameters` and contains a dictionary.
4. Parameters. Parameters associated token keys with items without parameters. These are used to store metadata about objects within a field. `CodableStructuredHeaders` models these as either Swift objects (where the property names are the parameter keys) or as Swift dictionaries.

The base types are:

1. Booleans. `CodableStructuredHeaders` models these as Swift's `Bool` type.
2. Integers. `CodableStructuredHeaders` models these as any fixed-width integer type.
3. Decimals. `CodableStructuredHeaders` models these as any floating-point type, or as Foundation's `Decimal`.
4. Tokens. `CodableStructuredHeaders` models these as Swift's `String` type, where the range of characters is restricted.
5. Strings. `CodableStructuredHeaders` models these as Swift's `String` type.
6. Binary data. `CodableStructuredHeaders` models this as Foundation's `Data` type.

For any Structured Header Field Item, the item may either be represented directly by the appropriate type, or by a Swift struct with two properties: `item` and `parameters`. This latter mode is how parameters on a given item may be captured.

The top-level structured header field must identify what kind of header field it corresponds to: `.item`, `.list`, or `.dictionary`. This is inherent in the type of the field and will be specified in the relevant field specification.

## Lower Levels

In some cases the Codable interface will not be either performant enough or powerful enough for the intended use-case. In cases like this, users can use the types in the `StructuredHeaders` module instead.

There are two core types: `StructuredFieldParser` and `StructuredFieldSerializer`. Rather than work with high-level Swift objects, these two objects either produce or accept a Swift representation of the data tree for a given structured header field.

This exposes the maximum amount of information about the header field. It allows users to handle situations where Codable cannot necessarily provide the relevant information, such in cases where dictionary ordering is semantic, or where it's necessary to control whether fields are tokens or strings more closely.

These APIs also have lower overhead than the `CodableStructuredHeaders` APIs.

The cost is that the APIs are substantially more verbose. Consider the above header field, `Accept-CH`. To parse or serialize this in `StructuredHeaders` would look like this:

```swift
let field = Array("Sec-CH-Example, Sec-CH-Example-2".utf8)
var parser = StructuredFieldParser(field)
let parsed = parser.parseListField()

print(parsed)
// [
//     .item(Item(bareItem: .token("Sec-CH-Example"), parameters: [])),
//     .item(Item(bareItem: .token("Sec-CH-Example-2"), parameters: [])),
// ]

var serializer = StructuredFieldSerializer()
let serialized = serializer.writeListHeader(parsed)
```

Notice the substantially more verbose types involved in this operation. These types are highly generic, giving the opportunity for parsing and serializing that greatly reduces the runtime overhead. They also make it easier to distinguish between tokens and strings, and to observe the order of objects in dictionaries or parameters, which can be lost at the Codable level.

In general, users should consider this API only when they are confident they need either the flexibility or the performance. This may be valuable for header fields that do not evolve often, or that are highly dynamic.

