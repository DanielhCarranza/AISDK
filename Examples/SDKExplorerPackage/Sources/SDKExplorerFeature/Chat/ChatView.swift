import SwiftUI
import AISDK

public struct ChatView: View {
    @ObservedObject var runtime: ExplorerRuntime
    @State private var input = ""
    @State private var showHistory = false

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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await runtime.startNewChat() }
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showHistory) {
                ChatHistorySheet(runtime: runtime, isPresented: $showHistory)
            }
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

// MARK: - Chat History Sheet

struct ChatHistorySheet: View {
    @ObservedObject var runtime: ExplorerRuntime
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                if runtime.sessions.isEmpty {
                    ContentUnavailableView(
                        "No Sessions",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Start chatting to create a session.")
                    )
                } else {
                    ForEach(runtime.sessions) { session in
                        Button {
                            Task {
                                await runtime.restore(session: session)
                                isPresented = false
                            }
                        } label: {
                            HStack(spacing: 10) {
                                providerIcon(for: session)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title ?? "Untitled")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                    HStack(spacing: 6) {
                                        Text("\(session.messageCount) msgs")
                                        Text("·")
                                        Text(session.lastActivityAt, style: .relative)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        Task {
                            for index in offsets {
                                let session = runtime.sessions[index]
                                await runtime.delete(session: session)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Chat History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await runtime.startNewChat() }
                        isPresented = false
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
        }
    }

    private func providerIcon(for session: SessionSummary) -> some View {
        let title = session.title ?? ""
        let (icon, color) = providerStyle(from: title)
        return Image(systemName: icon)
            .font(.title3)
            .foregroundStyle(color)
            .frame(width: 32, height: 32)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func providerStyle(from title: String) -> (String, Color) {
        let lower = title.lowercased()
        if lower.contains("openai") {
            return ("brain", .green)
        } else if lower.contains("anthropic") {
            return ("sparkle", .orange)
        } else if lower.contains("gemini") {
            return ("wand.and.stars", .blue)
        } else {
            return ("bubble.left.fill", .gray)
        }
    }
}
