import Foundation

extension WorkspaceModel {
    func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    func canTrackDirectory(_ url: URL) -> Bool {
        guard let rootURL else {
            return false
        }
        return PathResolver(rootURL: rootURL).contains(canonicalURL(url))
    }

    func expandSelectedDocumentDirectory() {
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

    func updateSelectedDocumentMonitor() {
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

    func scheduleRefreshForChangedDocument(_ documentURL: URL) {
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

    func refreshChangedDocument(_ documentURL: URL) {
        guard let selectedTabID,
              let selectedTab,
              canonicalURL(selectedTab.url) == documentURL
        else {
            return
        }
        refresh(tabID: selectedTabID)
        startSelectedDocumentMonitor(for: documentURL)
    }

    func stopSelectedDocumentMonitor() {
        pendingDocumentRefresh?.cancel()
        pendingDocumentRefresh = nil
        selectedDocumentMonitor?.cancel()
        selectedDocumentMonitor = nil
        monitoredDocumentURL = nil
    }

    func startSelectedDocumentMonitor(for documentURL: URL) {
        selectedDocumentMonitor?.cancel()
        monitoredDocumentURL = documentURL
        selectedDocumentMonitor = DocumentChangeMonitor(url: documentURL) { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleRefreshForChangedDocument(documentURL)
            }
        }
    }
}
