import Foundation
import Testing
@testable import Shep

struct JSONValueTests {
    @Test func eachKindOfValueIsDecoded() throws {
        let value = try #require(JSONValue(json: Data(#"{"a":null,"b":true,"c":3,"d":1.5,"e":"x","f":[1,"y"],"g":{"h":0}}"#.utf8)))
        #expect(value == ["a": .null, "b": true, "c": 3, "d": .double(1.5), "e": "x", "f": [1, "y"], "g": ["h": 0]])
    }

    @Test func aValueIsTheSameAfterEncodeAndDecode() throws {
        let value: JSONValue = ["spaces": [["id": "sp1", "extra": ["deep": [true, .null, 2]]]], "version": 43]
        #expect(JSONValue(json: value.encoded()) == value)
    }

    @Test func aBooleanIsNotReadAsANumber() throws {
        #expect(JSONValue(json: Data("true".utf8)) == .bool(true))
        #expect(JSONValue(json: Data("1".utf8)) == .int(1))
    }

    @Test func aSubscriptReadsAndSetsAField() {
        var value: JSONValue = ["name": "one"]
        #expect(value["name"].string == "one")
        #expect(value["absent"].isNull)
        value["name"] = "two"
        #expect(value["name"].string == "two")
    }
}
