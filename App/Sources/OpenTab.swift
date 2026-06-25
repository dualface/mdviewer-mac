import Foundation

struct OpenTab: Identifiable, Sendable {
    let id: UUID
    let url: URL
    var title: String
    var previewKind: PreviewKind
    var payload: RendererPayload?
    var errorMessage: String?

    init(url: URL, previewKind: PreviewKind) {
        self.id = UUID()
        self.url = url.standardizedFileURL
        self.title = url.lastPathComponent
        self.previewKind = previewKind
    }
}

struct RendererPayload: Codable, Equatable, Sendable {
    var kind: PreviewKind
    var filePath: String
    var rootPath: String
    var name: String
    var markdown: String?
    var content: String?
    var mediaURL: String?
    var language: String?
    var size: Int64
    var theme: String
    var fontSize: Double
    var fontFamily: String
    var previewWidth: PreviewWidth
}
