import SwiftUI

@main
struct CatherineGameBuilderApp: App {
    @State private var model: AppModel
    @State private var matches: OnlineMatchesModel

    init() {
        let appModel = AppModel()
        _model = State(initialValue: appModel)
        _matches = State(initialValue: OnlineMatchesModel(app: appModel))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if model.account == nil {
                    LoginView()
                } else {
                    TabView {
                        GamesView()
                            .tabItem { Label("Games", systemImage: "gamecontroller") }
                        OnlineMatchesView()
                            .tabItem { Label("Matches", systemImage: "person.2") }
                    }
                }
            }
            .environment(model)
            .environment(matches)
        }
    }
}