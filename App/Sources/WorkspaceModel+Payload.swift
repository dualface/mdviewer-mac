import Foundation

extension WorkspaceModel {
    func refresh(tabID: OpenTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let rootURL,
              let resolver
        else {
            return
        }

        cancelPayloadTask(for: tabID)

        let requestID = UUID()
        let url = tabs[index].url
        let settings = settings
        let theme = resolvedThemeName()
        tabs[index].isLoading = true
        tabs[index].errorMessage = nil
        tabs[index].statusMessage = nil
        tabs[index].payloadRequestID = requestID

        payloadTasks[tabID] = Task { @MainActor [weak self] in
            do {
                let payload = try await FileContentLoader.makePayload(
                    for: url,
                    rootURL: rootURL,
                    resolver: resolver,
                    settings: settings,
                    theme: theme
                )
                guard !Task.isCancelled else {
                    return
                }
                self?.completePayloadRefresh(tabID: tabID, requestID: requestID, result: .success(payload))
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                self?.completePayloadRefresh(tabID: tabID, requestID: requestID, result: .failure(error))
            }
        }
    }

    func payloadForSelectedTab() -> RendererPayload? {
        selectedTab?.payload
    }

    func setRendererStatus(_ message: String?, for tabID: OpenTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else {
            return
        }
        tabs[index].statusMessage = message
    }

    func scheduleRefreshAfterSelection(tabID: OpenTab.ID) {
        pendingTabSelectionRefresh?.cancel()
        pendingTabSelectionRefresh = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else {
                return
            }
            self?.refresh(tabID: tabID)
        }
    }

    func updatePayloadSettings() {
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

    func completePayloadRefresh(
        tabID: OpenTab.ID,
        requestID: UUID,
        result: Result<RendererPayload, Error>
    ) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[index].payloadRequestID == requestID
        else {
            return
        }

        payloadTasks[tabID] = nil
        tabs[index].isLoading = false

        switch result {
        case .success(let payload):
            tabs[index].previewKind = payload.kind
            tabs[index].payload = payload
            tabs[index].errorMessage = nil
            tabs[index].statusMessage = nil
        case .failure(let error):
            tabs[index].payload = nil
            tabs[index].errorMessage = error.localizedDescription
            tabs[index].statusMessage = nil
        }
    }

    func cancelPayloadTask(for tabID: OpenTab.ID) {
        payloadTasks[tabID]?.cancel()
        payloadTasks[tabID] = nil
    }

    func cancelAllPayloadTasks() {
        for task in payloadTasks.values {
            task.cancel()
        }
        payloadTasks.removeAll()
    }

    func resolvedThemeName() -> String {
        switch settings.theme {
        case .light:
            return "light"
        case .dark:
            return "dark"
        case .system:
            return Self.isSystemDarkModeEnabled ? "dark" : "light"
        }
    }

    static var isSystemDarkModeEnabled: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }
}
