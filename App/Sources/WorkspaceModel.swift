import AppKit
import Foundation
import SwiftUI

enum WorkspaceError: LocalizedError {
    case noWorkspace
    case outsideWorkspace
    case unreadableFile
    case unsupportedFile

    var errorDescription: String? {
        switch self {
        case .noWorkspace:
            return "No workspace is open."
        case .outsideWorkspace:
            return "The file is outside the open workspace."
        case .unreadableFile:
            return "The file could not be read."
        case .unsupportedFile:
            return "Unsupported file type."
        }
    }
}

enum ExternalDocumentOpenResult: Equatable {
    case handled
    case needsWorkspace(URL)
}

@MainActor
final class WorkspaceModel: ObservableObject {
    @Published private(set) var rootURL: URL? {
        didSet {
            rootURLDidChange?(rootURL)
        }
    }
    @Published var rootChildren: [FileItem] = []
    @Published var tabs: [OpenTab] = []
    @Published private(set) var expandedDirectoryURLs: Set<URL> = []
    @Published var selectedTabID: OpenTab.ID? {
        didSet {
            expandSelectedDocumentDirectory()
            updateSelectedDocumentMonitor()
            persistWorkspace()
        }
    }
    @Published var settings: PersistedSettings {
        didSet {
            if !oldValue.isSidebarVisible && settings.isSidebarVisible {
                expandSelectedDocumentDirectory()
            }
            AppStorage.saveSettings(settings)
            updatePayloadSettings()
        }
    }
    @Published var statusMessage: String?

    private var securityScopedURLs: [URL] = []
    private var initialWorkspaceFile: URL?
    private var selectedDocumentMonitor: DocumentChangeMonitor?
    private var monitoredDocumentURL: URL?
    private var pendingDocumentRefresh: Task<Void, Never>?

    var rootURLDidChange: ((URL?) -> Void)?

    init() {
        self.settings = AppStorage.loadSettings()
        restorePersistedWorkspace()
    }

    var selectedTab: OpenTab? {
        tabs.first { $0.id == selectedTabID }
    }

    var resolver: PathResolver? {
        rootURL.map(PathResolver.init(rootURL:))
    }

