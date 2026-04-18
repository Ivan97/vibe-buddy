import SwiftUI

struct MCPServerEditor: View {
    @Binding var server: MCPServer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if case .plugin = server.scope {
                    pluginBanner
                }

                Divider()

                transportPicker

                Divider()

                switch server.transport {
                case .stdio:
                    stdioFields
                case .http, .sse:
                    urlFields
                }

                if !server.extras.isEmpty {
                    Divider()
                    extrasView
                }
            }
            .padding(20)
            .disabled(!server.isEditable)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(server.name)
                .font(.title2.bold())
            Text("Renaming a server requires deleting and re-creating it so Claude Code sees the new key under mcpServers.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var pluginBanner: some View {
        if case .plugin(let marketplace, let pluginName) = server.scope {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plugin-provided — read-only").font(.caption.bold())
                    Text("Shipped by \(pluginName) · \(marketplace). Edits aren't saved from here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private var transportPicker: some View {
        LabeledRow("Transport", hint: "Determines which fields below apply") {
            Picker("", selection: $server.transport) {
                ForEach(MCPServer.Transport.allCases, id: \.self) { t in
                    Label(t.label, systemImage: t.icon).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // MARK: - stdio

    private var stdioFields: some View {
        VStack(alignment: .leading, spacing: 18) {
            LabeledRow("Command", hint: "Executable path or PATH-resolved name (e.g. 'npx')") {
                TextField("/path/to/server or 'npx'", text: $server.command)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
            }

            LabeledRow("Arguments", hint: "One per line") {
                MultilineListEditor(
                    items: $server.args,
                    placeholder: "-y\n@modelcontextprotocol/server-filesystem\n/path"
                )
            }

            LabeledRow("Environment", hint: "KEY=VALUE, one per line") {
                EnvEditor(env: $server.env)
            }
        }
    }

    // MARK: - http / sse

    private var urlFields: some View {
        VStack(alignment: .leading, spacing: 18) {
            LabeledRow("URL", hint: server.transport == .http ? "HTTP endpoint" : "Server-sent events endpoint") {
                TextField("https://host/mcp", text: $server.url)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
            }

            LabeledRow("Headers", hint: "Name: value, one per line") {
                HeaderEditor(headers: $server.headers)
            }
        }
    }

    // MARK: - extras

    private var extrasView: some View {
        LabeledRow("Unknown fields", hint: "Preserved on save") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(server.extras.keys.sorted()), id: \.self) { key in
                    HStack(alignment: .top, spacing: 4) {
                        Text("\(key):")
                            .font(.caption.monospaced().bold())
                        Text(server.extras[key] ?? "")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            }
        }
    }
}

// MARK: - list / env / header editors

/// Wraps a [String] behind a single-TextEditor with one item per line.
private struct MultilineListEditor: View {
    @Binding var items: [String]
    let placeholder: String
    @State private var text: String = ""

    var body: some View {
        MultilineTextField(
            text: Binding(
                get: { items.joined(separator: "\n") },
                set: { items = $0.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) }
            ),
            placeholder: placeholder,
            minHeight: 96
        )
    }
}

private struct EnvEditor: View {
    @Binding var env: [String: String]

    var body: some View {
        MultilineTextField(
            text: Binding(
                get: { Self.serialize(env) },
                set: { env = Self.parse($0) }
            ),
            placeholder: "TOKEN=abc123\nDEBUG=1",
            minHeight: 96
        )
    }

    static func serialize(_ env: [String: String]) -> String {
        env.sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
    }

    static func parse(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let pair = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { continue }
            let k = pair[0].trimmingCharacters(in: .whitespaces)
            let v = String(pair[1])
            if !k.isEmpty { out[k] = v }
        }
        return out
    }
}

private struct HeaderEditor: View {
    @Binding var headers: [String: String]

    var body: some View {
        MultilineTextField(
            text: Binding(
                get: { Self.serialize(headers) },
                set: { headers = Self.parse($0) }
            ),
            placeholder: "Authorization: Bearer <token>",
            minHeight: 72
        )
    }

    static func serialize(_ headers: [String: String]) -> String {
        headers.sorted(by: { $0.key < $1.key })
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
    }

    static func parse(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let pair = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { continue }
            let k = pair[0].trimmingCharacters(in: .whitespaces)
            let v = pair[1].trimmingCharacters(in: .whitespaces)
            if !k.isEmpty { out[k] = v }
        }
        return out
    }
}
