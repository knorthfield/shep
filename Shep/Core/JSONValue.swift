import Foundation

/// Any JSON value. The core's records and documents stay in this form,
/// so that fields that Shep does not know are kept.
enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    init?(json: Data) {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: json) else { return nil }
        self = value
    }

    /// The value as one line of JSON.
    func encoded() -> Data {
        // A JSONValue always encodes.
        (try? JSONEncoder().encode(self)) ?? Data("null".utf8)
    }

    /// A field of an object. Reads `.null` if this is not an object or the field is absent. Setting `.null` removes the field.
    subscript(key: String) -> JSONValue {
        get {
            if case .object(let fields) = self { fields[key] ?? .null } else { .null }
        }
        set {
            guard case .object(var fields) = self else { return }
            fields[key] = newValue.isNull ? nil : newValue
            self = .object(fields)
        }
    }

    var string: String? {
        if case .string(let value) = self { value } else { nil }
    }

    var int: Int? {
        if case .int(let value) = self { Int(value) } else { nil }
    }

    var bool: Bool? {
        if case .bool(let value) = self { value } else { nil }
    }

    var array: [JSONValue]? {
        if case .array(let value) = self { value } else { nil }
    }

    var object: [String: JSONValue]? {
        if case .object(let value) = self { value } else { nil }
    }

    var isNull: Bool { self == .null }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int64) { self = .int(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}
