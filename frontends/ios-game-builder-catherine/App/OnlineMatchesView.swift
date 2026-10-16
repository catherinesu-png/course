import SwiftUI

struct OnlineMatchesView: View {
    @Environment(AppModel.self) private var app
    @Environment(OnlineMatchesModel.self) private var model
    @State private var path: [String] = []
    @State private var pastedLink = ""
    @State private var showingNewMatch = false
    @State private var message: String?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let message { Text(message).font(.footnote).foregroundStyle(.red) }
                if model.loading && model.myMatches.isEmpty {
                    ProgressView()
                }
                Section("My matches") {
                    if model.myMatches.isEmpty {
                        Text("No matches yet. Start one from a game's page, or join an open match below.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.myMatches) { match in
                        NavigationLink(value: match.id) { MatchRow(match: match) }
                    }
                }
                Section("Open matches") {
                    if model.openMatches.isEmpty {
                        Text("No open matches right now.").foregroundStyle(.secondary)
                    }
                    ForEach(model.openMatches) { match in
                        NavigationLink(value: match.id) { MatchRow(match: match) }
                    }
                }
                Section("Join by link") {
                    TextField("Paste a match link or ID", text: $pastedLink)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Open match") {
                        Task {
                            do {
                                let match = try await model.open(linkOrId: pastedLink)
                                path.append(match.id)
                                pastedLink = ""
                                message = nil
                            } catch { message = error.localizedDescription }
                        }
                    }
                    .disabled(pastedLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let error = model.errorMessage {
                    Section { Text(error).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Online Matches")
            .refreshable { await model.refreshList() }
            .task { await model.refreshList() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New match", systemImage: "plus") { showingNewMatch = true }
                }
            }
            .navigationDestination(for: String.self) { id in
                OnlineMatchView(matchId: id)
            }
            .sheet(isPresented: $showingNewMatch) {
                NavigationStack {
                    NewOnlineMatchView()
                }
            }
        }
    }
}

private struct MatchRow: View {
    @Environment(AppModel.self) private var app
    @Environment(OnlineMatchesModel.self) private var model
    let match: Match

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(model.game(for: match)?.name ?? "Game")
                    .font(.headline)
                Spacer()
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }
            Text(match.players.map { model.name(of: $0) }.joined(separator: " · "))
                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            Text("v\(match.gameVersion) · move \(match.moveCount)")
                .font(.caption.monospaced()).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }

    private var status: String {
        if match.isWaiting { return "Waiting" }
        if match.isOver { return "Finished" }
        if model.isMyTurn(match) { return "Your turn" }
        return "In progress"
    }

    private var statusColor: Color {
        model.isMyTurn(match) ? .green : .secondary
    }
}

private struct NewOnlineMatchView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if app.games.isEmpty {
                ContentUnavailableView("No games available", systemImage: "gamecontroller",
                                      description: Text("Connect and refresh the Games tab first."))
            }
            ForEach(app.games) { game in
                NavigationLink {
                    CreateOnlineMatchView(game: game)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(game.name).font(.headline)
                        Text("\(game.allowedPlayerCounts.map(String.init).joined(separator: ", ")) players · v\(game.version)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(game.version < 1)
            }
        }
        .navigationTitle("Choose a game")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
        }
    }
}

struct CreateOnlineMatchView: View {
    @Environment(OnlineMatchesModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let game: Game
    @State private var computers = 0
    @State private var created: Match?
    @State private var busy = false
    @State private var error: String?

    private var maxComputers: Int { max(0, (game.allowedPlayerCounts.max() ?? 2) - 1) }

    var body: some View {
        Form {
            Section("Game") {
                LabeledContent("Name", value: game.name)
                LabeledContent("Version", value: "\(game.version)")
                LabeledContent("Allowed players", value: game.allowedPlayerCounts.map(String.init).joined(separator: ", "))
            }
            Section("Computer opponents") {
                Stepper("\(computers)", value: $computers, in: 0...maxComputers)
                Text(computers == 0
                     ? "Friends can join the open seats."
                     : "You and \(computers) computer opponent\(computers == 1 ? "" : "s"); friends may join too.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let error { Section { Text(error).font(.footnote).foregroundStyle(.red) } }
            if let created {
                Section {
                    NavigationLink("Open waiting room") { OnlineMatchView(matchId: created.id) }
                } footer: {
                    Text("Share the match link from its waiting room so friends can join.")
                }
            } else {
                Section {
                    Button("Create match") { Task { await create() } }
                        .disabled(busy)
                } footer: {
                    Text("Creating a match requires an internet connection.")
                }
            }
        }
        .navigationTitle("New online match")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if busy { ProgressView() } }
    }

    private func create() async {
        busy = true
        defer { busy = false }
        do { created = try await model.create(game: game, computers: computers) }
        catch { error = error.localizedDescription }
    }
}

struct OnlineMatchView: View {
    @Environment(AppModel.self) private var app
    @Environment(OnlineMatchesModel.self) private var model
    let matchId: String
    @State private var busy = false
    @State private var moveError: String?
    @State private var resendCount = 0

    var body: some View {
        Group {
            if let match = model.match(id: matchId) {
                if match.isWaiting { waitingRoom(match) }
                else { board(match) }
            } else {
                ProgressView("Loading match…")
            }
        }
        .navigationTitle(model.match(id: matchId).flatMap { model.game(for: $0)?.name } ?? "Match")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.refresh(matchId: matchId)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if !Task.isCancelled { await model.refresh(matchId: matchId) }
            }
        }
    }

