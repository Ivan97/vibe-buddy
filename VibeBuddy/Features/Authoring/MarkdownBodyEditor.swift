import MarkdownUI
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

/// Read-only markdown preview rendered via MarkdownUI — GitHub-flavored
/// Markdown with real block-level layout (headers sized, lists bulleted,
/// code blocks fenced, tables, blockquotes, task lists).
///
/// Falls back to plain monospaced text above a 256 KB UTF-8 ceiling.
/// Rationale: unlike the transcript (where 500 entries are parsed on open
/// and LazyVStack keeps re-measuring), preview renders a single document
/// the user explicitly picked, so one-shot parsing of 20-100 KB bodies is
/// fine. Agent system prompts and SKILL.md files commonly sit in the
/// 15-25 KB range.
private struct MarkdownPreview: View {
    let raw: String
    let minHeight: CGFloat

    private static let parseCeiling = 256_000

    var body: some View {
        ScrollView {
            Group {
                if raw.isEmpty {
                    emptyState
                } else if raw.utf8.count > Self.parseCeiling {
                    Text(raw)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                } else {
                    Markdown(raw)
                        .textSelection(.enabled)
                        .markdownTheme(.gitHub)
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
}
