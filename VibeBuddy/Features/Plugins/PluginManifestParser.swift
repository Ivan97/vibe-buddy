import Foundation

/// Parses a `plugin.json` file into a `PluginManifest`. Intentionally
/// permissive: `author` can be a string or an object (with `name` / `email`);
/// missing keys degrade to `nil`.
enum PluginManifestParser {

    static let knownKeys: Set<String> = [
        "name", "version", "description", "author",
        "homepage", "repository", "license", "keywords"
    ]

    static func parse(data: Data) throws -> PluginManifest {
        let obj = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = obj as? [String: Any] else {
            throw NSError(
                domain: "VibeBuddy.PluginManifestParser",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "plugin.json root must be an object"]
            )
        }
        return parse(dict: dict)
    }

    static func parse(url: URL) throws -> PluginManifest {
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    static func parse(dict: [String: Any]) -> PluginManifest {
        let name = (dict["name"] as? String) ?? ""
        let version = dict["version"] as? String
        let description = dict["description"] as? String
        let homepage = dict["homepage"] as? String
        let repository = dict["repository"] as? String
        let license = dict["license"] as? String
        let keywords = (dict["keywords"] as? [String]) ?? []

        let author: String? = {
            if let s = dict["author"] as? String { return s }
            if let obj = dict["author"] as? [String: Any] {
                let author = (obj["name"] as? String) ?? ""
                let email = (obj["email"] as? String).map { " <\($0)>" } ?? ""
                let combined = author + email
                return combined.isEmpty ? nil : combined
            }
            return nil
        }()

        var extras: [String: String] = [:]
        for (key, value) in dict where !knownKeys.contains(key) {
            if let s = value as? String {
                extras[key] = s
            } else if let b = value as? Bool {
                extras[key] = b ? "true" : "false"
            } else if let n = value as? NSNumber {
                extras[key] = n.stringValue
            }
        }

        return PluginManifest(
            name: name,
            version: version,
            description: description,
            author: author,
            homepage: homepage,
            repository: repository,
            license: license,
            keywords: keywords,
            extras: extras
        )
    }
}
