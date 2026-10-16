import SwiftUI

/// Phone version of the web builder: Edit, Test and AI tabs for one game.
struct EditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private enum Tab: String, CaseIterable { case edit = "Edit", test = "Test", ai = "AI" }

    /// The game being edited, nil for a new one. Updated after each save.
    @State private var game: Game?
    @State private var fields: GameFields
    @State private var baseline: GameFields
    @State private var tab = Tab.edit
    @State private var message: String?
    @State private var saving = false
    @State private var conflict: Game?
    @State private var confirmingDiscard = false

    init(game: Game?) {
        _game = State(initialValue: game)
        let start = game?.fields ?? GameFields(
            name: "", description: "", allowedPlayerCounts: [2],
            allowsLeaveMidMatch: false, allowsJoinMidMatch: false, code: GameTemplate.code)
        _fields = State(initialValue: start)
        _baseline = State(initialValue: start)
    }

    private var isDirty: Bool { fields != baseline }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()

            switch tab {
            case .edit: editForm
            case .test: PlayView(name: fields.name.isEmpty ? "Test" : fields.name, code: fields.code,
                                 allowedPlayerCounts: fields.allowedPlayerCounts)
            case .ai: AgentView(fields: $fields)
            }
        }
        .navigationTitle(game == nil ? "New game" : "Edit game")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { isDirty ? (confirmingDiscard = true) : dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(game == nil ? "Publish" : "Save") { Task { await save(overwrite: false) } }
                    .disabled(!canSave || saving)
            }
        }
        .confirmationDialog("Discard your unsaved changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { dismiss() }
        }
        .confirmationDialog("This game changed on the server", isPresented: .constant(conflict != nil), titleVisibility: .visible) {
            Button("Use the server's version (recommended)") {
                if let conflict { load(conflict) }
                conflict = nil
            }
            Button("Overwrite with my changes", role: .destructive) {
                conflict = nil
                Task { await save(overwrite: true) }
            }
            Button("Cancel", role: .cancel) { conflict = nil }
        } message: {
            Text("Version \(conflict?.version ?? 0) was saved after you started editing. Overwriting saves your edits as a newer version; the server's version stays in the history.")
        }
        .interactiveDismissDisabled(isDirty)
    }

    private var canSave: Bool {
        !fields.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !fields.allowedPlayerCounts.isEmpty && isDirty
    }

    private var editForm: some View {
        Form {
            Section("Game") {
                TextField("Name", text: $fields.name).textInputAutocapitalization(.words)
                TextField("Description", text: $fields.description, axis: .vertical).lineLimit(2...4)
            }
            Section("Allowed player counts") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                    ForEach(2...10, id: \.self) { count in
                        let on = fields.allowedPlayerCounts.contains(count)
                        Button("\(count)") {
                            if on { fields.allowedPlayerCounts.removeAll { $0 == count } }
                            else { fields.allowedPlayerCounts = (fields.allowedPlayerCounts + [count]).sorted() }
                        }
                        .buttonStyle(.bordered)
                        .tint(on ? .accentColor : .gray)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                Toggle("Players may leave mid-match", isOn: $fields.allowsLeaveMidMatch)
                Toggle("Players may join mid-match", isOn: $fields.allowsJoinMidMatch)
            }
            Section("Code (one HTML document)") {
                TextEditor(text: $fields.code)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(minHeight: 300)
            }
            Section {
                if let game { Text("Version \(game.version) · updated \(formatServerDate(game.updatedAt))").font(.footnote) }
                Button("Revert changes") { fields = baseline; message = nil }.disabled(!isDirty)
                if let message { Text(message).font(.footnote) }
            }
        }
    }

    private func load(_ server: Game) {
        game = server
        fields = server.fields
        baseline = server.fields
    }

    /// The server is the source of truth: if the game moved on, ask before replacing it.
    private func save(overwrite: Bool) async {
        guard let account = model.account else { return }
        saving = true
        defer { saving = false }
        do {
            let saved: Game
            if let game {
                if !overwrite {
                    let latest = try await API.game(id: game.id)
                    if latest.version != game.version { conflict = latest; return }
                }
                saved = try await API.updateGame(id: game.id, fields, as: account)
            } else {
                saved = try await API.createGame(fields, as: account)
            }
            load(saved)
            message = "Saved version \(saved.version)."
            await model.refreshGames()
        } catch {
            message = "Couldn't save: \(error.localizedDescription)"
        }
    }
}

/// The game-building agent: chat that proposes code, which you apply or discard.
struct AgentView: View {
    @Environment(AppModel.self) private var model
    @Binding var fields: GameFields
    @State private var messages: [AgentMessage] = []
    @State private var notes: [String] = []
    @State private var pending: AgentReply?
    @State private var input = ""
    @State private var thinking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if messages.isEmpty {
                        Text("Describe the game you want, or how to change it. The agent proposes new code that you can test before applying.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                        Text(message.content)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: message.role == "user" ? .trailing : .leading)
                            .background(message.role == "user" ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 10))
                    }
                    ForEach(notes, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
                    if thinking { ProgressView("The agent is thinking…") }
                    if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                }
                .padding()
            }
            if let pending {
                HStack {
                    Text("Proposal ready").font(.footnote)
                    Spacer()
                    Button("Discard") { self.pending = nil; notes.append("Discarded the proposal.") }
                    Button("Apply") { apply(pending) }.buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
            }
            HStack(alignment: .bottom) {
                TextField("Ask the agent…", text: $input, axis: .vertical).lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                Button("Send") { Task { await send() } }
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || thinking || pending != nil)
            }
            .padding()
        }
    }

    private func send() async {
        guard let account = model.account else { return }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let history = messages + [AgentMessage(role: "user", content: text)]
        input = ""
        thinking = true
        errorMessage = nil
        defer { thinking = false }
        do {
            let reply = try await API.agentChat(fields: fields, messages: history, as: account)
            messages = history + [AgentMessage(role: "assistant", content: reply.message)]
            if reply.code != nil {
                pending = reply
                notes.append("The agent proposed new code. Apply it, or discard it.")
            }
        } catch {
            errorMessage = "The agent couldn't reply: \(error.localizedDescription)"
            input = text
        }
    }

    private func apply(_ reply: AgentReply) {
        if let name = reply.name, fields.name.trimmingCharacters(in: .whitespaces).isEmpty { fields.name = name }
        if let text = reply.description, fields.description.trimmingCharacters(in: .whitespaces).isEmpty { fields.description = text }
        if let code = reply.code { fields.code = code }
        pending = nil
        notes.append("Applied. Test it in the Test tab, then publish from the top right.")
    }
}
