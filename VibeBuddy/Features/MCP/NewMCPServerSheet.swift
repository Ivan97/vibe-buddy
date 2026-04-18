import SwiftUI

struct NewMCPServerSheet: View {
    let existingNames: Set<String>
    let onCreated: (MCPServer) -> Void

    @State private var name: String = ""
    @State private var transport: MCPServer.Transport = .stdio
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New MCP Server").font(.title2.bold())

            LabeledRow("Name", hint: "The key in mcpServers — user-visible identifier") {
                TextField("my-server", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
            }

            LabeledRow("Transport", hint: "stdio spawns a process; http/sse connect to a running endpoint") {
                Picker("", selection: $transport) {
                    ForEach(MCPServer.Transport.allCases, id: \.self) { t in
                        Label(t.label, systemImage: t.icon).tag(t)
                    }
                }
                .pickerStyle(.segmented)
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
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if existingNames.contains(trimmed) {
            error = "A server named '\(trimmed)' already exists."
            return
        }
        var server = MCPServer.empty(named: trimmed)
        server.transport = transport
        onCreated(server)
    }
}
