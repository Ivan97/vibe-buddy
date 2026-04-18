import SwiftUI

/// Phase 1 MVP markdown body editor — a plain `TextEditor` with a monospaced
/// font. Syntax highlighting can come later as a drop-in replacement; the
/// surface area is intentionally narrow (just a `Binding<String>`).
struct MarkdownEditor: View {
    @Binding var text: String
    var placeholder: String = "Write the system prompt / body here…"
    var minHeight: CGFloat = 240

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .lineSpacing(2)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator, lineWidth: 1)
                )
                .frame(minHeight: minHeight)

            if text.isEmpty {
                Text(placeholder)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                    .allowsHitTesting(false)
            }
        }
    }
}

#Preview {
    @Previewable @State var text = ""
    return MarkdownEditor(text: $text).frame(width: 600, height: 300).padding()
}
