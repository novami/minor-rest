import SwiftUI

@main
struct MinorRESTApp: App {
    var body: some Scene {
        Window("MinorREST", id: "main") {
            ContentView()
        }
        .defaultSize(width: 1280, height: 800)
    }
}

struct ContentView: View {
    var body: some View {
        Color.clear
            .frame(minWidth: 900, minHeight: 600)
    }
}
