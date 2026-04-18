import SwiftUI

/// Label + control pair for frontmatter forms. Keeps the label column
/// aligned across a column of rows.
struct LabeledRow<Content: View>: View {
    let label: String
    let hint: String?
    @ViewBuilder var content: () -> Content

    init(_ label: String, hint: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.hint = hint
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(label)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                if let hint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            content()
        }
    }
}

/// Multi-line text field with a controlled minimum height, matching the
/// visual density of Claude Code's `description` fields.
struct MultilineTextField: View {
    @Binding var text: String
    var placeholder: String = ""
    var minHeight: CGFloat = 56

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.separator)
                )
                .frame(minHeight: minHeight)

            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
    }
}