    private func waitingRoom(_ match: Match) -> some View {
        let game = model.game(for: match)
        let isOwner = match.ownerUserId == app.account?.id
        let computers = match.players.filter { $0.kind == "computer" }.count
        let counts = game?.allowedPlayerCounts ?? []
        let canStart = counts.contains(match.players.count)

        return List {
            Section {
                Text("Waiting for players").font(.headline)
                LabeledContent("Game version", value: "\(game?.name ?? "Game") v\(match.gameVersion)")
                LabeledContent("Allowed players", value: counts.map(String.init).joined(separator: ", "))
            }
            Section("Seats") {
                ForEach(match.players) { seat in
                    HStack {
                        Text(model.name(of: seat))
                        if seat.userId == app.account?.id { Text("(you)").foregroundStyle(.secondary) }
                        Spacer()
                        Text(seat.kind.capitalized).foregroundStyle(.secondary)
                    }
                }
                if isOwner {
                    Stepper("Computer opponents: \(computers)", value: Binding(
                        get: { computers },
                        set: { value in Task { await updateComputers(value) } }
                    ), in: 0...max(0, (counts.max() ?? 2) - 1))
                    .disabled(busy)
                }
            }
            Section("Invite") {
                let url = API.shareURL(matchId: match.id)
                Text(url.absoluteString).font(.caption.monospaced()).textSelection(.enabled)
                ShareLink(item: url) { Label("Share match link", systemImage: "square.and.arrow.up") }
            }
            if isOwner {
                Section {
                    Button("Start match") { Task { await start() } }
                        .disabled(busy || !canStart)
                    if !canStart {
                        Text("Start when the seat count matches one of the allowed player counts.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } else if model.mySeat(match) == nil {
                Section { Button("Join match") { Task { await join() } }.disabled(busy) }
            } else {
                Section { Text("Waiting for the owner to start.").foregroundStyle(.secondary) }
            }
            if let moveError { Section { Text(moveError).font(.footnote).foregroundStyle(.red) } }
        }
    }

    private func board(_ match: Match) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(status(for: match)).font(.subheadline.weight(.semibold))
                Spacer()
                Text("Move \(match.moveCount)").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            .padding(12)

            if let game = model.game(for: match) {
                GameWebView(code: game.code, stateJSON: model.stateChanged(match), resendCount: resendCount) { json in
                    switch GameMessage(json: json) {
                    case .move(let newState, let nextTurn):
                        Task { await submit(newState: newState, nextTurn: nextTurn) }
                    case .invalid(let problem):
                        moveError = problem
                        resendCount += 1
                    case .other: break
                    }
                }
            } else {
                ContentUnavailableView("Game version unavailable", systemImage: "wifi.slash",
                                      description: Text("Reconnect to download this match's exact game version."))
            }
            if match.isOver, let reason = match.endReason {
                Text(reason == "player_left" ? "Match ended because a player left." : "Match finished.")
                    .font(.footnote).foregroundStyle(.secondary).padding(10)
            }
            if let moveError {
                Text(moveError).font(.footnote).foregroundStyle(.red).padding(8)
            }
        }
    }

    private func status(for match: Match) -> String {
        if match.isOver { return match.endReason == "player_left" ? "Over: a player left" : "Game over" }
        guard let mine = model.mySeat(match) else { return "Watching" }
        if (match.turnOfPlayerIndices ?? []).contains(mine) { return "Your turn" }
        let names = (match.turnOfPlayerIndices ?? []).compactMap { index in
            match.players.first { $0.playerIndex == index }.map(model.name(of:))
        }
        return names.isEmpty ? "Waiting" : "\(names.joined(separator: ", "))'s turn"
    }

    private func join() async {
        await perform { try await model.join(matchId: matchId) }
    }

    private func start() async {
        await perform { try await model.start(matchId: matchId) }
    }

    private func updateComputers(_ count: Int) async {
        await perform { try await model.setComputers(matchId: matchId, count: count) }
    }

    private func submit(newState: JSONValue, nextTurn: [Int]?) async {
        moveError = nil
        await model.makeMove(matchId: matchId, newState: newState, nextTurn: nextTurn)
        if let error = model.errorMessage {
            moveError = error
            resendCount += 1
        }
    }

    private func perform(_ action: () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await action()
            moveError = nil
        } catch { moveError = error.localizedDescription }
    }
}
