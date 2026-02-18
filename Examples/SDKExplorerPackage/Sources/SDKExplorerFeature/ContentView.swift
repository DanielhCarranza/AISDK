import SwiftUI

public struct ContentView: View {
    @StateObject private var runtime = ExplorerRuntime()

    public init() {}

    public var body: some View {
        TabView {
            ChatView(runtime: runtime)
                .tabItem {
                    Label("Chat", systemImage: "message.fill")
                }

            SessionsView(runtime: runtime)
                .tabItem {
                    Label("Sessions", systemImage: "tray.full.fill")
                }

            DiagnosticsView(runtime: runtime)
                .tabItem {
                    Label("Diagnostics", systemImage: "stethoscope")
                }
        }
    }
}
