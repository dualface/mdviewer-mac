import Foundation

struct PersistedWorkspace: Codable, Sendable {
    var bookmarkData: Data
    var rootPath: String
    var openFilePaths: [String]
    var selectedFilePath: String?
}

struct PersistedSettings: Codable, Sendable {
    var theme: AppTheme = .system
    var fontSize: Double = 16
    var fontFamily: String = FontFamily.systemID
    var previewWidth: PreviewWidth = .medium
    var sidebarWidth: Double = 260
    var isSidebarVisible: Bool = true
    var isToolbarVisible: Bool = true

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .system
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 16
        fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily) ?? FontFamily.systemID
        previewWidth = try container.decodeIfPresent(PreviewWidth.self, forKey: .previewWidth) ?? .medium
        sidebarWidth = try container.decodeIfPresent(Double.self, forKey: .sidebarWidth) ?? 260
        isSidebarVisible = try container.decodeIfPresent(Bool.self, forKey: .isSidebarVisible) ?? true
        isToolbarVisible = try container.decodeIfPresent(Bool.self, forKey: .isToolbarVisible) ?? true
    }

    var rendererFontFamily: String {
        FontFamily.cssFamily(for: fontFamily)
    }
}

enum FontFamily {
    static let systemID = "__system"
    static let serifID = "__serif"
    static let monospaceID = "__monospace"

    static func cssFamily(for id: String) -> String {
        switch id {
        case systemID:
            return "-apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif"
        case serifID:
            return "'New York', Georgia, ui-serif, serif"
        case monospaceID:
            return "'SF Mono', Menlo, Monaco, Consolas, monospace"
        default:
            return "\(quotedCSSFamily(id)), -apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif"
        }
    }

    private static func quotedCSSFamily(_ family: String) -> String {
        let escaped = family
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return "'\(escaped)'"
    }
}

struct PreviewFontOption: Hashable, Identifiable, Sendable {
    let id: String
    let label: String
}

enum PreviewFont {
    static let sizes: [Double] = [12, 13, 14, 15, 16, 17, 18, 20, 22, 24, 28]

    static let options: [PreviewFontOption] = [
        PreviewFontOption(id: FontFamily.systemID, label: "System"),
        PreviewFontOption(id: FontFamily.serifID, label: "Serif"),
        PreviewFontOption(id: FontFamily.monospaceID, label: "Mono"),
        PreviewFontOption(id: "Avenir Next", label: "Avenir Next"),
        PreviewFontOption(id: "Georgia", label: "Georgia"),
        PreviewFontOption(id: "Helvetica Neue", label: "Helvetica"),
        PreviewFontOption(id: "Menlo", label: "Menlo")
    ]
}

enum AppTheme: String, CaseIterable, Codable, Sendable {
    case system
    case light
    case dark

    var label: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }
}

enum PreviewWidth: String, CaseIterable, Codable, Sendable {
    case full
    case wide
    case medium
    case narrow

    var label: String {
        switch self {
        case .full:
            return "Full"
        case .wide:
            return "Wide"
        case .medium:
            return "Medium"
        case .narrow:
            return "Narrow"
        }
    }
}

@MainActor
enum AppStorage {
    private static let workspaceKey = "persistedWorkspace"
    private static let settingsKey = "persistedSettings"
    static var defaults: UserDefaults = .standard

    static func loadWorkspace() -> PersistedWorkspace? {
        guard let data = defaults.data(forKey: workspaceKey) else {
            return nil
        }
        return try? JSONDecoder().decode(PersistedWorkspace.self, from: data)
    }

    static func saveWorkspace(_ workspace: PersistedWorkspace?) {
        guard let workspace else {
            defaults.removeObject(forKey: workspaceKey)
            return
        }
        if let data = try? JSONEncoder().encode(workspace) {
            defaults.set(data, forKey: workspaceKey)
        }
    }

    static func loadSettings() -> PersistedSettings {
        guard let data = defaults.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(PersistedSettings.self, from: data)
        else {
            return PersistedSettings()
        }
        return settings
    }

    static func saveSettings(_ settings: PersistedSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: settingsKey)
        }
    }
}
