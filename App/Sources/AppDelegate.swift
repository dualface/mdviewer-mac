import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var workspace: WorkspaceModel?
    private var pendingDocumentURLs: [URL] = []
    private var closeDocumentShortcutMonitor: Any?

    @MainActor
    func attach(_ workspace: WorkspaceModel) {
        self.workspace = workspace
        installCloseDocumentShortcutMonitor()
        restoreVisibleWindowPlacement()
        _ = openPendingDocumentURLs()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            openDocumentURLs(urls, opensWorkspaceIfNeeded: true)
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        Task { @MainActor in
            openDocumentURLs([URL(fileURLWithPath: filename)], opensWorkspaceIfNeeded: true)
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let closeDocumentShortcutMonitor {
            NSEvent.removeMonitor(closeDocumentShortcutMonitor)
            self.closeDocumentShortcutMonitor = nil
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
        opensWorkspaceIfNeeded: Bool = false
    ) -> Bool {
        guard let workspace else {
            pendingDocumentURLs.append(contentsOf: urls)
            return false
        }

        let didOpenInCurrentInstance = urls.reduce(false) { partialResult, url in
            routeDocumentURL(
                url,
                to: workspace,
                opensWorkspaceIfNeeded: opensWorkspaceIfNeeded
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
        opensWorkspaceIfNeeded: Bool
    ) -> Bool {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        let result = workspace.openExternalDocumentURL(
            canonical,
            opensWorkspaceIfNeeded: opensWorkspaceIfNeeded || workspace.rootURL == nil
        )
        switch result {
        case .handled:
            return true
        case .needsWorkspace:
            return false
        }
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
