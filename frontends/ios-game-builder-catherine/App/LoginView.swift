import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var config: AuthConfig?
    @State private var guestName = ""
    @State private var contact = ""
    @State private var usePhone = false
    @State private var verification: VerificationStarted?
    @State private var code = ""
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Play as a guest") {
                    TextField("Display name", text: $guestName)
                        .textInputAutocapitalization(.words)
                    Button("Continue as guest") { run { try await API.createGuest(displayName: trimmed(guestName)) } }
                        .disabled(trimmed(guestName).isEmpty || busy)
                }

                if config?.emailLoginEnabled == true || config?.phoneLoginEnabled == true {
                    Section("Email or phone") {
                        if config?.emailLoginEnabled == true && config?.phoneLoginEnabled == true {
                            Picker("Method", selection: $usePhone) {
                                Text("Email").tag(false)
                                Text("Phone").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .disabled(verification != nil)
                        }
                        if verification == nil {
                            TextField(usePhone ? "Phone number, e.g. +15551234567" : "Email address", text: $contact)
                                .keyboardType(usePhone ? .phonePad : .emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button("Send code") { Task { await sendCode() } }
                                .disabled(trimmed(contact).isEmpty || busy)
                        } else {
                            TextField("6-digit code", text: $code)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                            Button("Log in") { run { try await verifyCode() } }
                                .disabled(trimmed(code).isEmpty || busy)
                            Button("Use a different \(usePhone ? "number" : "address")", role: .cancel) {
                                verification = nil
                                code = ""
                            }
                        }
                    }
                }

                Section("Google and Facebook") {
                    Text("Not available in this build yet. They need Google's and Facebook's iOS SDKs.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let message {
                    Section { Text(message).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("Game Builder")
            .overlay { if busy { ProgressView() } }
            .task { config = try? await API.authConfig() }
        }
    }

    private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func sendCode() async {
        busy = true
        defer { busy = false }
        do {
            verification = usePhone
                ? try await API.startPhoneLogin(phoneNumber: trimmed(contact))
                : try await API.startEmailLogin(email: trimmed(contact))
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    private func verifyCode() async throws -> Account {
        guard let verification else { throw URLError(.badURL) }
        return try await API.verify(phone: usePhone, verificationId: verification.verificationId, code: trimmed(code))
    }

    private func run(_ request: @escaping () async throws -> Account) {
        Task {
            busy = true
            defer { busy = false }
            do {
                try model.signedIn(try await request())
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
