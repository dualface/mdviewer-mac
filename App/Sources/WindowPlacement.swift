import AppKit

enum WindowPlacement {
    @MainActor
    static func ensureVisible(_ window: NSWindow) {
        guard !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) else {
            return
        }
        guard let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else {
            return
        }

        var frame = window.frame
        frame.size.width = min(max(frame.width, 980), visibleFrame.width)
        frame.size.height = min(max(frame.height, 640), visibleFrame.height)
        frame.origin.x = visibleFrame.midX - frame.width / 2
        frame.origin.y = visibleFrame.midY - frame.height / 2
        window.setFrame(frame, display: true)
    }
}
