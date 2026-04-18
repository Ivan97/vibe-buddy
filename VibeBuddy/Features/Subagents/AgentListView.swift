import SwiftUI

struct AgentListView: View {
    let handles: [AgentHandle]
    @Binding var selected: AgentHandle.ID?
    @Binding var searchText: String
    let totalCount: Int
    let isLoading: Bool
    let error: String?
    let onNewAgent: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            List(selection: $selected) {
                Section {
                    ForEach(handles) { handle in
                        AgentRow(handle: handle)
                            .tag(handle.id as AgentHandle.ID?)
                    }
                } header: {
                    HStack {
                        Image(systemName: "globe")
                        Text("Global").font(.caption.bold())
                        Spacer()
                        Text("\(handles.count)\(searchText.isEmpty ? "" : " / \(totalCount)")")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if handles.isEmpty, !isLoading {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No agents" : "No matches",
                        systemImage: "person.2",
                        description: Text(searchText.isEmpty
                            ? "Click New Agent to create your first one."
                            : "Try a different query.")
                    )
                } else if isLoading, handles.isEmpty {
                    ProgressView()
                }
            }

            Divider()
            footerBar
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search agents", text: $searchText)
                .textFieldStyle(.plain)
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .symbolEffect(.pulse, options: .repeating, isActive: isLoading)
            }
            .buttonStyle(.borderless)
            .disabled(isLoading)
            .help("Refresh from disk")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var footerBar: some View {
        HStack {
            Button(action: onNewAgent) {
                Label("New Agent", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct AgentRow: View {
    let handle: AgentHandle

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(handle.name)
                .font(.body)
                .lineLimit(1)
            if !handle.description.isEmpty {
                Text(handle.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}
