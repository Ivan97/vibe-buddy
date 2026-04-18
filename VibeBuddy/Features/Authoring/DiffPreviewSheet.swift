import SwiftUI

/// Modal confirmation sheet shown before a write-back. Displays a unified
/// line diff and asks the user to confirm before the change actually lands
/// on disk. Reusable across Subagents / Skills now; will be reused for
/// Phase 2's JSON config writes too.
struct DiffPreviewSheet: View {
    let title: String
    let message: String?
    let beforeText: String
    let afterText: String
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        message: String? = nil,
        beforeText: String,
        afterText: String,
        onConfirm: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.beforeText = beforeText
        self.afterText = afterText
        self.onConfirm = onConfirm
    }

    private var lines: [DiffLine] {
        TextDiff.unified(before: beforeText, after: afterText)
    }

    private var stats: (added: Int, removed: Int) {
        var added = 0
        var removed = 0
        for line in lines {
            switch line {
            case .added:   added += 1
            case .removed: removed += 1
            case .context: break
            }
        }
        return (added, removed)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            diffScroll
            Divider()
            footer
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 440, idealHeight: 560)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.secondary)
                Text(title).font(.headline)
                Spacer()
                HStack(spacing: 8) {
                    Text("+\(stats.added)")
                        .foregroundStyle(.green)
                    Text("−\(stats.removed)")
                        .foregroundStyle(.red)
                }
                .font(.callout.monospacedDigit())
            }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var diffScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    DiffLineRow(line: line)
                }
            }
            .padding(.vertical, 6)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("Save") {
                onConfirm()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
    }
}

private struct DiffLineRow: View {
    let line: DiffLine

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(marker)
                .frame(width: 24, alignment: .center)
                .foregroundStyle(markerColor)
                .background(background)
            Text(content.isEmpty ? " " : content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 1)
                .background(background)
                .textSelection(.enabled)
        }
        .font(.system(.caption, design: .monospaced))
    }

    private var marker: String {
        switch line {
        case .context: return " "
        case .added:   return "+"
        case .removed: return "−"
        }
    }

    private var content: String {
        switch line {
        case .context(let s), .added(let s), .removed(let s):
            return s
        }
    }

    private var markerColor: Color {
        switch line {
        case .context: return .secondary
        case .added:   return .green
        case .removed: return .red
        }
    }

    private var background: Color {
        switch line {
        case .context: return .clear
        case .added:   return Color.green.opacity(0.12)
        case .removed: return Color.red.opacity(0.12)
        }
    }
}
