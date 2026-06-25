import Foundation
import UniformTypeIdentifiers
import WebKit

final class WorkspaceAssetSchemeHandler: NSObject, WKURLSchemeHandler, @unchecked Sendable {
    private let lock = NSLock()
    private var resolver: PathResolver?

    @MainActor
    init(workspace: WorkspaceModel) {
        self.resolver = workspace.resolver
    }

    func update(resolver: PathResolver?) {
        lock.withLock {
            self.resolver = resolver
        }
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let resolver = lockedResolver(),
              let requestURL = urlSchemeTask.request.url,
              let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false),
              let path = components.queryItems?.first(where: { $0.name == "path" })?.value
        else {
            urlSchemeTask.didFailWithError(WorkspaceError.noWorkspace)
            return
        }

        do {
            let fileURL = try resolver.resolveWorkspacePath(path)
            let data = try Data(contentsOf: fileURL)
            let mimeType = mimeType(for: fileURL)
            let response = URLResponse(
                url: requestURL,
                mimeType: mimeType,
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
    }

    private func lockedResolver() -> PathResolver? {
        lock.withLock {
            resolver
        }
    }

    private func mimeType(for url: URL) -> String {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
           let mime = type.preferredMIMEType {
            return mime
        }
        switch url.pathExtension.lowercased() {
        case "svg":
            return "image/svg+xml"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        default:
            return "application/octet-stream"
        }
    }
}
