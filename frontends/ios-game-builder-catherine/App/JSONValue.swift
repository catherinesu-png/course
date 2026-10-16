import Foundation

/// Any JSON value. A match's state is opaque JSON chosen by the game.
enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    var int: Int? {
        if case .number(let d) = self, d == d.rounded() { return Int(d) }
        return nil
    }

    static func seat(_ i: Int?) -> JSONValue { i.map { .number(Double($0)) } ?? .null }
    static func seats(_ s: [Int]?) -> JSONValue { s.map { .array($0.map { .number(Double($0)) }) } ?? .null }

    var jsonString: String {
        String(decoding: (try? JSONEncoder().encode(self)) ?? Data("null".utf8), as: UTF8.self)
    }
}
