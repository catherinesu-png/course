import SwiftUI

/// Browse every game. Mine are separated so they can be edited.
struct GamesView: View {
    @Environment(AppModel.self) private var model
    @State private var showingNew = false

    var body: some View {
        NavigationStack {
            List {
                if model.isOffline {
                    Label("Offline. Showing games saved \(model.gamesSavedAt?.formatted(date: .abbreviated, time: .shortened) ?? "earlier"). Pass-and-play still works.",
                          systemImage: "wifi.slash")
                        .font(.footnote)
                } else if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
                }
                let mine = model.games.filter(model.isMine)
                let others = model.games.filter { !model.isMine($0) }
                Section("My games") {
                    if mine.isEmpty { Text("You haven't published a game yet.").foregroundStyle(.secondary) }
                    ForEach(mine) { row($0) }
                }
                Section("Class games") {
                    ForEach(others) { row($0) }
                }
            }
            .navigationTitle("Games")
            .refreshable { await model.refreshGames() }
            .task { await model.refreshGames() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Text(model.account?.displayName ?? "")
                        Button("Log out", role: .destructive) { model.logOut() }
                    } label: { Image(systemName: "person.crop.circle") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New game", systemImage: "plus") { showingNew = true }
                        .disabled(model.isOffline)
                }
            }
            .sheet(isPresented: $showingNew) {
                NavigationStack { EditorView(game: nil) }
            }
        }
    }

    private func row(_ game: Game) -> some View {
        NavigationLink {
            GameDetailView(gameId: game.id, initial: game)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(game.name).font(.headline)
                    Text("v\(game.version)").font(.caption).foregroundStyle(.secondary)
                }
                Text("\(game.allowedPlayerCounts.map(String.init).joined(separator: ", ")) players · updated \(formatServerDate(game.updatedAt))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct GameDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let gameId: String
    @State var initial: Game
    @State private var editing = false
    @State private var creatingMatch = false
    @State private var confirmingDelete = false
    @State private var errorMessage: String?

    private var game: Game { model.games.first { $0.id == gameId } ?? initial }

    var body: some View {
        List {
            Section {
                if !game.description.isEmpty { Text(game.description) }
                LabeledContent("Version", value: "\(game.version)")
                LabeledContent("Players", value: game.allowedPlayerCounts.map(String.init).joined(separator: ", "))
                LabeledContent("Updated", value: formatServerDate(game.updatedAt))
            }
            Section {
                NavigationLink("Play on this phone") {
                    PlayView(name: game.name, code: game.code, allowedPlayerCounts: game.allowedPlayerCounts)
                }
            } footer: {
                Text("Pass-and-play and computer opponents; works offline for games you have loaded.")
            }
            Section("Online") {
                Button("Create online match", systemImage: "person.2") { creatingMatch = true }
                    .disabled(model.isOffline)
            } footer: {
                Text("Create a server match and invite friends on other platforms.")
            }
            if model.isMine(game) {
                Section("Manage") {
                    Button("Edit game") { editing = true }.disabled(model.isOffline)
                    NavigationLink("Version history") { VersionsView(game: game) }.disabled(model.isOffline)
                    Button("Delete game", role: .destructive) { confirmingDelete = true }.disabled(model.isOffline)
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
        }
        .navigationTitle(game.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) { NavigationStack { EditorView(game: game) } }
        .sheet(isPresented: $creatingMatch) { NavigationStack { CreateOnlineMatchView(game: game) } }
        .confirmationDialog("Delete \(game.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await delete() } }
        } message: {
            Text("Existing matches keep working; new ones can't be created.")
        }
    }

    private func delete() async {
        guard let account = model.account else { return }
        do {
            try await API.deleteGame(id: game.id, as: account)
            await model.refreshGames()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The server keeps every version; this loads them one by one and can restore an old one
/// (restoring saves it as a new version, so no history is lost).
struct VersionsView: View {
    @Environment(AppModel.self) private var model
    let game: Game
    @State private var versions: [Game] = []
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if loading { ProgressView() }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            ForEach(versions, id: \.version) { version in
                NavigationLink {
                    VersionDetailView(version: version, latest: game.version)
                } label: {
                    VStack(alignment: .leading) {
                        Text("Version \(version.version)\(version.version == game.version ? " (current)" : "")").font(.headline)
                        Text("\(version.name) · \(formatServerDate(version.updatedAt))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Versions")
        .task {
            do {
                for number in stride(from: game.version, through: 1, by: -1) {
                    versions.append(try await API.gameVersion(id: game.id, version: number))
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            loading = false
        }
    }
}

struct VersionDetailView: View {
    @Environment(AppModel.self) private var model
    let version: Game
    let latest: Int
    @State private var message: String?

    var body: some View {
        List {
            Section("Details") {
                LabeledContent("Name", value: version.name)
                if !version.description.isEmpty { Text(version.description) }
                LabeledContent("Players", value: version.allowedPlayerCounts.map(String.init).joined(separator: ", "))
            }
            Section("Code") {
                Text(version.code)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(40)
            }
            Section {
                NavigationLink("Play this version") {
                    PlayView(name: "\(version.name) v\(version.version)", code: version.code,
                             allowedPlayerCounts: version.allowedPlayerCounts)
                }
                if version.version != latest {
                    Button("Restore as a new version") { Task { await restore() } }
                }
            }
            if let message { Section { Text(message).font(.footnote) } }
        }
        .navigationTitle("Version \(version.version)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func restore() async {
        guard let account = model.account else { return }
        do {
            let saved = try await API.updateGame(id: version.id, version.fields, as: account)
            await model.refreshGames()
            message = "Restored as version \(saved.version)."
        } catch {
            message = error.localizedDescription
        }
    }
}
