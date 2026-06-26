import AppKit
import Foundation
import SwiftUI

enum WorkspaceError: LocalizedError {
    case noWorkspace
    case outsideWorkspace
    case unreadableFile
    case unsupportedFile
    case fileTooLarge(Int64)

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
        case .fileTooLarge(let maximumSize):
            return "The file is too large to preview. Maximum supported size is \(ByteCountFormatter.string(fromByteCount: maximumSize, countStyle: .file))."
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
    @Published var expandedDirectoryURLs: Set<URL> = []
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

    var securityScopedURLs: [URL] = []
    var initialWorkspaceFile: URL?
    var selectedDocumentMonitor: DocumentChangeMonitor?
    var monitoredDocumentURL: URL?
    var pendingDocumentRefresh: Task<Void, Never>?
    var pendingTabSelectionRefresh: Task<Void, Never>?
    var payloadTasks: [OpenTab.ID: Task<Void, Never>] = [:]
    var lastSelectedTabCloseUptime: TimeInterval = 0

    static let duplicateSelectedTabCloseInterval: TimeInterval = 0.15

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

    func openDirectoryURL(_ url: URL) {
        setSidebarVisible(true)
        openWorkspace(url)
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

    func toggleToolbar() {
        var updated = settings
        updated.isToolbarVisible.toggle()
        settings = updated
    }

    func setPreviewWidth(_ previewWidth: PreviewWidth) {
        guard settings.previewWidth != previewWidth else {
            return
        }
        var updated = settings
        updated.previewWidth = previewWidth
        settings = updated
    }

    func setTheme(_ theme: AppTheme) {
        guard settings.theme != theme else {
            return
        }
        var updated = settings
        updated.theme = theme
        settings = updated
    }

    func setPreviewFontSize(_ fontSize: Double) {
        guard settings.fontSize != fontSize else {
            return
        }
        var updated = settings
        updated.fontSize = fontSize
        settings = updated
    }

    func setPreviewFontFamily(_ fontFamily: String) {
        guard settings.fontFamily != fontFamily else {
            return
        }
        var updated = settings
        updated.fontFamily = fontFamily
        settings = updated
    }

    func openWorkspace(_ url: URL, initialFile: URL? = nil) {
        stopSelectedDocumentMonitor()
        cancelAllPayloadTasks()
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
        Task { @MainActor [weak self] in
            do {
                let children = try await FileContentLoader.children(of: rootURL)
                guard self?.rootURL == rootURL else {
                    return
                }
                self?.rootChildren = children
            } catch {
                guard self?.rootURL == rootURL else {
                    return
                }
                if let initialWorkspaceFile = self?.initialWorkspaceFile,
                   let item = try? FileItemLoader.item(for: initialWorkspaceFile) {
                    self?.rootChildren = [item]
                    self?.statusMessage = nil
                    return
                }
                self?.statusMessage = error.localizedDescription
                self?.rootChildren = []
            }
        }
    }

    func children(of directoryURL: URL) async -> [FileItem] {
        do {
            return try await FileContentLoader.children(of: directoryURL)
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
            selectTab(existing.id)
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
                statusMessage = "Remote links are disabled."
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
        cancelPayloadTask(for: id)

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
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastSelectedTabCloseUptime > Self.duplicateSelectedTabCloseInterval else {
            return
        }
        lastSelectedTabCloseUptime = now
        closeTab(selectedTabID)
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else {
            return
        }
        selectTab(tabs[index].id)
    }

    func selectTab(_ id: OpenTab.ID) {
        guard tabs.contains(where: { $0.id == id }) else {
            return
        }
        selectedTabID = id
        scheduleRefreshAfterSelection(tabID: id)
    }

    func closeAllTabs() {
        guard !tabs.isEmpty else {
            return
        }
        cancelAllPayloadTasks()
        tabs = []
        selectedTabID = nil
    }

    func closeOtherTabs() {
        guard let selectedTab else {
            return
        }
        for tab in tabs where tab.id != selectedTab.id {
            cancelPayloadTask(for: tab.id)
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

    func clearWorkspace() {
        stopSelectedDocumentMonitor()
        cancelAllPayloadTasks()
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

}
