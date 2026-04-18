import SwiftUI

struct NewSkillSheet: View {
    @ObservedObject var store: SkillStore
    let onCreated: (SkillHandle) -> Void

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Skill")
                .font(.title2.bold())

            LabeledRow("Name", hint: "Becomes the directory name under ~/.claude/skills/") {
                TextField("my-skill", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: name) { _, newValue in
                        name = newValue.lowercased()
                            .replacingOccurrences(of: " ", with: "-")
                    }
            }

            LabeledRow("Description") {
                MultilineTextField(
                    text: $description,
                    placeholder: "One sentence summary…",
                    minHeight: 60
                )
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func create() {
        do {
            let handle = try store.create(name: name, description: description)
            onCreated(handle)
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }
}
