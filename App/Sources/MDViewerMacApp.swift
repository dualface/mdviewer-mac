import SwiftUI

@main
struct MDViewerMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var workspace = WorkspaceModel()
    private let tabShortcutKeys: [Character] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    private let previewWidthShortcuts: [(key: Character, width: PreviewWidth)] = [
        ("1", .full),
        ("2", .wide),
        ("3", .medium),
        ("4", .narrow),
    ]

    var body: some Scene {
        Window("MarkdownViewer", id: "main") {
            ContentView()
                .environmentObject(workspace)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear {
                    appDelegate.attach(workspace)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button {
                    workspace.openFilePanel()
                } label: {
                    Label("Open File...", systemImage: "doc")
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button {
                    workspace.openDirectoryPanel()
                } label: {
                    Label("Open Folder...", systemImage: "folder")
                }
                .keyboardShortcut("e", modifiers: [.command])

                Divider()

                Button {
                    workspace.closeSelectedTab()
                } label: {
                    Label("Close File", systemImage: "xmark.circle")
                }
                .keyboardShortcut("w", modifiers: [.command])
                .disabled(workspace.selectedTab == nil)

                Button {
                    workspace.closeOtherTabs()
                } label: {
                    Label("Close Other Files", systemImage: "rectangle.stack.badge.minus")
                }
                .keyboardShortcut("w", modifiers: [.command, .option])
                .disabled(workspace.selectedTab == nil || workspace.tabs.count <= 1)

                Button {
                    workspace.closeAllTabs()
                } label: {
                    Label("Close All Files", systemImage: "xmark.circle.fill")
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(workspace.tabs.isEmpty)
            }

            CommandGroup(replacing: .sidebar) {
                Button {
                    workspace.refreshSelectedTab()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: [.command])

                Menu {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Button {
                            workspace.setTheme(theme)
                        } label: {
                            Label(theme.label, systemImage: theme.menuSystemImage)
                        }
                        .disabled(workspace.settings.theme == theme)
                    }
                } label: {
                    Label("Theme", systemImage: "circle.lefthalf.filled")
                }

                Divider()

                Menu {
                    ForEach(previewWidthShortcuts, id: \.width) { shortcut in
                        Button {
                            workspace.setPreviewWidth(shortcut.width)
                        } label: {
                            Label(shortcut.width.label, systemImage: shortcut.width.menuSystemImage)
                        }
                        .keyboardShortcut(KeyEquivalent(shortcut.key), modifiers: [.option])
                        .disabled(workspace.settings.previewWidth == shortcut.width)
                    }
                } label: {
                    Label("Preview Width", systemImage: "arrow.left.and.right")
                }

                Divider()

                Menu {
                    Menu {
                        ForEach(PreviewFont.sizes, id: \.self) { size in
                            Button {
                                workspace.setPreviewFontSize(size)
                            } label: {
                                Label("\(Int(size))px", systemImage: "textformat.size")
                            }
                            .disabled(workspace.settings.fontSize == size)
                        }
                    } label: {
                        Label("Size", systemImage: "textformat.size")
                    }

                    Divider()

                    Menu {
                        ForEach(PreviewFont.options) { option in
                            Button {
                                workspace.setPreviewFontFamily(option.id)
                            } label: {
                                Label(option.label, systemImage: option.menuSystemImage)
                            }
                            .disabled(workspace.settings.fontFamily == option.id)
                        }
                    } label: {
                        Label("Family", systemImage: "textformat")
                    }
                } label: {
                    Label("Preview Font", systemImage: "textformat")
                }

                Divider()

                Button {
                    workspace.toggleSidebar()
                } label: {
                    Label(workspace.settings.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar", systemImage: "sidebar.left")
                }
                .keyboardShortcut("b", modifiers: [.command])

                Button {
                    workspace.toggleToolbar()
                } label: {
                    Label(workspace.settings.isToolbarVisible ? "Hide Toolbar" : "Show Toolbar", systemImage: "menubar.rectangle")
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }

            CommandGroup(after: .windowArrangement) {
                ForEach(0..<10, id: \.self) { index in
                    Button {
                        workspace.selectTab(at: index)
                    } label: {
                        Label("Select File \(index + 1)", systemImage: "doc.text")
                    }
                    .keyboardShortcut(KeyEquivalent(tabShortcutKeys[index]), modifiers: [.command])
                    .disabled(workspace.tabs.count <= index)
                }
            }
        }
    }
}

private extension AppTheme {
    var menuSystemImage: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max"
        case .dark:
            return "moon"
        }
    }
}

private extension PreviewWidth {
    var menuSystemImage: String {
        switch self {
        case .full:
            return "arrow.left.and.right"
        case .wide:
            return "rectangle"
        case .medium:
            return "rectangle.center.inset.filled"
        case .narrow:
            return "sidebar.right"
        }
    }
}

