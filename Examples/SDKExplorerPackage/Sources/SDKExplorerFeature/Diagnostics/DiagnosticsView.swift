import SwiftUI

public struct DiagnosticsView: View {
    @ObservedObject var runtime: ExplorerRuntime

    public init(runtime: ExplorerRuntime) {
        self.runtime = runtime
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                controls
                results
                if let location = runtime.exportLocation {
                    Text("Exported: \(location)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 12)
            .navigationTitle("Diagnostics")
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button("Run All Tests") {
                Task { await runtime.runDiagnostics() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(runtime.isBusy)

            Button("Export Evidence") {
                Task { await runtime.exportEvidenceBundle() }
            }
            .buttonStyle(.bordered)
            .disabled(runtime.diagnostics.isEmpty && runtime.missionEvidence.isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var results: some View {
        List(runtime.diagnostics) { result in
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: result.pass ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.pass ? .green : .red)
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.name)
                        .font(.headline)
                    Text(result.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(result.durationMs) ms")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Rerun") {
                    Task {
                        await runtime.runDiagnostics()
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .listStyle(.plain)
    }
}
