import SwiftUI

struct SessionDetailView: View {
    let summary: SessionSummary
    @StateObject private var loader = SessionMessageLoader()

    @State private var isPinnedToBottom: Bool = true
    @State private var hasDoneInitialScroll: Bool = false
    @State private var lastKnownCount: Int = 0
    @State private var unreadNew: Int = 0

    private static let bottomAnchorID = "bottom-anchor"

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(summary: summary)
            Divider()

            Group {
                if loader.isInitialLoading && loader.entries.isEmpty {
                    ProgressView("Loading transcript…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = loader.loadError {
                    ContentUnavailableView(
                        "Couldn't load session",
                        systemImage: "exclamationmark.triangle",
                        description: Text(err)
                    )
                } else if loader.entries.isEmpty {
                    ContentUnavailableView(
                        "No messages",
                        systemImage: "text.alignleft",
                        description: Text("This session has no user / assistant turns to show.")
                    )
                } else {
                    transcript
                }
            }
        }
        .onAppear {
            loader.load(summary)
            resetFollowState()
        }
        .onChange(of: summary) { _, new in
            loader.load(new)
            resetFollowState()
        }
    }

    private func resetFollowState() {
        isPinnedToBottom = true
        hasDoneInitialScroll = false
        lastKnownCount = 0
        unreadNew = 0
    }

    @ViewBuilder
    private var transcript: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if loader.hasMoreAtTop {
                            TopLoadSentinel(isLoading: loader.isPrepending)
                                .task(id: loader.entries.first?.id) {
                                    loader.loadOlderIfNeeded()
                                }
                                .id("top-sentinel")
                        }
                        ForEach(loader.entries) { entry in
                            MessageRow(entry: entry).id(entry.id)
                        }
                        // Invisible 1-pt bottom anchor. LazyVStack realizes
                        // it only when the user is at the bottom, so
                        // onAppear / onDisappear give us a cheap
                        // "is-the-user-pinned" signal.
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomAnchorID)
                            .onAppear {
                                isPinnedToBottom = true
                                unreadNew = 0
                            }
                            .onDisappear {
                                isPinnedToBottom = false
                            }
                    }
                    .padding(20)
                }
                .textSelection(.enabled)
                .onChange(of: loader.anchorRequest) { _, newValue in
                    guard let id = newValue else { return }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        proxy.scrollTo(id, anchor: .top)
                    }
                    loader.anchorRequest = nil
                }
                .onChange(of: loader.entries.count) { _, newCount in
                    handleCountChange(newCount: newCount, proxy: proxy)
                }

                if !isPinnedToBottom, unreadNew > 0 {
                    jumpToLatestButton(proxy: proxy)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: unreadNew)
        }
    }

    @ViewBuilder
    private func jumpToLatestButton(proxy: ScrollViewProxy) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
            unreadNew = 0
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                Text("\(unreadNew) new")
                    .font(.caption.bold())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.accentColor.opacity(0.4)))
            .shadow(radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .padding(16)
    }

    private func handleCountChange(newCount: Int, proxy: ScrollViewProxy) {
        let delta = newCount - lastKnownCount
        lastKnownCount = newCount

        // First time entries show up: scroll to the bottom so the user
        // lands on the latest turn rather than the top of the decoded
        // window (500 entries back from the end).
        if !hasDoneInitialScroll, newCount > 0 {
            hasDoneInitialScroll = true
            DispatchQueue.main.async {
                var txn = Transaction()
                txn.disablesAnimations = true
                withTransaction(txn) {
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
            }
            return
        }

        guard delta > 0 else { return }

        if isPinnedToBottom {
            // Follow-latest: scroll the newly appended rows into view.
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
        } else {
            // User is reading history; accumulate for the jump button.
            unreadNew += delta
        }
    }
}

private struct TopLoadSentinel: View {
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 8) {
            Spacer()
            if isLoading {
                ProgressView().controlSize(.small)
                Text("Loading older messages…")
            } else {
                Image(systemName: "arrow.up.circle")
                Text("Scroll up for older messages")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.vertical, 10)
    }
}

// MARK: - header

