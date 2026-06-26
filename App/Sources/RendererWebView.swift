import SwiftUI
import WebKit

struct RendererWebView: NSViewRepresentable {
    @ObservedObject var workspace: WorkspaceModel
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
        context.coordinator.latestPayload = payload
        context.coordinator.renderIfReady()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
        weak var webView: WKWebView?
        var schemeHandler: WorkspaceAssetSchemeHandler?
        var workspace: WorkspaceModel
        var latestPayload: RendererPayload?
        var isReady = false
        private var lastRenderedJSON: String?
        private var renderID = 0
        private var currentRenderFailed = false

        init(workspace: WorkspaceModel) {
            self.workspace = workspace
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "rendererReady":
                markRendererReady()
            case "renderComplete":
                guard let body = message.body as? [String: Any],
                      let completedRenderID = body["renderID"] as? Int,
                      completedRenderID == renderID
                else {
                    return
                }
                webView?.alphaValue = 1
                if !currentRenderFailed {
                    Task { @MainActor in
                        self.workspace.statusMessage = nil
                    }
                }
            case "openLink":
                guard let body = message.body as? [String: Any],
                      let href = body["href"] as? String,
                      let filePath = body["filePath"] as? String
                else {
                    return
                }
                Task { @MainActor in
                    self.workspace.openLink(href, from: filePath)
                }
            case "renderError":
                if let text = message.body as? String {
                    currentRenderFailed = true
                    lastRenderedJSON = nil
                    webView?.alphaValue = 1
                    Task { @MainActor in
                        self.workspace.statusMessage = text
                    }
                }
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            checkRendererReady()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            webView.alphaValue = 1
            workspace.statusMessage = "Renderer load failed: \(error.localizedDescription)"
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            webView.alphaValue = 1
            workspace.statusMessage = "Renderer load failed: \(error.localizedDescription)"
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
            webView.alphaValue = 1
            workspace.statusMessage = message
        }

        func renderIfReady(force: Bool = false) {
            guard isReady,
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
            renderID += 1
            currentRenderFailed = false
            webView.alphaValue = Self.renderingAlpha
            let encoded = data.base64EncodedString()
            let script = """
            (() => {
              try {
                const payload = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob('\(encoded)'), c => c.charCodeAt(0))));
                if (!window.MDViewer) {
                  throw new Error('Renderer script did not initialize.');
                }
                void window.MDViewer.render(payload, \(renderID));
                return true;
              } catch (error) {
                window.webkit?.messageHandlers?.renderError?.postMessage(error?.message || String(error));
                return false;
              }
            })();
            """
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    self.lastRenderedJSON = previousRenderedJSON
                    webView.alphaValue = 1
                    Task { @MainActor in
                        self.workspace.statusMessage = "Render failed: \(error.localizedDescription)"
                    }
                } else if let didStart = result as? Bool, !didStart {
                    self.lastRenderedJSON = previousRenderedJSON
                    webView.alphaValue = 1
                }
            }
        }

        private func markRendererReady() {
            guard !isReady else {
                return
            }
            isReady = true
            renderIfReady(force: true)
        }

        private func checkRendererReady(attempt: Int = 0) {
            guard !isReady, let webView else {
                return
            }
            webView.evaluateJavaScript("Boolean(window.MDViewer && window.MDViewer.render)") { result, _ in
                if result as? Bool == true {
                    self.markRendererReady()
                } else if attempt < Self.maxRendererReadyChecks {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.rendererReadyCheckInterval) { [weak self] in
                        self?.checkRendererReady(attempt: attempt + 1)
                    }
                } else {
                    webView.alphaValue = 1
                    Task { @MainActor in
                        self.workspace.statusMessage = "Renderer script did not initialize."
                    }
                }
            }
        }

        static let renderingAlpha: CGFloat = 0.001
        static let rendererReadyCheckInterval: TimeInterval = 0.05
        static let maxRendererReadyChecks = 40
    }

    static let startupErrorScript = """
    (() => {
      const post = (message) => {
        window.webkit?.messageHandlers?.renderError?.postMessage(String(message || 'Renderer JavaScript error'));
      };
      window.addEventListener('error', (event) => {
        const target = event.target;
        if (target && target !== window && target.tagName === 'SCRIPT') {
          post(`Renderer script failed to load: ${target.src || 'unknown script'}`);
          return;
        }
        const location = event.filename ? ` (${event.filename}${event.lineno ? `:${event.lineno}` : ''})` : '';
        post(`${event.message || 'Renderer JavaScript error'}${location}`);
      }, true);
      window.addEventListener('unhandledrejection', (event) => {
        const reason = event.reason;
        post(reason?.message || String(reason || 'Unhandled renderer rejection'));
      });
    })();
    """
}
