import SwiftUI

struct NewAgentSheet: View {
    @ObservedObject var store: AgentStore
    let onCreated: (AgentHandle) -> Void

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var model: String?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Agent")
                .font(.title2.bold())

            LabeledRow("Name", hint: "kebab-case; becomes the filename") {
                TextField("my-new-agent", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: name) { _, newValue in
                        // gently nudge toward kebab-case
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

            LabeledRow("Model") {
                Picker("", selection: modelBinding) {
                    Text("Inherit").tag(Optional<String>.none)
                    Text("opus").tag(Optional("opus"))
                    Text("sonnet").tag(Optional("sonnet"))
                    Text("haiku").tag(Optional("haiku"))
                }
                .pickerStyle(.menu)
                .labelsHidden()
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

    private var modelBinding: Binding<String?> {
        Binding(get: { model }, set: { model = $0 })
    }

    private func create() {
        do {
            let handle = try store.create(
                name: name,
                description: description,
                model: model
            )
            onCreated(handle)
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }
}
