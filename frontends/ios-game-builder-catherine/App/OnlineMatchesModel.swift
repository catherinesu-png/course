import Foundation
import Observation

/// Online matches are always server-backed; only the separate pass-and-play flow works offline.
@MainActor @Observable
final class OnlineMatchesModel {
    private let app: AppModel
    private(set) var myMatches: [Match] = []
    private(set) var openMatches: [Match] = []
    private(set) var versions: [String: Game] = [:]
    private(set) var playerNames: [String: String] = [:]
    private(set) var loading = false
    private(set) var sendingMoves: Set<String> = []
    var errorMessage: String?
    private var loadedUserId: String?

    init(app: AppModel) {
        self.app = app
        loadedUserId = app.account?.id
    }

    private var userId: String? { app.account?.id }

    func match(id: String) -> Match? {
        myMatches.first { $0.id == id } ?? openMatches.first { $0.id == id }
    }

    func game(for match: Match) -> Game? {
        versions["\(match.gameId)@\(match.gameVersion)"]
            ?? app.games.first { $0.id == match.gameId && $0.version == match.gameVersion }
    }

    func name(of seat: Match.Seat) -> String {
        guard let id = seat.userId else { return "Computer \(seat.playerIndex + 1)" }
        if id == userId { return app.account?.displayName ?? "You" }
        return playerNames[id] ?? "Player \(seat.playerIndex + 1)"
    }

    func mySeat(_ match: Match) -> Int? { match.seat(of: userId)?.playerIndex }

    /// Mine on my turn, or a computer seat on a computer turn (any human client can act for it).
    func actingSeat(_ match: Match) -> Int? {
        guard match.isOngoing, let turns = match.turnOfPlayerIndices else { return nil }
        if let mine = mySeat(match), turns.contains(mine) { return mine }
        return turns.first { seat in
            match.players.first(where: { $0.playerIndex == seat })?.kind == "computer"
        }
    }

    func isMyTurn(_ match: Match) -> Bool {
        guard let mine = mySeat(match) else { return false }
        return match.isOngoing && (match.turnOfPlayerIndices ?? []).contains(mine)
    }

    func stateChanged(_ match: Match) -> String {
        let players = match.players.map { seat in
            JSONValue.object([
                "player_index": .seat(seat.playerIndex),
                "kind": .string(seat.kind),
                "name": .string(name(of: seat)),
            ])
        }
        return JSONValue.object([
            "type": .string("state_changed"),
            "state": match.state,
            "players": .array(players),
            "turn_of_player_indices": .seats(match.turnOfPlayerIndices),
            "turn_of_player_index": .seat(match.turnOfPlayerIndices?.first),
            "status": .string(match.isOver ? "over" : "ongoing"),
            "end_reason": match.endReason.map(JSONValue.string) ?? .null,
            "move_count": .seat(match.moveCount),
            "my_player_index": .seat(mySeat(match)),
            "acting_for_player_index": .seat(actingSeat(match)),
        ]).jsonString
    }

    func refreshList() async {
        guard let account = app.account else {
            myMatches = []
            openMatches = []
            loadedUserId = nil
            return
        }
        if loadedUserId != account.id {
            myMatches = []
            openMatches = []
            loadedUserId = account.id
        }
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            async let mine = API.myMatches(as: account)
            async let open = API.openMatches()
            let (mineResult, openResult) = try await (mine, open)
            myMatches = mineResult
            let mineIds = Set(mineResult.map(\.id))
            openMatches = openResult.filter { !mineIds.contains($0.id) }
            errorMessage = nil
            await loadDetails(for: mineResult + openMatches)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh(matchId: String) async {
        do {
            let fresh = try await API.match(id: matchId)
            store(fresh)
            await loadDetails(for: [fresh])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func open(linkOrId: String) async throws -> Match {
        let text = linkOrId.trimmingCharacters(in: .whitespacesAndNewlines)
        let id: String
        if let marker = text.range(of: "match=") {
            id = String(text[marker.upperBound...]).split(separator: "&", maxSplits: 1).first.map(String.init) ?? ""
        } else {
            id = text
        }
        guard !id.isEmpty else { throw URLError(.badURL) }
        let result = try await API.match(id: id)
        store(result)
        await loadDetails(for: [result])
        return result
    }

    func create(game: Game, computers: Int) async throws -> Match {
        guard let account = app.account else { throw URLError(.userAuthenticationRequired) }
        let result = try await API.createMatch(gameId: game.id, computers: computers, as: account)
        store(result)
        await loadDetails(for: [result])
        return result
    }

    func join(matchId: String) async throws {
        guard let account = app.account else { throw URLError(.userAuthenticationRequired) }
        store(try await API.joinMatch(id: matchId, as: account))
    }

    func start(matchId: String) async throws {
        guard let account = app.account else { throw URLError(.userAuthenticationRequired) }
        store(try await API.startMatch(id: matchId, as: account))
    }

    func setComputers(matchId: String, count: Int) async throws {
        guard let account = app.account else { throw URLError(.userAuthenticationRequired) }
        store(try await API.setComputers(matchId: matchId, count: count, as: account))
    }

    func makeMove(matchId: String, newState: JSONValue, nextTurn: [Int]?) async {
        guard !sendingMoves.contains(matchId), let current = match(id: matchId),
              let account = app.account, actingSeat(current) != nil else { return }
        sendingMoves.insert(matchId)
        defer { sendingMoves.remove(matchId) }
        do {
            store(try await API.makeMove(matchId: matchId, newState: newState, nextTurn: nextTurn,
                                         expectedMoveCount: current.moveCount, as: account))
            errorMessage = nil
        } catch {
            errorMessage = "Move wasn't accepted: \(error.localizedDescription)"
            await refresh(matchId: matchId)
        }
    }

    private func store(_ match: Match) {
        if match.ownerUserId == userId || match.seat(of: userId) != nil {
            if let i = myMatches.firstIndex(where: { $0.id == match.id }) { myMatches[i] = match }
            else { myMatches.insert(match, at: 0) }
            openMatches.removeAll { $0.id == match.id }
        } else if let i = openMatches.firstIndex(where: { $0.id == match.id }) {
            openMatches[i] = match
        } else {
            openMatches.insert(match, at: 0)
        }
    }

    private func loadDetails(for matches: [Match]) async {
        for match in matches {
            let key = "\(match.gameId)@\(match.gameVersion)"
            if versions[key] == nil,
               let game = try? await API.gameVersion(id: match.gameId, version: match.gameVersion) {
                versions[key] = game
            }
        }
        for id in Set(matches.flatMap { $0.players.compactMap(\.userId) })
        where id != userId && playerNames[id] == nil {
            if let name = try? await API.displayName(userId: id) { playerNames[id] = name }
        }
    }
}
