import SwiftUI
import AISDK

public struct SessionDetail: View {
    let summary: SessionSummary
    let onRestore: () -> Void
    let onDelete: () -> Void

    public init(summary: SessionSummary, onRestore: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.summary = summary
        self.onRestore = onRestore
        self.onDelete = onDelete
    }

    public var body: some View {
        Form {
            Section("Overview") {
                LabeledContent("Title", value: summary.title ?? "Untitled")
                LabeledContent("Messages", value: "\(summary.messageCount)")
                LabeledContent("Status", value: summary.status.rawValue)
            }

            Section("Actions") {
                Button("Restore in Chat", action: onRestore)
                Button("Delete Session", role: .destructive, action: onDelete)
            }
        }
        .navigationTitle("Session")
    }
}
