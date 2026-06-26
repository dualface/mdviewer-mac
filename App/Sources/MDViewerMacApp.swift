import SwiftUI

@main
struct MDViewerMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var workspace = WorkspaceModel()

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
                Button("Open File...") {
                    workspace.openFilePanel()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Open Folder...") {
                    workspace.openDirectoryPanel()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            CommandMenu("Preview") {
                Button("Refresh") {
                    workspace.refreshSelectedTab()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }

            CommandMenu("Tabs") {
                Button("Close Other Files") {
                    workspace.closeOtherTabs()
                }
                .keyboardShortcut("w", modifiers: [.command, .option])
                .disabled(workspace.selectedTab == nil || workspace.tabs.count <= 1)

                Button("Close All Files") {
                    workspace.closeAllTabs()
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(workspace.tabs.isEmpty)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var workspace: WorkspaceModel?
    private var pendingDocumentURLs: [URL] = []

    @MainActor
    func attach(_ workspace: WorkspaceModel) {
        self.workspace = workspace
        restoreVisibleWindowPlacement()
        openPendingDocumentURLs()
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

    @MainActor
    private func openDocumentURLs(_ urls: [URL]) {
        guard let workspace else {
            pendingDocumentURLs.append(contentsOf: urls)
            return
        }
        urls.forEach { workspace.openExternalDocumentURL($0) }
        activateDocumentWindow()
    }

    @MainActor
    private func openPendingDocumentURLs() {
        guard !pendingDocumentURLs.isEmpty else {
            return
        }
        let urls = pendingDocumentURLs
        pendingDocumentURLs.removeAll()
        openDocumentURLs(urls)
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
        NSApp.activate(ignoringOtherApps: true)
        guard let window = NSApp.windows.first(where: { $0.canBecomeKey }) else {
            return
        }
        WindowPlacement.ensureVisible(window)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
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
