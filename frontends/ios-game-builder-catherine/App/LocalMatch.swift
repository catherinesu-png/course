import Foundation

/// A pass-and-play match kept on the phone: the platform's side of the shared game message
/// protocol (root README, "Game API"). Nothing is sent to the server.
struct LocalMatch {
    enum Kind: String { case human, computer }

    let kinds: [Kind]
    private var moves: [(state: JSONValue, next: [Int]?)] = []
    private(set) var viewerSeat: Int?
    /// Set while the phone must be handed to another human before their turn is shown.
    private(set) var handoffTo: Int?

    init(kinds: [Kind]) {
        self.kinds = kinds
        restart()
    }

    var moveCount: Int { moves.count }
    var state: JSONValue { moves.last?.state ?? .null }
    /// Seat 0 moves first; nil once the match is over.
    var turn: [Int]? { moves.isEmpty ? [0] : moves.last!.next }
    var isOver: Bool { turn == nil }
    var actingSeat: Int? { turn?.first }

    func name(of seat: Int) -> String {
        "\(kinds[seat] == .human ? "Player" : "Computer") \(seat + 1)"
    }

    /// Nil during a handoff, so the next player's private view isn't drawn behind the cover.
    var stateChanged: JSONValue? {
        guard handoffTo == nil else { return nil }
        let players = kinds.enumerated().map { seat, kind in
            JSONValue.object(["player_index": .seat(seat), "kind": .string(kind.rawValue), "name": .string(name(of: seat))])
        }
        return .object([
            "type": .string("state_changed"),
            "state": state,
            "players": .array(players),
            "turn_of_player_indices": .seats(turn),
            "turn_of_player_index": .seat(turn?.first),   // legacy field for older games
            "status": .string(isOver ? "over" : "ongoing"),
            "end_reason": isOver ? .string("finished") : .null,
            "move_count": .seat(moves.count),
            "my_player_index": .seat(viewerSeat),
            "acting_for_player_index": .seat(actingSeat),
        ])
    }

    /// Applies a `make_move`. Returns a message if the move is rejected.
    mutating func apply(newState: JSONValue, nextTurn: [Int]?) -> String? {
        guard !isOver else { return "The game sent a move, but the match is over." }
        if let next = nextTurn {
            guard !next.isEmpty, Set(next).count == next.count, next.allSatisfy({ kinds.indices.contains($0) }) else {
                return "next_turn_player_indices \(next) is not a set of seats."
            }
        }
        moves.append((newState, nextTurn))
        updateViewer()
        return nil
    }

    /// Takes back moves until a human is to move, so a computer doesn't just replay.
    mutating func undo() {
        guard !moves.isEmpty else { return }
        repeat { moves.removeLast() } while !moves.isEmpty && actingSeat.map { kinds[$0] == .computer } == true
        updateViewer()
    }

    mutating func restart() {
        moves = []
        viewerSeat = kinds.firstIndex(of: .human)
        handoffTo = nil
        updateViewer()
    }

    mutating func confirmHandoff() {
        guard let seat = handoffTo else { return }
        viewerSeat = seat
        handoffTo = nil
    }

    private mutating func updateViewer() {
        handoffTo = nil
        guard let seat = actingSeat, kinds[seat] == .human, seat != viewerSeat else { return }
        if viewerSeat == nil { viewerSeat = seat } else { handoffTo = seat }
    }
}

/// What the game's iframe posted to the platform.
enum GameMessage {
    case move(newState: JSONValue, nextTurn: [Int]?)
    case invalid(String)
    case other

    init(json: String) {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)),
              value["type"] == .string("make_move") else { self = .other; return }
        guard let newState = value["new_state"] else { self = .invalid("make_move has no new_state."); return }
        switch value["next_turn_player_indices"] {
        case .null?:
            self = .move(newState: newState, nextTurn: nil)
        case .array(let items)?:
            let seats = items.compactMap(\.int)
            self = seats.count == items.count
                ? .move(newState: newState, nextTurn: seats)
                : .invalid("next_turn_player_indices must be whole numbers.")
        default:
            // Older games send one seat as `next_turn_player_index`.
            switch value["next_turn_player_index"] {
            case .null?: self = .move(newState: newState, nextTurn: nil)
            case let legacy? where legacy.int != nil: self = .move(newState: newState, nextTurn: [legacy.int!])
            default: self = .invalid("make_move needs next_turn_player_indices (null ends the match).")
            }
        }
    }
}
