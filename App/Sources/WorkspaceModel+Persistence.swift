import Foundation

extension WorkspaceModel {
    func persistWorkspace() {
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

    func restorePersistedWorkspace() {
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

    func stopAccessingCurrentWorkspace() {
        for url in securityScopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        securityScopedURLs.removeAll()
    }

    func startAccessing(_ url: URL) {
        let canonical = canonicalURL(url)
        guard !securityScopedURLs.contains(canonical) else {
            return
        }
        if canonical.startAccessingSecurityScopedResource() {
            securityScopedURLs.append(canonical)
        }
    }
}
