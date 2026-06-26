import AppKit
import UniformTypeIdentifiers

extension WorkspaceModel {
    func openDirectoryPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        if panel.runModal() == .OK, let url = panel.url {
            openDirectoryURL(url)
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
}
