import Foundation
import Observation

@MainActor @Observable
final class AppModel {
    var account: Account? = Keychain.load()
    var games: [Game] = []
    var gamesSavedAt: Date?
    /// True when the last request failed for lack of network, so the saved list is shown.
    var isOffline = false
    var isLoading = false
    var errorMessage: String?

    init() {
        if let cached = GameCache.load() {
            games = cached.games
            gamesSavedAt = cached.savedAt
        }
    }

    func signedIn(_ account: Account) throws {
        try Keychain.save(account)
        self.account = account
        errorMessage = nil
    }

    func logOut() {
        Keychain.delete()
        account = nil
    }

    func isMine(_ game: Game) -> Bool { game.ownerUserId == account?.id }

    func refreshGames() async {
        isLoading = true
        defer { isLoading = false }
        do {
            games = try await API.fetchGames()
            gamesSavedAt = .now
            isOffline = false
            errorMessage = nil
            GameCache.save(games)
        } catch {
            isOffline = API.isNetworkError(error)
            errorMessage = error.localizedDescription
        }
    }
}
