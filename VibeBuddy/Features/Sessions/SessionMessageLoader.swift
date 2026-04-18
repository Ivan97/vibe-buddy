import Foundation

/// Drives transcript rendering: builds a byte-offset index for the session's
/// jsonl file, decodes the most recent `windowSize` entries on open, and
/// prepends older batches as the view scrolls up. Appends new entries to the
/// tail when the file grows (observed via a per-loader FSEvents watcher).
@MainActor
final class SessionMessageLoader: ObservableObject {
    @Published private(set) var entries: [SessionEntry] = []
    @Published private(set) var isInitialLoading: Bool = false
    @Published private(set) var isPrepending: Bool = false
    @Published private(set) var hasMoreAtTop: Bool = false
    @Published private(set) var totalLineCount: Int = 0
    @Published private(set) var loadError: String?

    /// View observes this and calls `ScrollViewReader.scrollTo(id, anchor: .top)`
    /// after a prepend to keep the user's viewport fixed on the same entry.
    @Published var anchorRequest: SessionEntry.ID?

    /// Entries per batch (forward append uses whatever the file grew by;
    /// backward prepend decodes until this many *decoded* entries are
    /// produced or the start of file is hit).
    private let windowSize: Int

    private var currentSummary: SessionSummary?
    private var backend: SessionFileBackend?
    private var topCursor: Int = 0
    private var watcher: DirectoryWatcher?
    /// Last time a prepend batch *completed*. Used to short-circuit
    /// back-to-back `loadOlderIfNeeded` calls that can happen when the
    /// sentinel row's `.task` re-fires during layout flux after a prepend.
    private var lastPrependCompletedAt: Date?
    private static let prependCooldown: TimeInterval = 0.3

    init(windowSize: Int = 500) {
        self.windowSize = windowSize
    }

    deinit {
        watcher?.stop()
    }

    /// True when the transcript's most recent user/assistant turn implies
    /// Claude Code hasn't finished its reply:
    ///  - last turn is `.userText` / `.userToolResults` → AI yet to respond
    ///  - last `.assistantTurn` has a non-"end_turn" `stop_reason`
    ///    (tool_use, max_tokens, ...)
    /// Ignores trailing system / attachment / unknown lines so a batch of
    /// hook outputs after an end_turn doesn't keep the spinner alive.
    var isInProgress: Bool {
        for entry in entries.reversed() {
            switch entry.kind {
            case .userText, .userToolResults:
                return true
            case .assistantTurn(_, _, let stopReason, _):
                return stopReason != "end_turn"
            case .systemNote, .attachment, .unknown:
                continue
            }
        }
        return false
    }

    // MARK: - load

    func load(_ summary: SessionSummary) {
        stopWatching()
        currentSummary = summary
        entries = []
        isInitialLoading = true
        isPrepending = false
        hasMoreAtTop = false
        totalLineCount = 0
        loadError = nil

        let url = summary.path
        let window = windowSize
        Task { [weak self] in
            do {
                let backend = try SessionFileBackend(url: url)
                let total = await backend.lineCount
                let (initial, cursor) = await backend.decodeBackwards(
                    from: total,
                    minEntries: window
                )

                guard let self, self.currentSummary?.path == url else { return }
                self.backend = backend
                self.entries = initial
                self.totalLineCount = total
                self.topCursor = cursor
                self.hasMoreAtTop = cursor > 0
                self.isInitialLoading = false
                self.startWatching()
            } catch {
                guard let self, self.currentSummary?.path == url else { return }
                self.loadError = (error as NSError).localizedDescription
                self.isInitialLoading = false
            }
        }
    }

    // MARK: - older batch

    /// Safe to call from `.task` of a top sentinel — guards against
    /// concurrent, no-op, and rapid-fire invocations.
    func loadOlderIfNeeded() {
        guard
            !isPrepending,
            hasMoreAtTop,
            let backend,
            currentSummary != nil
        else { return }

        if let last = lastPrependCompletedAt,
           Date().timeIntervalSince(last) < Self.prependCooldown {
            return
        }

        isPrepending = true
        let anchorID = entries.first?.id
        let priorCursor = topCursor
        let window = windowSize

        Task { [weak self] in
            let (older, newCursor) = await backend.decodeBackwards(
                from: priorCursor,
                minEntries: window
            )

            guard let self else { return }
            if !older.isEmpty {
                self.entries.insert(contentsOf: older, at: 0)
            }
            self.topCursor = newCursor
            self.hasMoreAtTop = newCursor > 0
            self.isPrepending = false
            self.lastPrependCompletedAt = Date()
            if !older.isEmpty, let anchorID {
                self.anchorRequest = anchorID
            }
        }
    }

    // MARK: - file watching / bottom append

    private func startWatching() {
        guard let summary = currentSummary, watcher == nil else { return }
        let dir = summary.path.deletingLastPathComponent()
        let targetPath = summary.path
        let w = DirectoryWatcher(url: dir) { [weak self] in
            Task { @MainActor in
                self?.onFileEvent(target: targetPath)
            }
        }
        w.start()
        watcher = w
    }

    private func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    private func onFileEvent(target: URL) {
        guard
            let backend,
            currentSummary?.path == target
        else { return }

        Task { [weak self] in
            let added: Int
            do {
                added = try await backend.refreshIfGrown()
            } catch {
                return  // transient, will retry on next event
            }
            guard added > 0, let self else { return }

            let oldTotal = self.totalLineCount
            let newTotal = await backend.lineCount
            guard newTotal > oldTotal else { return }

            let newEntries = await backend.decode(linesIn: oldTotal..<newTotal)
            self.entries.append(contentsOf: newEntries)
            self.totalLineCount = newTotal
        }
    }
}
