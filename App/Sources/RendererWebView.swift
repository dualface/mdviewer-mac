import SwiftUI
import WebKit

struct RendererWebView: NSViewRepresentable {
    @ObservedObject var workspace: WorkspaceModel
    let tabID: OpenTab.ID
    let payload: RendererPayload?

    func makeCoordinator() -> Coordinator {
        Coordinator(workspace: workspace)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let schemeHandler = WorkspaceAssetSchemeHandler(workspace: workspace)
        context.coordinator.schemeHandler = schemeHandler
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: AssetURLBuilder.scheme)
        configuration.userContentController.add(context.coordinator, name: "rendererReady")
        configuration.userContentController.add(context.coordinator, name: "renderComplete")
        configuration.userContentController.add(context.coordinator, name: "openLink")
        configuration.userContentController.add(context.coordinator, name: "renderError")
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.startupErrorScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.alphaValue = Coordinator.renderingAlpha
        context.coordinator.webView = webView

        if let rendererURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Renderer") {
            let directory = rendererURL.deletingLastPathComponent()
            webView.loadFileURL(rendererURL, allowingReadAccessTo: directory)
        } else {
            workspace.statusMessage = "Renderer bundle is missing."
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.workspace = workspace
        context.coordinator.schemeHandler?.update(resolver: workspace.resolver)
        context.coordinator.update(tabID: tabID, payload: payload)
        context.coordinator.renderIfReady()
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.invalidate()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "rendererReady")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "renderComplete")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "openLink")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "renderError")
        coordinator.webView = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
        weak var webView: WKWebView?
        var schemeHandler: WorkspaceAssetSchemeHandler?
        var workspace: WorkspaceModel
        var latestTabID: OpenTab.ID?
        var latestPayload: RendererPayload?
        var isReady = false
        private var lastRenderedJSON: String?
        private var lastCompletedRenderID: Int?
        private var renderID = 0
        private var currentRenderFailed = false
        private var hasDisplayedRender = false
        private var isActive = true

        init(workspace: WorkspaceModel) {
            self.workspace = workspace
        }

        func update(tabID: OpenTab.ID, payload: RendererPayload?) {
            if latestTabID != tabID {
                cancelCurrentRender()
                renderID += 1
                currentRenderFailed = false
                lastRenderedJSON = nil
            }
            latestTabID = tabID
            latestPayload = payload
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard isActive else {
                return
            }
            switch message.name {
            case "rendererReady":
                markRendererReady()
            case "renderComplete":
                guard let body = message.body as? [String: Any],
                      let completedRenderID = intValue(from: body["renderID"])
                else {
                    return
                }
                completeRenderIfCurrent(completedRenderID)
            case "openLink":
                guard let body = message.body as? [String: Any],
                      let href = body["href"] as? String,
                      let filePath = body["filePath"] as? String
                else {
                    return
                }
                Task { @MainActor in
                    guard self.isActive else {
                        return
                    }
                    self.workspace.openLink(href, from: filePath)
                }
            case "renderError":
                handleRenderError(message.body)
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard isActive else {
                return
            }
            checkRendererReady()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard isActive else {
                return
            }
            hasDisplayedRender = true
            webView.alphaValue = 1
            updateStatusMessageIfSelected("Renderer load failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard isActive else {
                return
            }
            hasDisplayedRender = true
            webView.alphaValue = 1
            updateStatusMessageIfSelected("Renderer load failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
            guard isActive else {
                return
            }
            hasDisplayedRender = true
            webView.alphaValue = 1
            updateStatusMessageIfSelected(message)
        }

        func renderIfReady(force: Bool = false) {
            guard isActive,
                  isReady,
                  let webView,
                  let latestPayload,
                  let data = try? JSONEncoder().encode(latestPayload),
                  let json = String(data: data, encoding: .utf8)
            else {
                return
            }
            guard force || json != lastRenderedJSON else {
                return
            }
            let previousRenderedJSON = lastRenderedJSON
            lastRenderedJSON = json
            cancelCurrentRender()
            renderID += 1
            let startedRenderID = renderID
            currentRenderFailed = false
            lastCompletedRenderID = nil
            if !hasDisplayedRender {
                webView.alphaValue = Self.renderingAlpha
            }
            let encoded = data.base64EncodedString()
            let script = """
            (() => {
              try {
                const payload = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob('\(encoded)'), c => c.charCodeAt(0))));
                if (!window.MDViewer) {
                  throw new Error('Renderer script did not initialize.');
                }
                void window.MDViewer.render(payload, \(startedRenderID));
                return true;
              } catch (error) {
                window.webkit?.messageHandlers?.renderError?.postMessage({
                  message: error?.message || String(error),
                  renderID: \(startedRenderID)
                });
                return false;
              }
            })();
            """
            webView.evaluateJavaScript(script) { [weak self, weak webView] result, error in
                guard let self,
                      let webView,
                      self.isActive,
                      self.renderID == startedRenderID
                else {
                    return
                }
                if let error {
                    self.lastRenderedJSON = previousRenderedJSON
                    self.hasDisplayedRender = true
                    webView.alphaValue = 1
                    Task { @MainActor in
                        guard self.isActive, self.renderID == startedRenderID else {
                            return
                        }
                        self.updateStatusMessageIfSelected("Render failed: \(error.localizedDescription)")
                    }
                } else if let didStart = result as? Bool, !didStart {
                    self.lastRenderedJSON = previousRenderedJSON
                    self.hasDisplayedRender = true
                    webView.alphaValue = 1
                } else {
                    self.scheduleRenderCompletionCheck(for: startedRenderID)
                }
            }
        }

        func invalidate() {
            cancelCurrentRender()
            isActive = false
            renderID += 1
            latestPayload = nil
            lastRenderedJSON = nil
            lastCompletedRenderID = nil
        }

        func cancelCurrentRender() {
            guard renderID > 0 else {
                return
            }
            let cancelledRenderID = renderID
            webView?.evaluateJavaScript("window.MDViewer?.cancelRender?.(\(cancelledRenderID));")
        }

        private func handleRenderError(_ body: Any) {
            guard isActive else {
                return
            }
            let text: String
            if let message = body as? String {
                text = message
            } else if let dictionary = body as? [String: Any],
                      let message = dictionary["message"] as? String {
                if let failedRenderID = intValue(from: dictionary["renderID"]),
                   failedRenderID != renderID {
                    return
                }
                text = message
            } else {
                return
            }

            currentRenderFailed = true
            lastRenderedJSON = nil
            let failedRenderID = renderID
            hasDisplayedRender = true
            webView?.alphaValue = 1
            Task { @MainActor in
                guard self.isActive, self.renderID == failedRenderID else {
                    return
                }
                self.updateStatusMessageIfSelected(text)
            }
        }

        private func intValue(from value: Any?) -> Int? {
            if let integer = value as? Int {
                return integer
            }
            if let number = value as? NSNumber {
                return number.intValue
            }
            if let double = value as? Double {
                return Int(double)
            }
            return nil
        }

        private func completeRenderIfCurrent(_ completedRenderID: Int) {
            guard isActive, completedRenderID == renderID else {
                return
            }
            guard lastCompletedRenderID != completedRenderID else {
                return
            }
            lastCompletedRenderID = completedRenderID
            hasDisplayedRender = true
            webView?.alphaValue = 1
            if !currentRenderFailed {
                Task { @MainActor in
                    guard self.isActive, self.renderID == completedRenderID else {
                        return
                    }
                    self.updateStatusMessageIfSelected(nil)
                }
            }
        }

        private func scheduleRenderCompletionCheck(for scheduledRenderID: Int, attempt: Int = 0) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.renderCompletionCheckInterval) { [weak self] in
                guard let self,
                      let webView = self.webView,
                      self.isActive,
                      self.renderID == scheduledRenderID
                else {
                    return
                }

                let script = "Boolean(window.MDViewer && window.MDViewer.lastCompletedRenderID === \(scheduledRenderID))"
                webView.evaluateJavaScript(script) { [weak self] result, _ in
                    guard let self,
                          self.isActive,
                          self.renderID == scheduledRenderID
                    else {
                        return
                    }

                    if result as? Bool == true {
                        self.completeRenderIfCurrent(scheduledRenderID)
                    } else if attempt < Self.maxRenderCompletionChecks {
                        self.scheduleRenderCompletionCheck(for: scheduledRenderID, attempt: attempt + 1)
                    }
                }
            }
        }

        private func markRendererReady() {
            guard isActive, !isReady else {
                return
            }
            isReady = true
            renderIfReady(force: true)
        }

        private func checkRendererReady(attempt: Int = 0) {
            guard isActive, !isReady, let webView else {
                return
            }
            webView.evaluateJavaScript("Boolean(window.MDViewer && window.MDViewer.render)") { [weak self, weak webView] result, _ in
                guard let self,
                      let webView,
                      let currentWebView = self.webView,
                      self.isActive,
                      currentWebView === webView
                else {
                    return
                }
                if result as? Bool == true {
                    self.markRendererReady()
                } else if attempt < Self.maxRendererReadyChecks {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.rendererReadyCheckInterval) { [weak self] in
                        self?.checkRendererReady(attempt: attempt + 1)
                    }
                } else {
                    self.hasDisplayedRender = true
                    webView.alphaValue = 1
                    Task { @MainActor in
                        guard self.isActive,
                              let currentWebView = self.webView,
                              currentWebView === webView
                        else {
                            return
                        }
                        self.updateStatusMessageIfSelected("Renderer script did not initialize.")
                    }
                }
            }
        }

        private func updateStatusMessageIfSelected(_ message: String?) {
            guard latestTabID == workspace.selectedTabID else {
                return
            }
            workspace.statusMessage = message
        }

        static let renderingAlpha: CGFloat = 0.001
        static let rendererReadyCheckInterval: TimeInterval = 0.05
        static let maxRendererReadyChecks = 40
        static let renderCompletionCheckInterval: TimeInterval = 0.25
        static let maxRenderCompletionChecks = 1200
    }

    static let startupErrorScript = """
    (() => {
      const post = (message) => {
        window.webkit?.messageHandlers?.renderError?.postMessage(String(message || 'Renderer JavaScript error'));
      };
      const isRendering = () => Boolean(window.MDViewer?.isRendering);
      window.addEventListener('error', (event) => {
        if (isRendering()) {
          return;
        }
        const target = event.target;
        if (target && target !== window && target.tagName === 'SCRIPT') {
          post(`Renderer script failed to load: ${target.src || 'unknown script'}`);
          return;
        }
        if (target && target !== window) {
          return;
        }
        const location = event.filename ? ` (${event.filename}${event.lineno ? `:${event.lineno}` : ''})` : '';
        post(`${event.message || 'Renderer JavaScript error'}${location}`);
      }, true);
      window.addEventListener('unhandledrejection', (event) => {
        if (isRendering()) {
          return;
        }
        const reason = event.reason;
        post(reason?.message || String(reason || 'Unhandled renderer rejection'));
      });
    })();
    """
}
