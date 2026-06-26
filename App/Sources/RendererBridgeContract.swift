import Foundation

enum RendererBridgeContract {
    static let payloadSchemaVersion = 1

    enum Message {
        static let rendererReady = "rendererReady"
        static let renderComplete = "renderComplete"
        static let openLink = "openLink"
        static let renderError = "renderError"
    }

    enum PayloadKey {
        static let renderID = "renderID"
        static let href = "href"
        static let filePath = "filePath"
        static let message = "message"
    }
}
