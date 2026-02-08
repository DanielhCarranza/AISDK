import SwiftUI
import AISDK

public struct ContentView: View {
    @State private var tree: UITree?
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if let tree {
                    ScrollView {
                        GenerativeUIView(
                            tree: tree,
                            registry: .extended,
                            onAction: { _ in }
                        )
                        .padding()
                    }
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Text("Failed to load UI")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    ProgressView("Loading UI…")
                        .padding()
                }
            }
            .navigationTitle("Generative UI")
        }
        .task {
            loadSample()
        }
    }

    private func loadSample() {
        guard let url = Bundle.module.url(forResource: "sample-ui", withExtension: "json") else {
            errorMessage = "Sample JSON not found in bundle."
            return
        }

        do {
            let data = try Data(contentsOf: url)
            tree = try UITree.parse(from: data, validatingWith: UICatalog.extended)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
