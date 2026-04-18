import SwiftUI

/// Simple modal for setting / clearing a session's custom title.
struct SessionRenameSheet: View {
    let sessionID: String
    let currentTitle: String
    let fallbackTitle: String?

    @EnvironmentObject private var titleStore: SessionTitleStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename session").font(.title2.bold())

            if let fallback = fallbackTitle, !fallback.isEmpty {
                Text("Default: \(fallback)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }

            TextField("Custom title", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(save)

            HStack {
                if !currentTitle.isEmpty {
                    Button("Reset to default") {
                        titleStore.setTitle(nil, for: sessionID)
                        dismiss()
                    }
                    .keyboardShortcut(.delete, modifiers: [.command])
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            draft = currentTitle
            focused = true
        }
    }

    private func save() {
        titleStore.setTitle(draft, for: sessionID)
        dismiss()
    }
}
