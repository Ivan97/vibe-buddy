import Foundation

/// Loads, patches, and saves a JSON file while preserving keys the caller
/// doesn't know about. The on-disk file round-trips through pretty-printed
/// JSON with stable key ordering so diffs are meaningful; atomic writes
/// (via `SafeTextWriter`) plus a `.bak` sibling keep disk safety.
///
/// Used by the Hooks, Plugins, MCP and Statusline modules — each reaches
/// into the top-level dictionary for its own field (`hooks`,
/// `enabledPlugins`, `mcpServers`, `statusLine`).
struct SafeJSONStore {
    let url: URL

    enum StoreError: Error, Equatable {
        case notADictionary
        case encodingFailed
    }

    // MARK: - read

    /// Reads the file and returns the top-level object as a dictionary.
    /// Missing file → empty dictionary. Non-dict root → error.
    func load() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        let obj = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = obj as? [String: Any] else {
            throw StoreError.notADictionary
        }
        return dict
    }

    /// Reads a single top-level field, converted to the requested type.
    /// `nil` when the key is absent.
    func field<T>(_ key: String, as type: T.Type) throws -> T? {
        let dict = try load()
        return dict[key] as? T
    }

    // MARK: - write

    /// Writes the full dictionary. Parent dirs are created on demand. An
    /// existing `.bak` sibling is refreshed so the previous revision is
    /// always one rollback away.
    func save(_ dict: [String: Any]) throws {
        let data = try Self.serialize(dict)
        guard let text = String(data: data, encoding: .utf8) else {
            throw StoreError.encodingFailed
        }
        try SafeTextWriter.write(text, to: url)
    }

    /// Patches a single top-level field and writes. Other keys pass through
    /// unchanged. Passing `nil` for `value` removes the key.
    func patch(field key: String, value: Any?) throws {
        var dict = try load()
        if let value {
            dict[key] = value
        } else {
            dict.removeValue(forKey: key)
        }
        try save(dict)
    }

    /// Serializes `dict` to UTF-8 bytes. Pretty-printed, keys sorted so the
    /// resulting file is diff-friendly for the confirm sheet; a trailing
    /// newline matches the convention Claude Code writes.
    static func serialize(_ dict: [String: Any]) throws -> Data {
        let data = try JSONSerialization.data(
            withJSONObject: dict,
            options: [.prettyPrinted, .sortedKeys]
        )
        // Append trailing newline to match POSIX-y text file convention.
        return data + Data([0x0A])
    }

    /// Convenience for tests and diff previews: serialize + decode to
    /// String so callers can show the exact on-disk content.
    static func serializedString(_ dict: [String: Any]) throws -> String {
        let data = try serialize(dict)
        return String(data: data, encoding: .utf8) ?? ""
    }
}
