import SwiftUI

/// Test or pass-and-play a game on this phone. Works offline once the game is downloaded.
struct PlayView: View {
    let name: String
    let code: String
    let allowedPlayerCounts: [Int]

    @State private var count: Int
    @State private var kinds: [LocalMatch.Kind]
    @State private var match: LocalMatch?
    @State private var resend = 0
    @State private var problem: String?

    init(name: String, code: String, allowedPlayerCounts: [Int]) {
        self.name = name
        self.code = code
        self.allowedPlayerCounts = allowedPlayerCounts
        let first = allowedPlayerCounts.min() ?? 2
        _count = State(initialValue: first)
        _kinds = State(initialValue: [.human] + Array(repeating: .computer, count: first - 1))
    }

    var body: some View {
        Group {
            if match == nil { setup } else { playing }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var setup: some View {
        Form {
            Section("Players") {
                Picker("Number of players", selection: $count) {
                    ForEach(allowedPlayerCounts.sorted(), id: \.self) { Text("\($0)").tag($0) }
                }
                .onChange(of: count) { _, new in
                    kinds = (0..<new).map { $0 < kinds.count ? kinds[$0] : .computer }
                }
                ForEach(0..<count, id: \.self) { seat in
                    Picker("Seat \(seat + 1)", selection: $kinds[seat]) {
                        Text("Human").tag(LocalMatch.Kind.human)
                        Text("Computer").tag(LocalMatch.Kind.computer)
                    }
                }
            }
            Section {
                Button("Start") { match = LocalMatch(kinds: kinds) }
                    .disabled(!kinds.contains(.human))
            } footer: {
                Text("Humans share this phone. Moves stay on the phone and nothing is sent to the server.")
            }
        }
    }

    private var playing: some View {
        VStack(spacing: 0) {
            if let match {
                ZStack {
                    GameWebView(code: code, stateJSON: match.stateChanged?.jsonString, resendCount: resend) { json in
                        handle(json)
                    }
                    if let seat = match.handoffTo {
                        VStack(spacing: 16) {
                            Text("Pass the phone to \(match.name(of: seat))").font(.title2).multilineTextAlignment(.center)
                            Button("I'm ready") { self.match?.confirmHandoff() }
                                .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.background)
                    }
                }
                if let problem {
                    Text(problem).font(.footnote).foregroundStyle(.red).padding(8)
                }
                HStack {
                    Text(match.isOver ? "Game over after \(match.moveCount) moves"
                         : "Move \(match.moveCount + 1): \(match.actingSeat.map(match.name(of:)) ?? "")")
                        .font(.footnote)
                    Spacer()
                    Button("Undo") { self.match?.undo(); problem = nil }.disabled(match.moveCount == 0)
                    Button("Restart") { self.match?.restart(); problem = nil }
                    Button("Setup") { self.match = nil }
                }
                .padding(10)
                .background(.bar)
            }
        }
    }

    private func handle(_ json: String) {
        switch GameMessage(json: json) {
        case .move(let state, let next):
            problem = self.match?.apply(newState: state, nextTurn: next)
            if problem != nil { resend += 1 }
        case .invalid(let text):
            problem = text
            resend += 1
        case .other:
            break
        }
    }
}
