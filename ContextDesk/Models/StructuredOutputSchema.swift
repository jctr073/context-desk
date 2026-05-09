import Foundation

struct StructuredOutput: Decodable {
    let blocks: [OutputBlock]
}

enum StructuredOutputSchema {
    static let toolName = "emit_output"
    static let description = "Emit the ContextDesk response as an ordered list of typed blocks."
    static let responseFormatName = "writing_buddy_output"

    static let schema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["blocks"],
        "properties": [
            "blocks": [
                "type": "array",
                "items": [
                    "anyOf": [
                        Self.paragraphSchema,
                        Self.headingSchema,
                        Self.bulletListSchema,
                        Self.tableSchema,
                        Self.codeBlockSchema,
                        Self.toolCallSchema,
                        Self.toolResultSchema,
                    ]
                ]
            ]
        ]
    ]

    static let schemaData: Data = {
        // Sorted keys keeps the request body stable across builds and lets the
        // schema-snapshot test compare against a deterministic string.
        try! JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])
    }()

    private static let paragraphSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["kind", "text"],
        "properties": [
            "kind": ["const": "paragraph", "type": "string"],
            "text": ["type": "string"],
        ],
    ]

    private static let headingSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["kind", "text"],
        "properties": [
            "kind": ["const": "heading", "type": "string"],
            "text": ["type": "string"],
        ],
    ]

    private static let bulletListSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["kind", "items"],
        "properties": [
            "kind": ["const": "bulletList", "type": "string"],
            "items": [
                "type": "array",
                "items": ["type": "string"],
            ],
        ],
    ]

    private static let tableSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["kind", "head", "rows"],
        "properties": [
            "kind": ["const": "table", "type": "string"],
            "head": [
                "type": "array",
                "items": ["type": "string"],
            ],
            "rows": [
                "type": "array",
                "items": [
                    "type": "array",
                    "items": ["type": "string"],
                ],
            ],
        ],
    ]

    private static let codeBlockSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["kind", "code", "language"],
        "properties": [
            "kind": ["const": "codeBlock", "type": "string"],
            "code": ["type": "string"],
            // Nullable rather than optional so OpenAI strict mode accepts it
            // (strict requires every property listed in `properties` to also
            // appear in `required`).
            "language": ["type": ["string", "null"]],
        ],
    ]

    // Allowed by the schema but never instructed by the system prompt today.
    // Reserved so a future tool-using build can emit these without another
    // schema migration.
    private static let toolCallSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["kind", "id", "name", "arguments"],
        "properties": [
            "kind": ["const": "toolCall", "type": "string"],
            "id": ["type": "string"],
            "name": ["type": "string"],
            "arguments": ["type": "string"],
        ],
    ]

    private static let toolResultSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["kind", "call_id", "content", "is_error"],
        "properties": [
            "kind": ["const": "toolResult", "type": "string"],
            "call_id": ["type": "string"],
            "content": ["type": "string"],
            "is_error": ["type": "boolean"],
        ],
    ]
}

/// Wraps a pre-encoded JSON blob so it can be embedded inside an `Encodable`
/// request body without re-serializing the bytes.
struct RawJSON: Encodable {
    let data: Data

    init(_ data: Data) { self.data = data }

    func encode(to encoder: Encoder) throws {
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        try AnyEncodable(object).encode(to: encoder)
    }
}

private struct AnyEncodable: Encodable {
    let value: Any

    init(_ value: Any) { self.value = value }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let dict as [String: Any]:
            try container.encode(dict.mapValues(AnyEncodable.init))
        case let array as [Any]:
            try container.encode(array.map(AnyEncodable.init))
        case let string as String:
            try container.encode(string)
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case is NSNull:
            try container.encodeNil()
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Unsupported JSON value: \(type(of: value))"
                )
            )
        }
    }
}
