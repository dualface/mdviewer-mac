import Foundation

enum PathResolverError: Error, Equatable {
    case outsideWorkspace
    case invalidPath
}

struct PathResolver: Sendable {
    let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    func contains(_ url: URL) -> Bool {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        return canonical.path == rootURL.path || canonical.path.hasPrefix(rootURL.path + "/")
    }

    func relativePath(for url: URL) throws -> String {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        guard contains(canonical) else {
            throw PathResolverError.outsideWorkspace
        }
        if canonical.path == rootURL.path {
            return "/"
        }
        return "/" + String(canonical.path.dropFirst(rootURL.path.count + 1))
    }

    func resolveWorkspacePath(_ path: String) throws -> URL {
        let cleaned = normalizeWorkspacePath(path)
        guard !cleaned.contains("..") else {
            throw PathResolverError.invalidPath
        }
        let relative = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let resolved = relative.isEmpty ? rootURL : rootURL.appendingPathComponent(relative)
        let canonical = resolved.standardizedFileURL.resolvingSymlinksInPath()
        guard contains(canonical) else {
            throw PathResolverError.outsideWorkspace
        }
        return canonical
    }

    func resolveLink(_ rawLink: String, from documentURL: URL) throws -> URL? {
        guard let decoded = rawLink.removingPercentEncoding else {
            throw PathResolverError.invalidPath
        }
        let withoutFragment = decoded.components(separatedBy: "#").first ?? decoded
        guard !withoutFragment.isEmpty else {
            return nil
        }

        if let url = URL(string: withoutFragment), let scheme = url.scheme, scheme != "file" {
            return nil
        }

        let resolved: URL
        if withoutFragment.hasPrefix("/") {
            resolved = rootURL.appendingPathComponent(String(withoutFragment.dropFirst()))
        } else {
            resolved = documentURL.deletingLastPathComponent().appendingPathComponent(withoutFragment)
        }

        let canonical = resolved.standardizedFileURL.resolvingSymlinksInPath()
        guard contains(canonical) else {
            throw PathResolverError.outsideWorkspace
        }
        return canonical
    }

    private func normalizeWorkspacePath(_ path: String) -> String {
        var value = path
        if let decoded = value.removingPercentEncoding {
            value = decoded
        }
        if value.hasPrefix("file://"), let url = URL(string: value) {
            value = url.path
        }
        if value.hasPrefix(rootURL.path) {
            value = String(value.dropFirst(rootURL.path.count))
        }
        return value.replacingOccurrences(of: "\\", with: "/")
    }
}
