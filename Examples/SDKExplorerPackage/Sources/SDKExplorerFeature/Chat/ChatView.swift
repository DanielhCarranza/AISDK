import SwiftUI

public struct ChatView: View {
    @ObservedObject var runtime: ExplorerRuntime
    @State private var input = ""

    public init(runtime: ExplorerRuntime) {
        self.runtime = runtime
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                providerPicker
                missionStrip
                transcript
                toolActivity
                composer
            }
            .padding(.horizontal, 12)
            .navigationTitle("KillgraveAI")
        }
    }

    private var providerPicker: some View {
        Picker("Provider", selection: $runtime.selectedProvider) {
            ForEach(DemoProvider.allCases) { provider in
                Text(provider.title).tag(provider)
            }
        }
        .pickerStyle(.segmented)
    }

    private var missionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MissionCatalog.all) { mission in
                    Button(mission.title) {
                        Task { await runtime.runMission(mission) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(runtime.isBusy)
                }
            }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(runtime.messages) { message in
                        MessageRow(message: message)
                            .id(message.id)
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: runtime.messages.count) { _, _ in
                if let id = runtime.messages.last?.id {
                    withAnimation {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var toolActivity: some View {
        Group {
            if !runtime.activeToolEvents.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tool activity")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(runtime.activeToolEvents.indices, id: \.self) { idx in
                        Text(runtime.activeToolEvents[idx])
                            .font(.caption2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Ask KillgraveAI...", text: $input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                Button("Send") {
                    let text = input
                    input = ""
                    Task { await runtime.sendMessage(text) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(runtime.isBusy || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let error = runtime.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
