import SwiftUI
import WebKit

struct RendererWebView: NSViewRepresentable {
    @ObservedObject var workspace: WorkspaceModel
    let tabID: OpenTab.ID
    let payload: RendererPayload?
    let isVisible: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(workspace: workspace)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let schemeHandler = WorkspaceAssetSchemeHandler(workspace: workspace)
        context.coordinator.schemeHandler = schemeHandler
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: AssetURLBuilder.scheme)
        configuration.userContentController.add(context.coordinator, name: RendererBridgeContract.Message.rendererReady)
        configuration.userContentController.add(context.coordinator, name: RendererBridgeContract.Message.renderComplete)
        configuration.userContentController.add(context.coordinator, name: RendererBridgeContract.Message.openLink)
        configuration.userContentController.add(context.coordinator, name: RendererBridgeContract.Message.renderError)
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.startupErrorScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        Self.installNetworkBlocker(on: configuration)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.alphaValue = Coordinator.renderingAlpha
        context.coordinator.webView = webView
        context.coordinator.update(tabID: tabID, payload: payload, isVisible: isVisible)

        if let rendererURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Renderer") {
            let directory = rendererURL.deletingLastPathComponent()
            webView.loadFileURL(rendererURL, allowingReadAccessTo: directory)
        } else {
            workspace.setRendererStatus("Renderer bundle is missing.", for: tabID)
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.workspace = workspace
        context.coordinator.schemeHandler?.update(resolver: workspace.resolver)
        context.coordinator.update(tabID: tabID, payload: payload, isVisible: isVisible)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.invalidate()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: RendererBridgeContract.Message.rendererReady)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: RendererBridgeContract.Message.renderComplete)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: RendererBridgeContract.Message.openLink)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: RendererBridgeContract.Message.renderError)
        coordinator.webView = nil
    }

}
