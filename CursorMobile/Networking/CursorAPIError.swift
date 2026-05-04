import Foundation

enum CursorAPIError: LocalizedError, Equatable {
    case invalidURL
    case emptyAPIKey
    case requestFailed(statusCode: Int, message: String)
    case decodingFailed(String)
    case missingProvider
    case unsupportedResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The Cursor API URL could not be created."
        case .emptyAPIKey:
            "Enter a Cursor API key."
        case .requestFailed(let statusCode, let message):
            "Cursor API returned \(statusCode): \(message)"
        case .decodingFailed(let message):
            "Cursor API response could not be decoded: \(message)"
        case .missingProvider:
            "Connect a Cursor API key first."
        case .unsupportedResponse(let message):
            message
        }
    }

    var userMessage: String {
        switch self {
        case .emptyAPIKey:
            "Enter a Cursor API key."
        case .requestFailed(401, _):
            "Cursor rejected this API key."
        case .requestFailed(403, _):
            "This API key does not have access to the requested Cursor resource."
        case .requestFailed(404, let message):
            message.isEmpty ? "Cursor could not find this resource." : Self.readableMessage(from: message)
        case .requestFailed(409, let message):
            message
        case .requestFailed(429, _):
            "Cursor rate-limited this request. Try again shortly."
        case .requestFailed(_, let message):
            Self.readableMessage(from: message)
        case .missingProvider:
            "Connect a Cursor API key first."
        case .invalidURL, .decodingFailed, .unsupportedResponse:
            "Runline could not read the Cursor API response."
        }
    }

    private static func readableMessage(from message: String) -> String {
        guard !message.isEmpty else { return "Cursor API request failed." }

        if message.localizedCaseInsensitiveContains("Git Repository is empty")
            || message.localizedCaseInsensitiveContains("Failed to fetch branch/tag ref") {
            return "This repository is empty or the selected branch does not exist. Add an initial commit on GitHub, then refresh repositories and launch again."
        }

        return message
    }
}

extension CursorAPIError {
    var isNotFound: Bool {
        if case .requestFailed(404, _) = self {
            return true
        }
        return false
    }

    var isStreamExpired: Bool {
        if case .requestFailed(410, let message) = self {
            return message.localizedCaseInsensitiveContains("stream_expired")
                || message.localizedCaseInsensitiveContains("stream expired")
        }
        return false
    }
}

struct CursorAPIErrorResponse: Decodable {
    let error: String?
    let message: String?
    let code: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let nested = try? container.decode(NestedError.self, forKey: .error) {
            error = nested.message ?? nested.code
            message = nested.message
            code = nested.code
            return
        }
        error = try container.decodeIfPresent(String.self, forKey: .error)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        code = try container.decodeIfPresent(String.self, forKey: .code)
    }

    private enum CodingKeys: String, CodingKey {
        case error
        case message
        case code
    }

    private struct NestedError: Decodable {
        let message: String?
        let code: String?
    }
}
