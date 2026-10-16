import Foundation

struct Account: Codable, Equatable {
    let id: String
    let password: String
    let displayName: String
}

/// One version of a game, as returned by `GET /games` and `GET /games/{id}/versions/{n}`.
struct Game: Codable, Identifiable, Hashable {
    let id: String
    let version: Int
    let ownerUserId: String
    let name: String
    let description: String
    let allowedPlayerCounts: [Int]
    let allowsLeaveMidMatch: Bool
    let allowsJoinMidMatch: Bool
    let code: String
    let createdAt: String
    let updatedAt: String

    var fields: GameFields {
        GameFields(name: name, description: description, allowedPlayerCounts: allowedPlayerCounts,
                   allowsLeaveMidMatch: allowsLeaveMidMatch, allowsJoinMidMatch: allowsJoinMidMatch, code: code)
    }
}

/// The editable fields (body of `POST /games` and `PATCH /games/{id}`).
struct GameFields: Codable, Equatable {
    var name: String
    var description: String
    var allowedPlayerCounts: [Int]
    var allowsLeaveMidMatch: Bool
    var allowsJoinMidMatch: Bool
    var code: String
}

struct AuthConfig: Decodable {
    let googleClientId: String
    let phoneLoginEnabled: Bool
    let emailLoginEnabled: Bool
}

struct VerificationStarted: Decodable {
    let verificationId: String
    let expiresInSeconds: Int
}

struct AgentMessage: Codable, Equatable {
    let role: String   // "user" or "assistant"
    let content: String
}

struct AgentReply: Decodable {
    let message: String
    let code: String?
    let name: String?
    let description: String?
    let thinking: String?
    let raw: String?
    let attempts: Int?
    let parseNote: String?
}

struct Match: Codable, Identifiable, Equatable {
    struct Seat: Codable, Equatable, Identifiable {
        var id: Int { playerIndex }
        let playerIndex: Int
        let kind: String
        let userId: String?
    }

    let id: String
    let gameId: String
    let gameVersion: Int
    let ownerUserId: String
    var status: String
    var endReason: String?
    var players: [Seat]
    var turnOfPlayerIndices: [Int]?
    var state: JSONValue
    var moveCount: Int

    var isWaiting: Bool { status == "waiting_for_players" }
    var isOngoing: Bool { status == "ongoing" }
    var isOver: Bool { status == "over" }
    func seat(of userId: String?) -> Seat? { players.first { $0.userId != nil && $0.userId == userId } }
}

enum APIError: LocalizedError {
    case server(status: Int, detail: String)

    var errorDescription: String? {
        switch self {
        case .server(let status, let detail): "Server error \(status): \(detail)"
        }
    }
}

