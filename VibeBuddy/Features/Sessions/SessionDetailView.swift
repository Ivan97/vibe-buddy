import AppKit
import SwiftUI

struct SessionDetailView: View {
    let summary: SessionSummary
    @StateObject private var loader = SessionMessageLoader()

    /// True when the scrolled-to position is (close to) the last entry.
    /// Drives the magnetic glow + haptic snap. Follow-latest scrolling is
    /// handled natively by `.defaultScrollAnchor(.bottom)`; this state is
    /// only a signal for feedback UI.
    @State private var isPinnedToBottom: Bool = true
    /// Brief visual flash on pin engage/release. Visible for ~300 ms.
    @State private var snapPulse: Bool = false
    /// Debounces the anchor's onDisappear so a brief layout shudder (when
    /// a new entry is appended and LazyVStack re-lays out) doesn't
    /// spuriously flip the pinned-state signal.
    @State private var unpinTask: Task<Void, Never>?

    private static let bottomAnchorID = "bottom-anchor"
    private static let unpinDebounce: Duration = .milliseconds(200)

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
        .onAppear { loader.load(summary) }
    }

    @ViewBuilder
    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if loader.hasMoreAtTop {
                        TopLoadSentinel(isLoading: loader.isPrepending)
                            .onAppear { loader.loadOlderIfNeeded() }
                            .id("top-sentinel")
                    }
                    ForEach(loader.entries) { entry in
                        MessageRow(entry: entry).id(entry.id)
                    }

                    if loader.isInProgress {
                        InProgressIndicator()
                            .id("in-progress-indicator")
                    }

                    // Invisible 1-pt tail anchor. LazyVStack only realizes
                    // it when the user is near the bottom, so
                    // onAppear / onDisappear drive `isPinnedToBottom`.
                    // onDisappear is debounced because new-entry
                    // appends cause a brief re-layout that can wink the
                    // anchor out of the viewport for a single frame.
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchorID)
                        .onAppear {
                            unpinTask?.cancel()
                            unpinTask = nil
                            isPinnedToBottom = true
                        }
                        .onDisappear {
                            unpinTask?.cancel()
                            unpinTask = Task { @MainActor in
                                try? await Task.sleep(for: Self.unpinDebounce)
                                guard !Task.isCancelled else { return }
                                isPinnedToBottom = false
                            }
                        }
                }
                .padding(20)
            }
            .defaultScrollAnchor(.bottom)      // initial position + resize anchor
            .textSelection(.enabled)
            .overlay(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    // Persistent "magnetic pull" glow — visible while
                    // pinned, fades to zero when the user scrolls away.
                    // Gives an ongoing hint that the view is attached
                    // to the bottom edge.
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(isPinnedToBottom ? 0.18 : 0),
                            Color.accentColor.opacity(0)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .frame(height: 42)
                    .animation(.easeInOut(duration: 0.25), value: isPinnedToBottom)

                    // Sharp 2-pt accent line along the very bottom while
                    // pinned — reinforces the "attached" feel. Slightly
                    // brighter during the transition pulse.
                    Rectangle()
                        .fill(Color.accentColor.opacity(
                            snapPulse ? 0.65 : (isPinnedToBottom ? 0.25 : 0)
                        ))
                        .frame(height: 2)
                        .animation(.easeInOut(duration: 0.25), value: isPinnedToBottom)
                }
                .allowsHitTesting(false)
            }
            .onChange(of: loader.anchorRequest) { _, newValue in
                guard let id = newValue else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo(id, anchor: .top)
                }
                loader.anchorRequest = nil
            }
            .onChange(of: isPinnedToBottom) { _, _ in
                triggerSnapFeedback()
            }
        }
    }

    private func triggerSnapFeedback() {
        // Trackpad haptic — .levelChange is more pronounced than .alignment
        // and matches the "snap / click" metaphor better. No-op on hardware
        // without Force Touch, or when the user is currently driving the
        // scroll with a mouse rather than the trackpad.
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .now
        )

        // Visible fallback — a short accent-line pulse at the scroll
        // area's bottom edge. Degrades to nothing on non-haptic hardware
        // users who would otherwise miss the signal entirely.
        withAnimation(.easeOut(duration: 0.15)) {
            snapPulse = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            withAnimation(.easeIn(duration: 0.25)) {
                snapPulse = false
            }
        }
    }
}

// MARK: - in-progress indicator

/// Just the spinner, nothing else. Rendered inside the LazyVStack right
/// after the last entry, so scrolled-up readers don't see it and pinned
/// readers see a single small spinner trailing the newest message.
private struct InProgressIndicator: View {
    var body: some View {
        HStack {
            ProgressView()
                .controlSize(.small)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
    @EnvironmentObject private var titleStore: SessionTitleStore
    @State private var renameSheetShown: Bool = false

    private var displayTitle: String {
        titleStore.customTitle(for: summary.id)
            ?? summary.firstPrompt
            ?? "(no prompt)"
    }

    private var isRenamed: Bool {
        titleStore.customTitle(for: summary.id) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                Button {
                    renameSheetShown = true
                } label: {
                    Image(systemName: isRenamed ? "pencil.circle.fill" : "pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(isRenamed ? "Edit custom title" : "Rename session")
            }

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
        .sheet(isPresented: $renameSheetShown) {
            SessionRenameSheet(
                sessionID: summary.id,
                currentTitle: titleStore.customTitle(for: summary.id) ?? "",
                fallbackTitle: summary.firstPrompt
            )
        }
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
