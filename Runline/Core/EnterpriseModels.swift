import Foundation

enum CursorAPIEndpointArea: String, CaseIterable, Identifiable, Hashable {
    case cloudAgents = "Cloud Agents"
    case admin = "Admin"
    case analytics = "Analytics"
    case aiCode = "AI Code"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .cloudAgents:
            "bolt.horizontal"
        case .admin:
            "person.3"
        case .analytics:
            "chart.line.uptrend.xyaxis"
        case .aiCode:
            "curlybraces"
        }
    }
}

struct CursorAPIEndpoint: Identifiable, Hashable {
    enum Access: String, Hashable {
        case user = "User"
        case enterprise = "Enterprise"
        case admin = "Admin"
    }

    var id: String {
        "\(method.rawValue):\(path)?\(queryItems.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&"))"
    }

    var area: CursorAPIEndpointArea
    var title: String
    var subtitle: String
    var method: CursorAPIClient.Method
    var path: String
    var queryItems: [URLQueryItem] = []
    var access: Access

    var displayPath: String {
        guard !queryItems.isEmpty else { return path }
        let query = queryItems
            .map { item in
                guard let value = item.value else { return item.name }
                return "\(item.name)=\(value)"
            }
            .joined(separator: "&")
        return "\(path)?\(query)"
    }

    var page: Int? {
        queryItems.first(where: { $0.name == "page" })?.value.flatMap(Int.init)
    }

    var supportsPagination: Bool {
        page != nil || queryItems.contains(where: { $0.name == "pageSize" || $0.name == "cursor" })
    }

    func withPage(_ page: Int) -> CursorAPIEndpoint {
        var copy = self
        if let index = copy.queryItems.firstIndex(where: { $0.name == "page" }) {
            copy.queryItems[index] = URLQueryItem(name: "page", value: String(max(1, page)))
        } else {
            copy.queryItems.append(URLQueryItem(name: "page", value: String(max(1, page))))
        }
        return copy
    }
}

struct CursorAPIEndpointResult: Identifiable, Hashable {
    var id: String { endpoint.id }
    var endpoint: CursorAPIEndpoint
    var statusCode: Int
    var latencyMilliseconds: Int
    var capturedAt: Date
    var etag: String?
    var preview: String
    var recordCount: Int?
    var errorMessage: String?

    var isSuccessful: Bool {
        (200..<300).contains(statusCode)
    }
}

struct CursorAPIEndpointCacheEntry: Equatable, Hashable {
    var etag: String
    var json: JSONValue
    var result: CursorAPIEndpointResult
}

enum JSONValue: Codable, Equatable, Hashable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let object):
            try container.encode(object)
        case .array(let array):
            try container.encode(array)
        case .string(let string):
            try container.encode(string)
        case .number(let number):
            try container.encode(number)
        case .bool(let bool):
            try container.encode(bool)
        case .null:
            try container.encodeNil()
        }
    }

    var recordCount: Int? {
        switch self {
        case .array(let values):
            return values.count
        case .object(let object):
            if case .array(let items)? = object["items"] {
                return items.count
            }
            if case .array(let data)? = object["data"] {
                return data.count
            }
            if case .object(let data)? = object["data"] {
                return data.count
            }
            if case .array(let commits)? = object["commits"] {
                return commits.count
            }
            if case .array(let members)? = object["members"] {
                return members.count
            }
            return object.count
        case .string, .number, .bool, .null:
            return nil
        }
    }

    func preview(maxLines: Int = 12) -> String {
        let lines = prettyPrintedLines(depth: 0)
        if lines.count <= maxLines {
            return lines.joined(separator: "\n")
        }
        return lines.prefix(maxLines).joined(separator: "\n") + "\n..."
    }

    private func prettyPrintedLines(depth: Int) -> [String] {
        let indent = String(repeating: "  ", count: depth)
        switch self {
        case .object(let object):
            guard !object.isEmpty else { return ["{}"] }
            var lines = ["{"]
            for key in object.keys.sorted() {
                guard let value = object[key] else { continue }
                let child = value.prettyPrintedLines(depth: depth + 1)
                if child.count == 1 {
                    lines.append("\(indent)  \"\(key)\": \(child[0])")
                } else {
                    lines.append("\(indent)  \"\(key)\": \(child[0])")
                    lines.append(contentsOf: child.dropFirst())
                }
            }
            lines.append("\(indent)}")
            return lines
        case .array(let values):
            guard !values.isEmpty else { return ["[]"] }
            var lines = ["["]
            for value in values.prefix(6) {
                let child = value.prettyPrintedLines(depth: depth + 1)
                if child.count == 1 {
                    lines.append("\(indent)  \(child[0])")
                } else {
                    lines.append("\(indent)  \(child[0])")
                    lines.append(contentsOf: child.dropFirst())
                }
            }
            if values.count > 6 {
                lines.append("\(indent)  ...")
            }
            lines.append("\(indent)]")
            return lines
        case .string(let value):
            return ["\"\(value)\""]
        case .number(let value):
            return [value.formatted()]
        case .bool(let value):
            return [value ? "true" : "false"]
        case .null:
            return ["null"]
        }
    }
}