/// The buildplay.fun REST API (see "API" in the root README).
enum API {
    static let baseURL: URL = {
        #if DEBUG
        // Launch argument `-server http://localhost:8000` points the app at a local backend.
        if let s = UserDefaults.standard.string(forKey: "server"), let url = URL(string: s) { return url }
        #endif
        return URL(string: "https://buildplay.fun")!
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    static func isNetworkError(_ error: Error) -> Bool { error is URLError }

    // MARK: Login (every method returns the same id + password pair)

    private struct AuthResponse: Decodable {
        let userId: String
        let password: String
        let displayName: String
        var account: Account { Account(id: userId, password: password, displayName: displayName) }
    }

    static func authConfig() async throws -> AuthConfig {
        try decoder.decode(AuthConfig.self, from: try await send("GET", "auth/config"))
    }

    static func createGuest(displayName: String) async throws -> Account {
        let user: AuthResponseLike = try await post("users", ["display_name": displayName])
        return Account(id: user.id, password: user.password, displayName: user.displayName)
    }

    private struct AuthResponseLike: Decodable { let id: String; let password: String; let displayName: String }

    static func logInWithGoogle(idToken: String) async throws -> Account {
        (try await post("auth/google", ["id_token": idToken]) as AuthResponse).account
    }

    static func logInWithFacebook(accessToken: String) async throws -> Account {
        (try await post("auth/facebook", ["access_token": accessToken]) as AuthResponse).account
    }

    static func startPhoneLogin(phoneNumber: String) async throws -> VerificationStarted {
        try await post("auth/phone/start", ["phone_number": phoneNumber])
    }

    static func startEmailLogin(email: String) async throws -> VerificationStarted {
        try await post("auth/email/start", ["email": email])
    }

    static func verify(phone: Bool, verificationId: String, code: String) async throws -> Account {
        let path = phone ? "auth/phone/verify" : "auth/email/verify"
        return (try await post(path, ["verification_id": verificationId, "code": code]) as AuthResponse).account
    }

    // MARK: Games

    static func fetchGames() async throws -> [Game] {
        try decoder.decode([Game].self, from: try await send("GET", "games"))
    }

    static func game(id: String) async throws -> Game {
        try decoder.decode(Game.self, from: try await send("GET", "games/\(id)"))
    }

    static func gameVersion(id: String, version: Int) async throws -> Game {
        try decoder.decode(Game.self, from: try await send("GET", "games/\(id)/versions/\(version)"))
    }

    static func createGame(_ fields: GameFields, as account: Account) async throws -> Game {
        try await post("games", fields, as: account)
    }

    static func updateGame(id: String, _ fields: GameFields, as account: Account) async throws -> Game {
        let body = try encoder.encode(fields)
        return try decoder.decode(Game.self, from: try await send("PATCH", "games/\(id)", body: body, as: account))
    }

    static func deleteGame(id: String, as account: Account) async throws {
        _ = try await send("DELETE", "games/\(id)", as: account)
    }

    // MARK: AI

    static func agentChat(fields: GameFields, messages: [AgentMessage], as account: Account) async throws -> AgentReply {
        struct Request: Encodable {
            let gameName: String
            let gameDescription: String
            let allowedPlayerCounts: [Int]
            let code: String
            let messages: [AgentMessage]
        }
        let request = Request(gameName: fields.name, gameDescription: fields.description,
                              allowedPlayerCounts: fields.allowedPlayerCounts, code: fields.code, messages: messages)
        return try await post("agent/chat", request, as: account)
    }

    // MARK: Online matches

    static func myMatches(as account: Account) async throws -> [Match] {
        try decoder.decode([Match].self, from: try await send("GET", "matches", as: account))
    }

    static func openMatches() async throws -> [Match] {
        try decoder.decode([Match].self, from: try await send("GET", "matches/open"))
    }

    static func match(id: String) async throws -> Match {
        try decoder.decode(Match.self, from: try await send("GET", "matches/\(id)"))
    }

    static func createMatch(gameId: String, computers: Int, as account: Account) async throws -> Match {
        struct Request: Encodable { let gameId: String; let numComputerOpponents: Int }
        return try await post("matches", Request(gameId: gameId, numComputerOpponents: computers), as: account)
    }

    static func joinMatch(id: String, as account: Account) async throws -> Match {
        struct Empty: Encodable {}
        return try await post("matches/\(id)/join", Empty(), as: account)
    }

    static func startMatch(id: String, as account: Account) async throws -> Match {
        struct Empty: Encodable {}
        return try await post("matches/\(id)/start", Empty(), as: account)
    }

    static func setComputers(matchId: String, count: Int, as account: Account) async throws -> Match {
        struct Request: Encodable { let numComputerOpponents: Int }
        let data = try encoder.encode(Request(numComputerOpponents: count))
        return try decoder.decode(Match.self, from: try await send("PATCH", "matches/\(matchId)", body: data, as: account))
    }

    static func makeMove(matchId: String, newState: JSONValue, nextTurn: [Int]?, expectedMoveCount: Int,
                         as account: Account) async throws -> Match {
        let body: JSONValue = .object([
            "new_state": newState,
            "next_turn_player_indices": .seats(nextTurn),
            "expected_move_count": .number(Double(expectedMoveCount)),
        ])
        return try decoder.decode(Match.self, from: try await send("POST", "matches/\(matchId)/moves",
                                                                   body: JSONEncoder().encode(body), as: account))
    }

    static func displayName(userId: String) async throws -> String {
        struct User: Decodable { let displayName: String }
        return try decoder.decode(User.self, from: try await send("GET", "users/\(userId)")).displayName
    }

    static func shareURL(matchId: String) -> URL {
        URL(string: "\(baseURL.absoluteString)/portal#match=\(matchId)")!
    }

    // MARK: Plumbing

    private static func post<T: Decodable>(_ path: String, _ body: some Encodable, as account: Account? = nil) async throws -> T {
        let data = try await send("POST", path, body: try encoder.encode(body), as: account)
        return try decoder.decode(T.self, from: data)
    }

    private static func send(_ method: String, _ path: String, body: Data? = nil, as account: Account? = nil) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 60   // the AI agent can take a while
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let account {
            request.setValue(account.id, forHTTPHeaderField: "X-User-Id")
            request.setValue(account.password, forHTTPHeaderField: "X-User-Password")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            struct ErrorBody: Decodable { let detail: JSONValue }
            let detail = (try? JSONDecoder().decode(ErrorBody.self, from: data)).map { body in
                if case .string(let s) = body.detail { return s }
                return body.detail.jsonString   // 422 details are a list
            } ?? String(decoding: data, as: UTF8.self)
            throw APIError.server(status: status, detail: detail)
        }
        return data
    }
}

/// "2026-10-16T12:30:00.123456Z" as a short local date, or the raw text if it doesn't parse.
func formatServerDate(_ text: String) -> String {
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()
    guard let date = withFraction.date(from: text) ?? plain.date(from: text) else { return text }
    return date.formatted(date: .abbreviated, time: .shortened)
}
