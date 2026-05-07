import XCTest
@testable import ContextDesk

final class StructuredOutputSchemaTests: XCTestCase {
    func testRootIsStrictObject() throws {
        let schema = StructuredOutputSchema.schema
        XCTAssertEqual(schema["type"] as? String, "object")
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        XCTAssertEqual(schema["required"] as? [String], ["blocks"])
    }

    func testBlocksItemsHasFiveAnyOfBranches() throws {
        let schema = StructuredOutputSchema.schema
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let blocks = try XCTUnwrap(properties["blocks"] as? [String: Any])
        XCTAssertEqual(blocks["type"] as? String, "array")
        let items = try XCTUnwrap(blocks["items"] as? [String: Any])
        let anyOf = try XCTUnwrap(items["anyOf"] as? [[String: Any]])
        XCTAssertEqual(anyOf.count, 5)

        let kinds = anyOf.compactMap { branch -> String? in
            let props = branch["properties"] as? [String: Any]
            let kind = props?["kind"] as? [String: Any]
            return kind?["const"] as? String
        }
        XCTAssertEqual(Set(kinds), Set(["paragraph", "heading", "bulletList", "table", "codeBlock"]))
    }

    func testEveryBranchIsStrictObject() throws {
        let schema = StructuredOutputSchema.schema
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let blocks = try XCTUnwrap(properties["blocks"] as? [String: Any])
        let items = try XCTUnwrap(blocks["items"] as? [String: Any])
        let anyOf = try XCTUnwrap(items["anyOf"] as? [[String: Any]])

        for branch in anyOf {
            XCTAssertEqual(branch["type"] as? String, "object")
            XCTAssertEqual(branch["additionalProperties"] as? Bool, false)
            let required = try XCTUnwrap(branch["required"] as? [String])
            let properties = try XCTUnwrap(branch["properties"] as? [String: Any])
            XCTAssertEqual(Set(required), Set(properties.keys),
                           "Strict mode requires every property to also appear in `required`")
        }
    }

    func testCodeBlockLanguageIsNullable() throws {
        let schema = StructuredOutputSchema.schema
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let blocks = try XCTUnwrap(properties["blocks"] as? [String: Any])
        let items = try XCTUnwrap(blocks["items"] as? [String: Any])
        let anyOf = try XCTUnwrap(items["anyOf"] as? [[String: Any]])

        let codeBranch = try XCTUnwrap(anyOf.first { branch in
            let props = branch["properties"] as? [String: Any]
            let kind = props?["kind"] as? [String: Any]
            return (kind?["const"] as? String) == "codeBlock"
        })
        let codeProps = try XCTUnwrap(codeBranch["properties"] as? [String: Any])
        let language = try XCTUnwrap(codeProps["language"] as? [String: Any])
        let types = try XCTUnwrap(language["type"] as? [String])
        XCTAssertEqual(Set(types), Set(["string", "null"]))
    }

    func testSchemaDataIsValidSortedJSON() throws {
        let data = StructuredOutputSchema.schemaData
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["type"] as? String, "object")
        // Re-serialize and confirm the bytes round-trip; .sortedKeys means we
        // get a stable hash if no schema changes are intended.
        let resorted = try JSONSerialization.data(withJSONObject: object as Any, options: [.sortedKeys])
        XCTAssertEqual(data, resorted)
    }
}
