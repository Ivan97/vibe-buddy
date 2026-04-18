import SwiftUI

/// Body editor with a Preview / Edit toggle. Defaults to Preview so reading
/// an agent's system prompt doesn't expose raw markdown; the user flips to
/// Edit when they actually want to modify. Designed to drop in anywhere
/// `MarkdownEditor` is used; reused in Phase 1 by Prompts and Skills.
struct MarkdownBodyEditor: View {
    @Binding var text: String
    var placeholder: String = "Write the system prompt / body here…"
    var minHeight: CGFloat = 320

    @State private var mode: Mode = .preview

    enum Mode: String, Hashable, CaseIterable {
        case preview, edit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $mode) {
                Text("Preview").tag(Mode.preview)
                Text("Edit").tag(Mode.edit)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 160)

            switch mode {
            case .preview:
                MarkdownPreview(raw: text, minHeight: minHeight)
            case .edit:
                MarkdownEditor(
                    text: $text,
                    placeholder: placeholder,
                    minHeight: minHeight
                )
            }
        }
    }
}

/// Read-only markdown preview. Uses `AttributedString(markdown:)` with inline
/// interpretation preserving whitespace — same trade-off as the transcript
/// renderer. Skips parsing entirely for content past a 16 KB UTF-8 ceiling
/// (same pathological-parser guard as `RichText`).
private struct MarkdownPreview: View {
    let raw: String
    let minHeight: CGFloat

    var body: some View {
        ScrollView {
            Group {
                if raw.isEmpty {
                    emptyState
                } else {
                    Text(attributed)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            }
        }
        .frame(minHeight: minHeight)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundStyle(.tertiary)
            Text("No body yet — switch to Edit to write the system prompt.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var attributed: AttributedString {
        if raw.utf8.count > 16_000 {
            return AttributedString(raw)
        }
        return (try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(raw)
    }
}