private extension PreviewFontOption {
    var menuSystemImage: String {
        switch id {
        case FontFamily.systemID:
            return "textformat"
        case FontFamily.serifID:
            return "textformat.alt"
        case FontFamily.monospaceID, "Menlo":
            return "curlybraces"
        default:
            return "textformat.abc"
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let openDocumentRequestNotification = Notification.Name("com.dualface.mdviewer.mac.openDocumentRequest")
    private static let notificationObject = Bundle.main.bundleIdentifier ?? "com.dualface.mdviewer.mac"

    weak var workspace: WorkspaceModel?
    private var pendingDocumentURLs: [URL] = []
    private let workspaceInstances = WorkspaceInstanceRegistry()
    private var closeDocumentShortcutMonitor: Any?
    private var isObservingOpenDocumentRequests = false

    @MainActor
    func attach(_ workspace: WorkspaceModel) {
        self.workspace = workspace
        workspace.rootURLDidChange = { [weak self] rootURL in
            self?.workspaceInstances.update(rootURL: rootURL)
        }
        workspaceInstances.unregister()
        observeOpenDocumentRequests()
        installCloseDocumentShortcutMonitor()
        restoreVisibleWindowPlacement()
        let didOpenPendingInCurrentInstance = openPendingDocumentURLs()
        if didOpenPendingInCurrentInstance != false {
            workspaceInstances.update(rootURL: workspace.rootURL)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            openDocumentURLs(urls)
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        Task { @MainActor in
            openDocumentURLs([URL(fileURLWithPath: filename)])
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        workspace?.rootURLDidChange = nil
        workspaceInstances.unregister()
        if let closeDocumentShortcutMonitor {
            NSEvent.removeMonitor(closeDocumentShortcutMonitor)
            self.closeDocumentShortcutMonitor = nil
        }
        if isObservingOpenDocumentRequests {
            DistributedNotificationCenter.default().removeObserver(
                self,
                name: Self.openDocumentRequestNotification,
                object: Self.notificationObject
            )
        }
    }

    private func installCloseDocumentShortcutMonitor() {
        guard closeDocumentShortcutMonitor == nil else {
            return
        }
        closeDocumentShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleCloseDocumentShortcut(event) ?? event
        }
    }

    private func handleCloseDocumentShortcut(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == .command,
              !event.isARepeat,
              event.charactersIgnoringModifiers?.lowercased() == "w",
              let workspace,
              workspace.selectedTab != nil
        else {
            return event
        }
        workspace.closeSelectedTab()
        return nil
    }

    @MainActor
    @discardableResult
    private func openDocumentURLs(
        _ urls: [URL],
        opensWorkspaceIfNeeded: Bool = false,
        prefersExistingInstances: Bool = true
    ) -> Bool {
        guard let workspace else {
            pendingDocumentURLs.append(contentsOf: urls)
            return false
        }

        let didOpenInCurrentInstance = urls.reduce(false) { partialResult, url in
            routeDocumentURL(
                url,
                to: workspace,
                opensWorkspaceIfNeeded: opensWorkspaceIfNeeded,
                prefersExistingInstances: prefersExistingInstances
            ) || partialResult
        }
        if didOpenInCurrentInstance {
            activateDocumentWindow()
        }
        return didOpenInCurrentInstance
    }

    @MainActor
    private func openPendingDocumentURLs() -> Bool? {
        guard !pendingDocumentURLs.isEmpty else {
            return nil
        }
        let urls = pendingDocumentURLs
        pendingDocumentURLs.removeAll()
        let didOpenInCurrentInstance = openDocumentURLs(urls, opensWorkspaceIfNeeded: true)
        if !didOpenInCurrentInstance {
            NSApp.terminate(nil)
        }
        return didOpenInCurrentInstance
    }

    @MainActor
    private func routeDocumentURL(
        _ url: URL,
        to workspace: WorkspaceModel,
        opensWorkspaceIfNeeded: Bool,
        prefersExistingInstances: Bool
    ) -> Bool {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        if prefersExistingInstances,
           let instance = workspaceInstances.bestInstance(containing: canonical),
           instance.processIdentifier != WorkspaceInstanceRegistry.currentProcessIdentifier {
            requestInstance(instance, toOpen: canonical)
            return false
        }

        let result = workspace.openExternalDocumentURL(
            canonical,
            opensWorkspaceIfNeeded: opensWorkspaceIfNeeded || workspace.rootURL == nil
        )
        switch result {
        case .handled:
            return true
        case .needsWorkspace(let documentURL):
            openDocumentURLsInNewInstance([documentURL])
            return false
        }
    }

    private func observeOpenDocumentRequests() {
        guard !isObservingOpenDocumentRequests else {
            return
        }
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleOpenDocumentRequestNotification(_:)),
            name: Self.openDocumentRequestNotification,
            object: Self.notificationObject,
            suspensionBehavior: .deliverImmediately
        )
        isObservingOpenDocumentRequests = true
    }

    @objc
    private func handleOpenDocumentRequestNotification(_ notification: Notification) {
        let targetProcessIdentifier = notification.userInfo?["targetProcessIdentifier"] as? Int
        let path = notification.userInfo?["path"] as? String
        handleOpenDocumentRequest(targetProcessIdentifier: targetProcessIdentifier, path: path)
    }

    @MainActor
    private func handleOpenDocumentRequest(targetProcessIdentifier: Int?, path: String?) {
        guard targetProcessIdentifier == Int(WorkspaceInstanceRegistry.currentProcessIdentifier),
              let path
        else {
            return
        }
        openDocumentURLs([URL(fileURLWithPath: path)], prefersExistingInstances: false)
    }

    private func requestInstance(_ instance: WorkspaceInstanceRegistry.Instance, toOpen url: URL) {
        DistributedNotificationCenter.default().postNotificationName(
            Self.openDocumentRequestNotification,
            object: Self.notificationObject,
            userInfo: [
                "targetProcessIdentifier": Int(instance.processIdentifier),
                "path": url.path
            ],
            deliverImmediately: true
        )
    }

    @MainActor
    private func openDocumentURLsInNewInstance(_ urls: [URL]) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.open(
            urls,
            withApplicationAt: Bundle.main.bundleURL,
            configuration: configuration
        )
    }

