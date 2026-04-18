import SwiftUI

struct SettingsFileListView: View {
    let files: [SettingsFileState]
    @Binding var selected: SettingsTarget

    var body: some View {
        List(selection: $selected) {
            ForEach(files, id: \.target) { file in
                SettingsFileRow(file: file)
                    .tag(file.target)
            }
        }
        .listStyle(.sidebar)
    }
}

private struct SettingsFileRow: View {
    let file: SettingsFileState

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: file.target.systemImage)
                .font(.title3)
                .foregroundStyle(file.exists ? Color.accentColor : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(file.target.title).font(.body)
                    if file.loadError != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                Text(file.target.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if file.exists {
                        Text(Self.bytes(file.byteSize))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                        if let mtime = file.modifiedAt {
                            Text("·").foregroundStyle(.tertiary)
                            Text(Self.relative(mtime))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        Text("Not created")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .italic()
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
