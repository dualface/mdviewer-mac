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
    var previewWidth: PreviewWidth = .medium
    var sidebarWidth: Double = 260
}

enum AppTheme: String, CaseIterable, Codable, Sendable {
    case system
    case light
    case dark
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

enum AppStorage {
    private static let workspaceKey = "persistedWorkspace"
    private static let settingsKey = "persistedSettings"

    static func loadWorkspace() -> PersistedWorkspace? {
        guard let data = UserDefaults.standard.data(forKey: workspaceKey) else {
            return nil
        }
        return try? JSONDecoder().decode(PersistedWorkspace.self, from: data)
    }

    static func saveWorkspace(_ workspace: PersistedWorkspace?) {
        guard let workspace else {
            UserDefaults.standard.removeObject(forKey: workspaceKey)
            return
        }
        if let data = try? JSONEncoder().encode(workspace) {
            UserDefaults.standard.set(data, forKey: workspaceKey)
        }
    }

    static func loadSettings() -> PersistedSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(PersistedSettings.self, from: data)
        else {
            return PersistedSettings()
        }
        return settings
    }

    static func saveSettings(_ settings: PersistedSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }
}
