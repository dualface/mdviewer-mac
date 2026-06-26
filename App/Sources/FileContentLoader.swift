import Foundation

enum FileContentLoader {
    static let maximumTextPreviewSize: Int64 = 20 * 1024 * 1024

    static func makePayload(
        for url: URL,
        rootURL: URL,
        resolver: PathResolver,
        settings: PersistedSettings,
        theme: String
    ) async throws -> RendererPayload {
        try await Task.detached(priority: .userInitiated) {
            try makePayloadSynchronously(
                for: url,
                rootURL: rootURL,
                resolver: resolver,
                settings: settings,
                theme: theme
            )
        }.value
    }

    static func children(of directoryURL: URL) async throws -> [FileItem] {
        try await Task.detached(priority: .userInitiated) {
            try FileItemLoader.children(of: directoryURL)
        }.value
    }

    private static func makePayloadSynchronously(
        for url: URL,
        rootURL: URL,
        resolver: PathResolver,
        settings: PersistedSettings,
        theme: String
    ) throws -> RendererPayload {
        guard resolver.contains(url) else {
            throw WorkspaceError.outsideWorkspace
        }

        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        let kind = FileTypeDetector.kind(for: url, isDirectory: values.isDirectory == true)
        let previewKind = FileTypeDetector.previewKind(for: kind)
        let filePath = try resolver.relativePath(for: url)
        let rootPath = try resolver.relativePath(for: rootURL)
        let size = Int64(values.fileSize ?? 0)

        switch previewKind {
        case .markdown:
            let markdown = try readUTF8Text(at: url, size: size)
            return RendererPayload(
                schemaVersion: RendererBridgeContract.payloadSchemaVersion,
                kind: .markdown,
                filePath: filePath,
                rootPath: rootPath,
                name: url.lastPathComponent,
                markdown: markdown,
                content: nil,
                mediaURL: nil,
                language: nil,
                size: size,
                theme: theme,
                fontSize: settings.fontSize,
                fontFamily: settings.rendererFontFamily,
                previewWidth: settings.previewWidth
            )
        case .image:
            return RendererPayload(
                schemaVersion: RendererBridgeContract.payloadSchemaVersion,
                kind: .image,
                filePath: filePath,
                rootPath: rootPath,
                name: url.lastPathComponent,
                markdown: nil,
                content: nil,
                mediaURL: AssetURLBuilder.assetURL(for: filePath),
                language: nil,
                size: size,
                theme: theme,
                fontSize: settings.fontSize,
                fontFamily: settings.rendererFontFamily,
                previewWidth: settings.previewWidth
            )
        case .text:
            let content = try readUTF8Text(at: url, size: size)
            return RendererPayload(
                schemaVersion: RendererBridgeContract.payloadSchemaVersion,
                kind: .text,
                filePath: filePath,
                rootPath: rootPath,
                name: url.lastPathComponent,
                markdown: nil,
                content: content,
                mediaURL: nil,
                language: FileTypeDetector.highlightLanguage(for: url),
                size: size,
                theme: theme,
                fontSize: settings.fontSize,
                fontFamily: settings.rendererFontFamily,
                previewWidth: settings.previewWidth
            )
        case .unsupported:
            return RendererPayload(
                schemaVersion: RendererBridgeContract.payloadSchemaVersion,
                kind: .unsupported,
                filePath: filePath,
                rootPath: rootPath,
                name: url.lastPathComponent,
                markdown: nil,
                content: nil,
                mediaURL: nil,
                language: nil,
                size: size,
                theme: theme,
                fontSize: settings.fontSize,
                fontFamily: settings.rendererFontFamily,
                previewWidth: settings.previewWidth
            )
        }
    }

    private static func readUTF8Text(at url: URL, size: Int64) throws -> String {
        guard size <= maximumTextPreviewSize else {
            throw WorkspaceError.fileTooLarge(maximumTextPreviewSize)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
