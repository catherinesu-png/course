# Catherine's iOS Game Builder

A native SwiftUI iPhone app (iOS 17+, Xcode 16+, no third-party packages) for the shared course
backend. It only uses the existing REST API and the shared game message protocol; it changes nothing
else in the repo.

## Decisions made

| Topic | Decision |
|-------|----------|
| Scope | Everything the web builder does: browse, publish, edit, delete, versions, AI agent, test |
| Offline | Pass-and-play only. Creating or editing games needs a connection |
| Conflicts | The server is the truth (see below) |
| Login | Every method the backend supports |
| Editor | A phone version of the web editor: Edit, Test and AI tabs |
| Protocol | `state_changed` / `make_move`, run in a sandboxed `WKWebView` iframe |

## What works

- **Login:** guest, and email or phone codes (shown only when `GET /auth/config` enables them).
  Credentials are stored in the Keychain.
- **Browse:** all games, with "My games" separated from "Class games". The list is cached on the
  phone for offline play.
- **Editor:** name, description, player counts, mid-match leave/join, HTML code; Publish (create) and
  Save (new version).
- **Test / play:** pass-and-play with human and computer seats, undo, restart and a handoff screen.
  Works offline for any game already loaded. Moves stay on the phone.
- **Online matches:** create from a game's page or the Matches tab, invite friends with a share
  link, join open matches or a pasted link, start the match, and play through the same game
  protocol. The app refreshes match state while the match is open; online matches require a network.
- **Versions:** the history of a game (each version fetched from `GET /games/{id}/versions/{n}`),
  with play and "restore as a new version".
- **Delete** (with confirmation) and the **AI agent** chat (`POST /agent/chat`), with Apply/Discard
  of its proposals.

## Conflicts

Before saving an existing game, the app compares the server's current version with the one the
edit started from. If the server moved on, you choose: **use the server's version** (default), or
**overwrite**, which saves your edits as a newer version, so the other version stays in the history.
The API has no compare-and-set on `PATCH`, so a tiny race between the check and the save is
possible; fixing that needs a backend change.

## Not built yet

- Linking another login to an account and account merging.
- **Google and Facebook login** still need their iOS SDKs and client IDs. `API.logInWithFacebook`
  is ready; `GET /auth/config` currently returns no Facebook app id.
- Tests, and a build: this was written without Xcode and has not been compiled yet.

## Run

Open `CatherineGameBuilder.xcodeproj`, choose a simulator or your iPhone, and run. For a device,
set your team under Signing & Capabilities and change the bundle identifier if needed. In Debug,
`-server http://localhost:8000` points the app at a local backend.

## Files (`App/`)

`API.swift` REST client and models · `AppModel.swift` account and games list · `Keychain.swift` ·
`GameCache.swift` offline copy of the game list · `LoginView.swift` · `GamesView.swift` browse,
detail, versions · `OnlineMatchesModel.swift` online match state · `OnlineMatchesView.swift` create,
join, waiting room and live play · `EditorView.swift` editor tabs and AI chat · `PlayView.swift`
pass-and-play · `LocalMatch.swift` local protocol state · `GameWebView.swift` sandboxed bridge ·
`GameTemplate.swift` starter game · `JSONValue.swift` opaque state.
