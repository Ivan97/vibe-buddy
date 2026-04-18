import SwiftUI

struct MCPListView: View {
    let servers: [MCPServer]
    @Binding var selectedName: String?
    let onNew: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedName) {
                ForEach(servers) { server in
                    ServerRow(server: server).tag(server.name as String?)
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack {
                Button(action: onNew) {
                    Label("New Server", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selectedName == nil)
                .help("Remove selected server")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

private struct ServerRow: View {
    let server: MCPServer

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: server.transport.icon)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(.body)
                    .lineLimit(1)
                Text(server.transport.label)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
