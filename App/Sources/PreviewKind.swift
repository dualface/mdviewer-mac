import Foundation
import UniformTypeIdentifiers

enum PreviewKind: String, Codable, Sendable {
    case markdown
    case image
    case text
    case unsupported
}

enum FileKind: String, Codable, Sendable {
    case directory
    case markdown
    case image
    case text
    case unsupported
}

enum FileTypeDetector {
    private static let markdownExtensions: Set<String> = ["md", "markdown"]
    private static let textExtensions: Set<String> = [
        "txt", "log", "go", "js", "jsx", "ts", "tsx", "py", "rb", "php", "java",
        "c", "cpp", "cc", "cxx", "h", "hpp", "rs", "swift", "kt", "scala", "cs",
        "sh", "bash", "zsh", "fish", "ps1", "bat", "json", "yaml", "yml", "toml",
        "ini", "cfg", "conf", "xml", "csv", "html", "css", "scss", "less", "sql",
        "graphql", "proto", "dockerfile", "makefile", "cmake", "tf", "lua", "r", "pl"
    ]

    static func kind(for url: URL, isDirectory: Bool) -> FileKind {
        if isDirectory {
            return .directory
        }

        let ext = url.pathExtension.lowercased()
        if markdownExtensions.contains(ext) {
            return .markdown
        }

        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            if type.conforms(to: .image) {
                return .image
            }
            if type.conforms(to: .text) || type.conforms(to: .sourceCode) || type.conforms(to: .json) {
                return .text
            }
        }

        if textExtensions.contains(ext) || ext.isEmpty {
            return .text
        }

        return .unsupported
    }

    static func previewKind(for fileKind: FileKind) -> PreviewKind {
        switch fileKind {
        case .markdown:
            return .markdown
        case .image:
            return .image
        case .text:
            return .text
        case .directory, .unsupported:
            return .unsupported
        }
    }

    static func highlightLanguage(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "md", "markdown":
            return "markdown"
        case "yml":
            return "yaml"
        case "sh", "bash", "zsh", "fish":
            return "bash"
        case "h", "hpp":
            return "cpp"
        default:
            return ext
        }
    }

    static func isMarkdown(_ url: URL) -> Bool {
        markdownExtensions.contains(url.pathExtension.lowercased())
    }

    static func isHidden(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix(".")
    }
}
