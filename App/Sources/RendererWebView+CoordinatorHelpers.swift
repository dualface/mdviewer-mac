import Foundation
import WebKit

extension RendererWebView.Coordinator {
    func setRendererPaused(_ isPaused: Bool) {
        webView?.evaluateJavaScript("window.MDViewer?.setPaused?.(\(isPaused ? "true" : "false"));")
    }

    func handleRenderError(_ body: Any) {
        guard isActive else {
            return
        }
        let text: String
        if let message = body as? String {
            text = message
        } else if let dictionary = body as? [String: Any],
                  let message = dictionary[RendererBridgeContract.PayloadKey.message] as? String {
            if let failedRenderID = intValue(from: dictionary[RendererBridgeContract.PayloadKey.renderID]),
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
            self.updateStatusMessage(text)
        }
    }

    func intValue(from value: Any?) -> Int? {
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

    func completeRenderIfCurrent(_ completedRenderID: Int) {
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
                self.updateStatusMessage(nil)
            }
        }
    }

    func scheduleRenderCompletionCheck(for scheduledRenderID: Int, attempt: Int = 0) {
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

    func markRendererReady() {
        guard isActive, !isReady else {
            return
        }
        isReady = true
        setRendererPaused(!isVisible)
        renderIfReady(force: true)
    }

    func checkRendererReady(attempt: Int = 0) {
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
                    self.updateStatusMessage("Renderer script did not initialize.")
                }
            }
        }
    }

    func updateStatusMessage(_ message: String?) {
        guard let latestTabID else {
            return
        }
        workspace.setRendererStatus(message, for: latestTabID)
    }

    func focusWebViewIfSelected(attempt: Int = 0) {
        guard isActive,
              isVisible,
              let latestTabID,
              latestTabID == workspace.selectedTabID
        else {
            lastFocusedSelectedTabID = nil
            return
        }
        guard lastFocusedSelectedTabID != latestTabID else {
            return
        }
        lastFocusedSelectedTabID = latestTabID
        DispatchQueue.main.async { [weak self] in
            self?.focusSelectedWebView(attempt: attempt)
        }
    }

    func focusSelectedWebView(attempt: Int) {
        guard isActive,
              isVisible,
              let latestTabID,
              latestTabID == workspace.selectedTabID,
              let webView
        else {
            return
        }
        guard let window = webView.window else {
            guard attempt < Self.maxFocusAttempts else {
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.focusRetryInterval) { [weak self] in
                self?.focusSelectedWebView(attempt: attempt + 1)
            }
            return
        }
        if window.firstResponder !== webView {
            window.makeFirstResponder(webView)
        }
        webView.evaluateJavaScript("window.focus();")
    }

    static func isAllowedNavigationURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }
        switch scheme {
        case "file", AssetURLBuilder.scheme, "about", "data", "blob":
            return true
        default:
            return false
        }
    }
}
