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
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.alphaValue = Coordinator.renderingAlpha
        context.coordinator.webView = webView

        if let rendererURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Renderer"),
           let html = try? String(contentsOf: rendererURL, encoding: .utf8) {
            let directory = rendererURL.deletingLastPathComponent()
            webView.loadHTMLString(html, baseURL: directory)
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

        init(workspace: WorkspaceModel) {
            self.workspace = workspace
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "rendererReady":
                isReady = true
                renderIfReady(force: true)
            case "renderComplete":
                guard let body = message.body as? [String: Any],
                      let completedRenderID = body["renderID"] as? Int,
                      completedRenderID == renderID
                else {
                    return
                }
                webView?.alphaValue = 1
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
            isReady = true
            renderIfReady(force: true)
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
            lastRenderedJSON = json
            renderID += 1
            webView.alphaValue = Self.renderingAlpha
            let encoded = data.base64EncodedString()
            let script = """
            (() => {
              const payload = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob('\(encoded)'), c => c.charCodeAt(0))));
              if (!window.MDViewer) {
                throw new Error('Renderer script did not initialize.');
              }
              window.MDViewer.render(payload, \(renderID));
            })();
            """
            webView.evaluateJavaScript(script) { _, error in
                if let error {
                    webView.alphaValue = 1
                    Task { @MainActor in
                        self.workspace.statusMessage = "Render failed: \(error.localizedDescription)"
                    }
                }
            }
        }

        static let renderingAlpha: CGFloat = 0.001
    }
}
