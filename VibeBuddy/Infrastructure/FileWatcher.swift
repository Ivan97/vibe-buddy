import CoreServices
import Foundation

/// Recursive directory watcher backed by FSEvents. Fires `onChange` on a
/// dedicated utility queue whenever anything inside the watched path is
/// created, modified, or renamed. Callers are responsible for debouncing
/// and for hopping back to their preferred actor.
final class DirectoryWatcher {
    private let path: String
    private let onChange: @Sendable () -> Void
    private let queue: DispatchQueue
    private var stream: FSEventStreamRef?

    init(
        url: URL,
        queue: DispatchQueue = DispatchQueue(
            label: "tech.iooo.vibebuddy.fswatcher",
            qos: .utility
        ),
        onChange: @escaping @Sendable () -> Void
    ) {
        self.path = url.path(percentEncoded: false)
        self.queue = queue
        self.onChange = onChange
    }

    deinit { stop() }

    func start() {
        guard stream == nil else { return }
        guard FileManager.default.fileExists(atPath: path) else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            /* latency */ 0.5,
            flags
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private static let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
        guard let info else { return }
        let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
        watcher.onChange()
    }
}