    func openDirectoryPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        if panel.runModal() == .OK, let url = panel.url {
            openWorkspace(url)
        }
    }

    func openFilePanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.item]
        panel.prompt = "Open"
        if panel.runModal() == .OK, let url = panel.url {
            openDocumentURL(url)
        }
    }

    func openDocumentURL(_ url: URL) {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: canonical.path, isDirectory: &isDirectory)
        if isDirectory.boolValue {
            setSidebarVisible(true)
            openWorkspace(canonical)
            return
        }

        if let resolver, resolver.contains(canonical) {
            openFile(canonical)
            return
        }

        let parent = canonical.deletingLastPathComponent()
        setSidebarVisible(!FileTypeDetector.isMarkdown(canonical))
        openWorkspace(parent, initialFile: canonical)
    }

    @discardableResult
    func openExternalDocumentURL(_ url: URL, opensWorkspaceIfNeeded: Bool = false) -> ExternalDocumentOpenResult {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: canonical.path, isDirectory: &isDirectory)

        if let resolver, resolver.contains(canonical) {
            if isDirectory.boolValue {
                openDocumentURL(canonical)
            } else {
                openFile(canonical)
            }
            return .handled
        }

        guard opensWorkspaceIfNeeded else {
            return .needsWorkspace(canonical)
        }

        if isDirectory.boolValue {
            openDocumentURL(canonical)
            return .handled
        }

        let parent = canonical.deletingLastPathComponent()
        setSidebarVisible(!FileTypeDetector.isMarkdown(canonical))
        openWorkspace(parent, initialFile: canonical)
        return .handled
    }

    func setSidebarVisible(_ isVisible: Bool) {
        guard settings.isSidebarVisible != isVisible else {
            if isVisible {
                expandSelectedDocumentDirectory()
            }
            return
        }
        var updated = settings
        updated.isSidebarVisible = isVisible
        settings = updated
    }

    func toggleSidebar() {
        setSidebarVisible(!settings.isSidebarVisible)
    }

    func openWorkspace(_ url: URL, initialFile: URL? = nil) {
        stopSelectedDocumentMonitor()
        stopAccessingCurrentWorkspace()

        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        let canonicalInitialFile = initialFile?.standardizedFileURL.resolvingSymlinksInPath()
        startAccessing(canonical)
        if let canonicalInitialFile {
            startAccessing(canonicalInitialFile)
        }
        expandedDirectoryURLs = [canonical]
        rootURL = canonical
        initialWorkspaceFile = canonicalInitialFile
        statusMessage = nil
        tabs = []
        selectedTabID = nil
        loadRootChildren()

        if let canonicalInitialFile {
            openFile(canonicalInitialFile)
        }
        persistWorkspace()
    }

    func loadRootChildren() {
        guard let rootURL else {
            rootChildren = []
            return
        }
        do {
            rootChildren = try FileItemLoader.children(of: rootURL)
        } catch {
            if let initialWorkspaceFile,
               let item = try? FileItemLoader.item(for: initialWorkspaceFile) {
                rootChildren = [item]
                statusMessage = nil
                return
            }
            statusMessage = error.localizedDescription
            rootChildren = []
        }
    }

    func children(of directoryURL: URL) async -> [FileItem] {
        do {
            return try FileItemLoader.children(of: directoryURL)
        } catch {
            return []
        }
    }

    func isDirectoryExpanded(_ url: URL) -> Bool {
        expandedDirectoryURLs.contains(canonicalURL(url))
    }

    func expandDirectory(_ url: URL) {
        guard canTrackDirectory(url) else {
            return
        }
        let canonical = canonicalURL(url)
        var updated = expandedDirectoryURLs
        guard updated.insert(canonical).inserted else {
            return
        }
        expandedDirectoryURLs = updated
    }

    func collapseDirectory(_ url: URL) {
        let canonical = canonicalURL(url)
        var updated = expandedDirectoryURLs
        guard updated.remove(canonical) != nil else {
            return
        }
        expandedDirectoryURLs = updated
    }

    func toggleDirectoryExpansion(_ url: URL) {
        if isDirectoryExpanded(url) {
            collapseDirectory(url)
        } else {
            expandDirectory(url)
        }
    }

    func openFile(_ url: URL) {
        guard let resolver else {
            openDocumentURL(url)
            return
        }
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        guard resolver.contains(canonical) else {
            statusMessage = WorkspaceError.outsideWorkspace.localizedDescription
            return
        }

        let kind = FileTypeDetector.kind(for: canonical, isDirectory: false)
        let previewKind = FileTypeDetector.previewKind(for: kind)
        if let existing = tabs.first(where: { canonicalURL($0.url) == canonical }) {
            selectedTabID = existing.id
            refresh(tabID: existing.id)
            return
        }

        let tab = OpenTab(url: canonical, previewKind: previewKind)
        tabs.append(tab)
        selectedTabID = tab.id
        refresh(tabID: tab.id)
    }

    func openLink(_ rawLink: String, from filePath: String) {
        guard let resolver else {
            return
        }
        do {
            let source = try resolver.resolveWorkspacePath(filePath)
            guard let url = try resolver.resolveLink(rawLink, from: source) else {
                if let external = URL(string: rawLink) {
                    NSWorkspace.shared.open(external)
                }
                return
            }

            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                openWorkspace(url)
                return
            }

            let kind = FileTypeDetector.kind(for: url, isDirectory: false)
            switch kind {
            case .markdown, .image, .text:
                openFile(url)
            case .directory:
                openWorkspace(url)
            case .unsupported:
                NSWorkspace.shared.open(url)
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func closeTab(_ id: OpenTab.ID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else {
            return
        }
        let wasSelected = selectedTabID == id
        tabs.remove(at: idx)

        if tabs.isEmpty {
            selectedTabID = nil
        } else if wasSelected {
            selectedTabID = tabs[min(idx, tabs.count - 1)].id
        }
        if wasSelected {
            updateSelectedDocumentMonitor()
        } else {
            persistWorkspace()
        }
    }

    func closeSelectedTab() {
        guard let selectedTabID else {
            return
        }
        closeTab(selectedTabID)
    }

    func closeAllTabs() {
        guard !tabs.isEmpty else {
            return
        }
        tabs = []
        selectedTabID = nil
    }

    func closeOtherTabs() {
        guard let selectedTab else {
            return
        }
        tabs = [selectedTab]
        selectedTabID = selectedTab.id
    }

    func refreshSelectedTab() {
        guard let selectedTabID else {
            return
        }
        refresh(tabID: selectedTabID)
    }

    func systemAppearanceDidChange() {
        guard settings.theme == .system else {
            return
        }
        updatePayloadSettings()
    }

    func refresh(tabID: OpenTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let rootURL,
              let resolver
        else {
            return
        }

        var tab = tabs[index]
        do {
            let payload = try makePayload(for: tab.url, rootURL: rootURL, resolver: resolver)
            tab.previewKind = payload.kind
            tab.payload = payload
            tab.errorMessage = nil
        } catch {
            tab.payload = nil
            tab.errorMessage = error.localizedDescription
        }
        tabs[index] = tab
    }

    func payloadForSelectedTab() -> RendererPayload? {
        selectedTab?.payload
    }

    func clearWorkspace() {
        stopSelectedDocumentMonitor()
        stopAccessingCurrentWorkspace()
        rootURL = nil
        initialWorkspaceFile = nil
        rootChildren = []
        tabs = []
        expandedDirectoryURLs = []
        selectedTabID = nil
        statusMessage = nil
        AppStorage.saveWorkspace(nil)
    }

    private func makePayload(for url: URL, rootURL: URL, resolver: PathResolver) throws -> RendererPayload {
        guard resolver.contains(url) else {
            throw WorkspaceError.outsideWorkspace
        }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        let kind = FileTypeDetector.kind(for: url, isDirectory: values.isDirectory == true)
        let previewKind = FileTypeDetector.previewKind(for: kind)
        let filePath = try resolver.relativePath(for: url)
        let rootPath = try resolver.relativePath(for: rootURL)
        let theme = resolvedThemeName()

        switch previewKind {
        case .markdown:
            let markdown = try String(contentsOf: url, encoding: .utf8)
            return RendererPayload(
                kind: .markdown,
                filePath: filePath,
                rootPath: rootPath,
                name: url.lastPathComponent,
                markdown: markdown,
                content: nil,
                mediaURL: nil,
                language: nil,
                size: Int64(values.fileSize ?? 0),
                theme: theme,
                fontSize: settings.fontSize,
                fontFamily: settings.rendererFontFamily,
                previewWidth: settings.previewWidth
            )
        case .image:
            return RendererPayload(
                kind: .image,
                filePath: filePath,
                rootPath: rootPath,
                name: url.lastPathComponent,
                markdown: nil,
                content: nil,
                mediaURL: AssetURLBuilder.assetURL(for: filePath),
                language: nil,
                size: Int64(values.fileSize ?? 0),
                theme: theme,
                fontSize: settings.fontSize,
                fontFamily: settings.rendererFontFamily,
                previewWidth: settings.previewWidth
            )
        case .text:
            let content = try String(contentsOf: url, encoding: .utf8)
            return RendererPayload(
                kind: .text,
                filePath: filePath,
                rootPath: rootPath,
                name: url.lastPathComponent,
                markdown: nil,
                content: content,
                mediaURL: nil,
                language: FileTypeDetector.highlightLanguage(for: url),
                size: Int64(values.fileSize ?? 0),
                theme: theme,
                fontSize: settings.fontSize,
                fontFamily: settings.rendererFontFamily,
                previewWidth: settings.previewWidth
            )
        case .unsupported:
            return RendererPayload(
                kind: .unsupported,
                filePath: filePath,
                rootPath: rootPath,
                name: url.lastPathComponent,
                markdown: nil,
                content: nil,
                mediaURL: nil,
                language: nil,
                size: Int64(values.fileSize ?? 0),
                theme: theme,
                fontSize: settings.fontSize,
                fontFamily: settings.rendererFontFamily,
                previewWidth: settings.previewWidth
            )
        }
    }

    private func updatePayloadSettings() {
        for idx in tabs.indices {
            guard var payload = tabs[idx].payload else {
                continue
            }
            payload.theme = resolvedThemeName()
            payload.fontSize = settings.fontSize
            payload.fontFamily = settings.rendererFontFamily
            payload.previewWidth = settings.previewWidth
            tabs[idx].payload = payload
        }
        persistWorkspace()
    }

    private func resolvedThemeName() -> String {
        switch settings.theme {
        case .light:
            return "light"
        case .dark:
            return "dark"
        case .system:
            return Self.isSystemDarkModeEnabled ? "dark" : "light"
        }
    }

    private static var isSystemDarkModeEnabled: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    private func persistWorkspace() {
        guard let rootURL else {
            AppStorage.saveWorkspace(nil)
            return
        }
        do {
            let bookmarkData = try rootURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let resolver = PathResolver(rootURL: rootURL)
            let selected = selectedTab.flatMap { try? resolver.relativePath(for: $0.url) }
            let paths = tabs.compactMap { try? resolver.relativePath(for: $0.url) }
            let persisted = PersistedWorkspace(
                bookmarkData: bookmarkData,
                rootPath: rootURL.path,
                openFilePaths: paths,
                selectedFilePath: selected
            )
            AppStorage.saveWorkspace(persisted)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func restorePersistedWorkspace() {
        guard let persisted = AppStorage.loadWorkspace() else {
            return
        }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: persisted.bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                AppStorage.saveWorkspace(nil)
                return
            }
            openWorkspace(url)
            guard let resolver else {
                return
            }
            for path in persisted.openFilePaths {
                if let fileURL = try? resolver.resolveWorkspacePath(path) {
                    openFile(fileURL)
                }
            }
            if let selectedFilePath = persisted.selectedFilePath,
               let selectedURL = try? resolver.resolveWorkspacePath(selectedFilePath),
               let tab = tabs.first(where: { $0.url == selectedURL }) {
                selectedTabID = tab.id
            } else {
                updateSelectedDocumentMonitor()
            }
        } catch {
            AppStorage.saveWorkspace(nil)
        }
    }

    private func stopAccessingCurrentWorkspace() {
        for url in securityScopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        securityScopedURLs.removeAll()
    }

    private func startAccessing(_ url: URL) {
        let canonical = canonicalURL(url)
        guard !securityScopedURLs.contains(canonical) else {
            return
        }
        if canonical.startAccessingSecurityScopedResource() {
            securityScopedURLs.append(canonical)
        }
    }

    private func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func canTrackDirectory(_ url: URL) -> Bool {
        guard let rootURL else {
            return false
        }
        return PathResolver(rootURL: rootURL).contains(canonicalURL(url))
    }

    private func expandSelectedDocumentDirectory() {
        guard let rootURL,
              let selectedTab
        else {
            return
        }

        let root = canonicalURL(rootURL)
        let resolver = PathResolver(rootURL: root)
        var updated = expandedDirectoryURLs
        updated.insert(root)

        var directoryURL = canonicalURL(selectedTab.url).deletingLastPathComponent()
        while resolver.contains(directoryURL) {
            updated.insert(directoryURL)
            guard directoryURL.path != root.path else {
                break
            }
            let parentURL = canonicalURL(directoryURL.deletingLastPathComponent())
            guard parentURL.path != directoryURL.path else {
                break
            }
            directoryURL = parentURL
        }

        guard updated != expandedDirectoryURLs else {
            return
        }
        expandedDirectoryURLs = updated
    }

    private func updateSelectedDocumentMonitor() {
        pendingDocumentRefresh?.cancel()
        guard let selectedTab else {
            stopSelectedDocumentMonitor()
            return
        }

        let documentURL = canonicalURL(selectedTab.url)
        guard monitoredDocumentURL != documentURL else {
            return
        }

        startSelectedDocumentMonitor(for: documentURL)
    }

    private func scheduleRefreshForChangedDocument(_ documentURL: URL) {
        pendingDocumentRefresh?.cancel()
        pendingDocumentRefresh = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                self?.refreshChangedDocument(documentURL)
            }
        }
    }

    private func refreshChangedDocument(_ documentURL: URL) {
        guard let selectedTabID,
              let selectedTab,
              canonicalURL(selectedTab.url) == documentURL
        else {
            return
        }
        refresh(tabID: selectedTabID)
        startSelectedDocumentMonitor(for: documentURL)
    }

    private func stopSelectedDocumentMonitor() {
        pendingDocumentRefresh?.cancel()
        pendingDocumentRefresh = nil
        selectedDocumentMonitor?.cancel()
        selectedDocumentMonitor = nil
        monitoredDocumentURL = nil
    }

    private func startSelectedDocumentMonitor(for documentURL: URL) {
        selectedDocumentMonitor?.cancel()
        monitoredDocumentURL = documentURL
        selectedDocumentMonitor = DocumentChangeMonitor(url: documentURL) { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleRefreshForChangedDocument(documentURL)
            }
        }
    }
}
