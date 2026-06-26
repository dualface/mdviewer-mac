import WebKit

extension RendererWebView {
    static func installNetworkBlocker(on configuration: WKWebViewConfiguration) {
        let rules = """
        [
          {
            "trigger": {
              "url-filter": "^https?://.*"
            },
            "action": {
              "type": "block"
            }
          }
        ]
        """
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "MDViewerNetworkBlocker",
            encodedContentRuleList: rules
        ) { ruleList, _ in
            if let ruleList {
                configuration.userContentController.add(ruleList)
            }
        }
    }

    static let startupErrorScript = """
    (() => {
      const post = (message) => {
        window.webkit?.messageHandlers?.\(RendererBridgeContract.Message.renderError)?.postMessage(String(message || 'Renderer JavaScript error'));
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
