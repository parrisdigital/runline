import Foundation

struct CursorTeamMemberDTO: Decodable, Equatable {
    var id: String?
    var email: String?
    var name: String?
    var role: String?
    var active: Bool?
    var lastActiveAt: String?
}

struct CursorTeamSpendDTO: Decodable, Equatable {
    var amountCents: Int?
    var currency: String?
    var periodStart: String?
    var periodEnd: String?
    var raw: JSONValue?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        amountCents = try container.decodeIfPresent(Int.self, forKey: .amountCents)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
        periodStart = try container.decodeIfPresent(String.self, forKey: .periodStart)
        periodEnd = try container.decodeIfPresent(String.self, forKey: .periodEnd)
        raw = try? JSONValue(from: decoder)
    }

    private enum CodingKeys: String, CodingKey {
        case amountCents
        case currency
        case periodStart
        case periodEnd
    }
}

struct CursorDailyUsageDTO: Decodable, Equatable {
    var date: String?
    var userID: String?
    var email: String?
    var requests: Int?
    var costCents: Int?
    var raw: JSONValue?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        userID = try container.decodeIfPresent(String.self, forKey: .userID)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        requests = try container.decodeIfPresent(Int.self, forKey: .requests)
        costCents = try container.decodeIfPresent(Int.self, forKey: .costCents)
        raw = try? JSONValue(from: decoder)
    }

    private enum CodingKeys: String, CodingKey {
        case date
        case userID = "userId"
        case email
        case requests
        case costCents
    }
}

struct CursorUsageEventDTO: Decodable, Equatable {
    var id: String?
    var userID: String?
    var timestamp: String?
    var kind: String?
    var model: String?
    var raw: JSONValue?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        userID = try container.decodeIfPresent(String.self, forKey: .userID)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        raw = try? JSONValue(from: decoder)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case userID = "userId"
        case timestamp
        case kind
        case model
    }
}

struct CursorAuditLogDTO: Decodable, Equatable {
    var id: String?
    var actorEmail: String?
    var action: String?
    var resource: String?
    var createdAt: String?
}

struct CursorRepoBlocklistEntryDTO: Decodable, Equatable {
    var repository: String?
    var pattern: String?
    var createdAt: String?
}

struct CursorAnalyticsMetricDTO: Decodable, Equatable {
    var date: String?
    var userID: String?
    var email: String?
    var value: Double?
    var count: Int?
    var raw: JSONValue?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        userID = try container.decodeIfPresent(String.self, forKey: .userID)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        value = try container.decodeIfPresent(Double.self, forKey: .value)
        count = try container.decodeIfPresent(Int.self, forKey: .count)
        raw = try? JSONValue(from: decoder)
    }

    private enum CodingKeys: String, CodingKey {
        case date
        case userID = "userId"
        case email
        case value
        case count
    }
}

struct CursorAICodeTrackingDTO: Decodable, Equatable {
    var id: String?
    var commitSha: String?
    var repository: String?
    var userID: String?
    var linesAdded: Int?
    var linesDeleted: Int?
    var source: String?
    var createdAt: String?
}
