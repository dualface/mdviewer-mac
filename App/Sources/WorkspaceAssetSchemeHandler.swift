import Foundation
import UniformTypeIdentifiers
@preconcurrency import WebKit

final class WorkspaceAssetSchemeHandler: NSObject, WKURLSchemeHandler, @unchecked Sendable {
    private let lock = NSLock()
    private var resolver: PathResolver?
    private let queue = DispatchQueue(label: "com.dualface.mdviewer.workspace-asset-scheme", qos: .userInitiated)

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
        let taskBox = SendableURLSchemeTask(urlSchemeTask)

        queue.async {
            do {
                let fileURL = try resolver.resolveWorkspacePath(path)
                try WorkspaceAssetStreamer.streamFile(at: fileURL, requestURL: requestURL, to: taskBox.task)
            } catch {
                taskBox.task.didFailWithError(error)
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
    }

    private func lockedResolver() -> PathResolver? {
        lock.withLock {
            resolver
        }
    }
}

private final class SendableURLSchemeTask: @unchecked Sendable {
    let task: WKURLSchemeTask

    init(_ task: WKURLSchemeTask) {
        self.task = task
    }
}

private enum WorkspaceAssetStreamer {
    static func streamFile(at fileURL: URL, requestURL: URL, to urlSchemeTask: WKURLSchemeTask) throws {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        let fileSize = values.fileSize ?? 0
        let response = URLResponse(
            url: requestURL,
            mimeType: mimeType(for: fileURL),
            expectedContentLength: fileSize,
            textEncodingName: nil
        )
        urlSchemeTask.didReceive(response)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        while true {
            let data = try handle.read(upToCount: chunkSize) ?? Data()
            if data.isEmpty {
                break
            }
            urlSchemeTask.didReceive(data)
        }
        urlSchemeTask.didFinish()
    }

    private static func mimeType(for url: URL) -> String {
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

    private static let chunkSize = 256 * 1024
}
