import Foundation

enum AssetURLBuilder {
    static let scheme = "mdv-file"
    static let host = "asset"

    static func assetURL(for workspacePath: String) -> String {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [
            URLQueryItem(name: "path", value: workspacePath)
        ]
        return components.url?.absoluteString ?? ""
    }
}
