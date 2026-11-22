import SwiftUI

@main
struct MinorRESTApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("MinorREST", id: "main") {
            MainView()
                .environment(model)
        }
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView()
        }
    }
}