    @MainActor
    private func restoreVisibleWindowPlacement() {
        DispatchQueue.main.async {
            for window in NSApp.windows where window.isVisible {
                WindowPlacement.ensureVisible(window)
            }
        }
    }

    @MainActor
    private func activateDocumentWindow() {
        guard let window = NSApp.windows.first(where: { $0.canBecomeKey }) else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let shouldOrderFront = !window.isVisible || window.isMiniaturized || NSApp.isHidden
        WindowPlacement.ensureVisible(window)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        if NSApp.isHidden {
            NSApp.unhide(nil)
        }
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        if shouldOrderFront {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

private final class WorkspaceInstanceRegistry {
    struct Instance: Equatable {
        var processIdentifier: pid_t
        var rootURL: URL
    }

    static let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier

    private struct StoredInstance: Codable, Equatable {
        var processIdentifier: pid_t
        var rootPath: String
        var updatedAt: Date
    }

    private let defaults: UserDefaults
    private let key = "runningWorkspaceInstances"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func update(rootURL: URL?) {
        var instances = loadActiveInstances()
        instances.removeAll { $0.processIdentifier == Self.currentProcessIdentifier }

        if let rootURL {
            instances.append(
                StoredInstance(
                    processIdentifier: Self.currentProcessIdentifier,
                    rootPath: canonicalURL(rootURL).path,
                    updatedAt: Date()
                )
            )
        }

        save(instances)
    }

    func unregister() {
        var instances = loadActiveInstances()
        instances.removeAll { $0.processIdentifier == Self.currentProcessIdentifier }
        save(instances)
    }

    func bestInstance(containing url: URL) -> Instance? {
        let path = canonicalURL(url).path
        return loadActiveInstances()
            .filter { contains(path: path, inRootPath: $0.rootPath) }
            .max { lhs, rhs in lhs.rootPath.count < rhs.rootPath.count }
            .map {
                Instance(
                    processIdentifier: $0.processIdentifier,
                    rootURL: URL(fileURLWithPath: $0.rootPath, isDirectory: true)
                )
            }
    }

    private func loadActiveInstances() -> [StoredInstance] {
        defaults.synchronize()
        let instances = loadInstances()
        let active = instances.filter { instance in
            if instance.processIdentifier == Self.currentProcessIdentifier {
                return true
            }
            guard let runningApplication = NSRunningApplication(processIdentifier: instance.processIdentifier) else {
                return false
            }
            return runningApplication.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        if active != instances {
            save(active)
        }
        return active
    }

    private func loadInstances() -> [StoredInstance] {
        guard let data = defaults.data(forKey: key),
              let instances = try? JSONDecoder().decode([StoredInstance].self, from: data)
        else {
            return []
        }
        return instances
    }

    private func save(_ instances: [StoredInstance]) {
        guard let data = try? JSONEncoder().encode(instances) else {
            return
        }
        defaults.set(data, forKey: key)
        defaults.synchronize()
    }

    private func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func contains(path: String, inRootPath rootPath: String) -> Bool {
        path == rootPath || path.hasPrefix(rootPath + "/")
    }
}

private enum WindowPlacement {
    @MainActor
    static func ensureVisible(_ window: NSWindow) {
        guard !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) else {
            return
        }
        guard let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else {
            return
        }

        var frame = window.frame
        frame.size.width = min(max(frame.width, 980), visibleFrame.width)
        frame.size.height = min(max(frame.height, 640), visibleFrame.height)
        frame.origin.x = visibleFrame.midX - frame.width / 2
        frame.origin.y = visibleFrame.midY - frame.height / 2
        window.setFrame(frame, display: true)
    }
}
