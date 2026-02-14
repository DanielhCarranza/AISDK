import SwiftUI
import AISDK

public struct SessionsView: View {
    @ObservedObject var runtime: ExplorerRuntime
    @State private var estimatedTokens = 0

    public init(runtime: ExplorerRuntime) {
        self.runtime = runtime
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                storeSelector
                compactionPanel
                sessionsList
            }
            .padding(.horizontal, 12)
            .navigationTitle("Sessions")
            .task {
                estimatedTokens = await runtime.estimateTokenCount()
            }
        }
    }

    private var storeSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Store")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Store", selection: $runtime.selectedStore) {
                ForEach(DemoStoreKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: runtime.selectedStore) { _, newValue in
                Task { await runtime.switchStore(to: newValue) }
            }
            if !runtime.canSwitchStore {
                Text("Finish or clear current transcript before switching stores.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var compactionPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Estimated tokens: \(estimatedTokens)")
                Spacer()
                Button("Refresh") {
                    Task { estimatedTokens = await runtime.estimateTokenCount() }
                }
                .buttonStyle(.bordered)
            }
            Button("Compact active transcript") {
                Task {
                    await runtime.compactActiveSession()
                    estimatedTokens = await runtime.estimateTokenCount()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var sessionsList: some View {
        List(runtime.sessions) { session in
            NavigationLink {
                SessionDetail(
                    summary: session,
                    onRestore: {
                        Task { await runtime.restore(session: session) }
                    },
                    onDelete: {
                        Task { await runtime.delete(session: session) }
                    }
                )
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title ?? "Untitled")
                        .font(.headline)
                    Text("\(session.messageCount) messages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
    }
}
