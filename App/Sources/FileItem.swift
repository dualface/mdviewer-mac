import Foundation

struct FileItem: Identifiable, Hashable, Sendable {
    let id: URL
    let url: URL
    let name: String
    let kind: FileKind
    let size: Int64

    var isDirectory: Bool {
        kind == .directory
    }

    var previewKind: PreviewKind {
        FileTypeDetector.previewKind(for: kind)
    }
}

enum FileItemLoader {
    static func item(for url: URL) throws -> FileItem {
        let canonical = url.standardizedFileURL
        let values = try canonical.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentTypeKey])
        let isDirectory = values.isDirectory == true
        return FileItem(
            id: canonical,
            url: canonical,
            name: canonical.lastPathComponent,
            kind: FileTypeDetector.kind(for: canonical, isDirectory: isDirectory),
            size: Int64(values.fileSize ?? 0)
        )
    }

    static func children(of directoryURL: URL) throws -> [FileItem] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentTypeKey]
        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants]
        )

        return urls
            .filter { !FileTypeDetector.isHidden($0) }
            .compactMap { try? item(for: $0) }
            .filter { $0.isDirectory || $0.kind == .markdown || $0.kind == .image || $0.kind == .text }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }
}