private struct DetailHeader: View {
    let summary: SessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summary.firstPrompt ?? "(no prompt)")
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 10) {
                Label {
                    Text(summary.projectPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    Image(systemName: "folder")
                }
                Text("·")
                Text("\(summary.messageCount) msgs")
                if let v = summary.claudeVersion {
                    Text("·")
                    Text("CC v\(v)")
                }
                if let branch = summary.gitBranch, !branch.isEmpty, branch != "HEAD" {
                    Text("·")
                    Label(branch, systemImage: "arrow.triangle.branch")
                }
                Spacer()
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([summary.path])
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help("Reveal jsonl file in Finder")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - dispatch

private struct MessageRow: View {
    let entry: SessionEntry

    var body: some View {
        switch entry.kind {
        case .userText(let rich):
            UserTurnView(text: rich, timestamp: entry.timestamp)

        case .userToolResults(let results):
            ToolResultBlock(results: results)

        case .assistantTurn(let blocks, let model, let stopReason, let usage):
            AssistantTurnView(
                blocks: blocks,
                model: model,
                stopReason: stopReason,
                usage: usage,
                timestamp: entry.timestamp
            )

        case .systemNote(_, let summary):
            MetaNote(text: summary, icon: "info.circle")

        case .attachment(_, let summary):
            MetaNote(text: summary, icon: "paperclip")

        case .unknown(let type):
            MetaNote(text: "Unknown entry (\(type))", icon: "questionmark.circle")
        }
    }
}

// MARK: - user

private struct UserTurnView: View {
    let text: RichText
    let timestamp: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("You", systemImage: "person.circle.fill")
                    .font(.caption.bold())
                Spacer()
                if let ts = timestamp {
                    Text(ts, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ExpandableRichText(rich: text)
        }
        .padding(12)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - assistant

private struct AssistantTurnView: View {
    let blocks: [AssistantBlock]
    let model: String?
    let stopReason: String?
    let usage: Usage?
    let timestamp: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Label("Assistant", systemImage: "sparkles")
                    .font(.caption.bold())
                if let model {
                    Text(model)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let ts = timestamp {
                    Text(ts, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                AssistantBlockView(block: block)
            }

            if let usage {
                UsageFooter(usage: usage, stopReason: stopReason)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
    }
}

private struct AssistantBlockView: View {
    let block: AssistantBlock
    @State private var thinkingExpanded = false
    @State private var toolInputExpanded = false

    var body: some View {
        switch block {
        case .text(let rich):
            ExpandableRichText(rich: rich)

        case .thinking(let s):
            DisclosureGroup(isExpanded: $thinkingExpanded) {
                Text(s)
                    .font(.callout.italic())
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Thinking (\(s.count) chars)", systemImage: "brain")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

        case .toolUse(_, let name, let preview):
            DisclosureGroup(isExpanded: $toolInputExpanded) {
                Text(preview)
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    .padding(.top, 4)
            } label: {
                Label("Tool: \(name)", systemImage: "wrench.and.screwdriver")
                    .font(.caption.bold())
            }
        }
    }
}

// MARK: - tool results

private struct ToolResultBlock: View {
    let results: [ToolResult]
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(results, id: \.toolUseId) { result in
                DisclosureGroup(isExpanded: binding(for: result.toolUseId)) {
                    Text(result.content.isEmpty ? "(empty result)" : result.content)
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                        .padding(.top, 4)
                } label: {
                    Label(
                        result.isError ? "Tool result (error)" : "Tool result",
                        systemImage: result.isError ? "xmark.octagon" : "checkmark.circle"
                    )
                    .font(.caption.bold())
                    .foregroundStyle(result.isError ? .red : .secondary)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { newValue in
                if newValue { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }
}

// MARK: - meta

private struct MetaNote: View {
    let text: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - expandable text

/// Renders a `RichText` inline up to `threshold` UTF-8 bytes; longer content
/// shows a truncated preview plus a "Show full" action. Stops SwiftUI Text
/// layout from blowing up on 80 KB+ user messages (observed in claude-mem
/// observer-sessions) that pegged CPU and broke LazyVStack virtualization.
private struct ExpandableRichText: View {
    let rich: RichText
    var threshold: Int = 4_000
    @State private var expanded = false

    var body: some View {
        if expanded || rich.raw.utf8.count <= threshold {
            Text(rich.markdown)
                .textSelection(.enabled)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(truncatedPreview)
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    Image(systemName: "text.append")
                        .foregroundStyle(.tertiary)
                    Text("+\(rich.raw.count - previewCharCount) chars hidden")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Show full") { expanded = true }
                        .buttonStyle(.link)
                        .font(.caption)
                }
                .padding(.top, 2)
            }
        }
    }

    /// Character count used for the preview (approximate — based on the
    /// UTF-8 byte budget, so mostly-ASCII content clips near `threshold`
    /// and multibyte content clips earlier).
    private var previewCharCount: Int {
        var bytes = 0
        var chars = 0
        for ch in rich.raw {
            bytes += ch.utf8.count
            if bytes > threshold { break }
            chars += 1
        }
        return chars
    }

    private var truncatedPreview: String {
        String(rich.raw.prefix(previewCharCount)) + "…"
    }
}

private struct UsageFooter: View {
    let usage: Usage
    let stopReason: String?

    var body: some View {
        HStack(spacing: 10) {
            if let stopReason, !stopReason.isEmpty {
                Text("⏹ \(stopReason)")
            }
            Text("↑ \(usage.inputTokens)")
            Text("↓ \(usage.outputTokens)")
            if usage.cacheReadTokens > 0 {
                Text("cache r: \(usage.cacheReadTokens)")
            }
            if usage.cacheCreationTokens > 0 {
                Text("cache w: \(usage.cacheCreationTokens)")
            }
            Spacer()
        }
        .font(.caption2.monospaced())
        .foregroundStyle(.tertiary)
    }
}
