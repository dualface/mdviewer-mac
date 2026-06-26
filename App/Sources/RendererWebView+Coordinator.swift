import SwiftUI
import WebKit

extension RendererWebView {
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
        weak var webView: WKWebView?
        var schemeHandler: WorkspaceAssetSchemeHandler?
        var workspace: WorkspaceModel
        var latestTabID: OpenTab.ID?
        var latestPayload: RendererPayload?
        var isReady = false
        var isVisible = false
        var lastRenderedJSON: String?
        var lastCompletedRenderID: Int?
        var renderID = 0
        var currentRenderFailed = false
        var hasDisplayedRender = false
        var lastFocusedSelectedTabID: OpenTab.ID?
        var isActive = true

        init(workspace: WorkspaceModel) {
            self.workspace = workspace
        }

        func update(tabID: OpenTab.ID, payload: RendererPayload?, isVisible: Bool) {
            let didChangeTab = latestTabID != tabID
            let didChangePayload = latestPayload != payload
            let didChangeVisibility = self.isVisible != isVisible
            if didChangeTab {
                cancelCurrentRender()
                renderID += 1
                currentRenderFailed = false
                lastRenderedJSON = nil
            }

            latestTabID = tabID
            latestPayload = payload
            self.isVisible = isVisible

            if didChangeVisibility {
                setRendererPaused(!isVisible)
                if !isVisible {
                    cancelCurrentRender()
                }
            }

            if isVisible, didChangeTab || didChangePayload || didChangeVisibility {
                renderIfReady()
            }
            focusWebViewIfSelected()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard isActive else {
                return
            }
            switch message.name {
            case RendererBridgeContract.Message.rendererReady:
                markRendererReady()
            case RendererBridgeContract.Message.renderComplete:
                guard let body = message.body as? [String: Any],
                      let completedRenderID = intValue(from: body[RendererBridgeContract.PayloadKey.renderID])
                else {
                    return
                }
                completeRenderIfCurrent(completedRenderID)
            case RendererBridgeContract.Message.openLink:
                guard let body = message.body as? [String: Any],
                      let href = body[RendererBridgeContract.PayloadKey.href] as? String,
                      let filePath = body[RendererBridgeContract.PayloadKey.filePath] as? String
                else {
                    return
                }
                Task { @MainActor in
                    guard self.isActive else {
                        return
                    }
                    self.workspace.openLink(href, from: filePath)
                }
            case RendererBridgeContract.Message.renderError:
                handleRenderError(message.body)
            default:
                break
            }
        }

        @MainActor
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(Self.isAllowedNavigationURL(url) ? .allow : .cancel)
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
            updateStatusMessage("Renderer load failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard isActive else {
                return
            }
            hasDisplayedRender = true
            webView.alphaValue = 1
            updateStatusMessage("Renderer load failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
            guard isActive else {
                return
            }
            hasDisplayedRender = true
            webView.alphaValue = 1
            updateStatusMessage(message)
        }

        func renderIfReady(force: Bool = false) {
            guard isActive,
                  isVisible,
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
                window.webkit?.messageHandlers?.\(RendererBridgeContract.Message.renderError)?.postMessage({
                  \(RendererBridgeContract.PayloadKey.message): error?.message || String(error),
                  \(RendererBridgeContract.PayloadKey.renderID): \(startedRenderID)
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
                        self.updateStatusMessage("Render failed: \(error.localizedDescription)")
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
            lastFocusedSelectedTabID = nil
        }

        func cancelCurrentRender() {
            guard renderID > 0 else {
                return
            }
            let cancelledRenderID = renderID
            webView?.evaluateJavaScript("window.MDViewer?.cancelRender?.(\(cancelledRenderID));")
        }

        static let renderingAlpha: CGFloat = 0.001
        static let rendererReadyCheckInterval: TimeInterval = 0.05
        static let maxRendererReadyChecks = 40
        static let renderCompletionCheckInterval: TimeInterval = 0.25
        static let maxRenderCompletionChecks = 1200
        static let focusRetryInterval: TimeInterval = 0.05
        static let maxFocusAttempts = 20
    }
}
