import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var workspace: WorkspaceModel
    @Environment(\.colorScheme) private var effectiveColorScheme
    @State private var liveSidebarWidth: Double?

    private var sidebarWidth: Double {
        liveSidebarWidth ?? workspace.settings.sidebarWidth
    }

    var body: some View {
        VStack(spacing: 0) {
            if workspace.settings.isToolbarVisible {
                ToolbarView()
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
            }
            HStack(spacing: 0) {
                if workspace.settings.isSidebarVisible {
                    SidebarView()
                        .frame(width: sidebarWidth)
                    SidebarResizeHandle(width: $liveSidebarWidth)
                }
                VStack(spacing: 0) {
                    if workspace.tabs.count > 1 {
                        TabBarView()
                    }
                    PreviewContainerView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppBackgroundView())
        .overlay {
            WindowAppearanceBridge(theme: workspace.settings.theme)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
        .preferredColorScheme(colorScheme)
        .onAppear {
            workspace.systemAppearanceDidChange()
        }
        .onChange(of: effectiveColorScheme) {
            workspace.systemAppearanceDidChange()
        }
        .onChange(of: workspace.settings.theme) {
            workspace.systemAppearanceDidChange()
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private var colorScheme: ColorScheme? {
        switch workspace.settings.theme {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers where provider.hasItemConformingToTypeIdentifier("public.file-url") {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let dropped = item as? URL {
                    url = dropped
                } else {
                    url = nil
                }
                if let url {
                    Task { @MainActor in
                        workspace.openDocumentURL(url)
                    }
                }
            }
            return true
        }
        return false
    }
}

private struct WindowAppearanceBridge: NSViewRepresentable {
    let theme: AppTheme

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            applyAppearance(to: view)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            applyAppearance(to: view)
        }
    }

    private func applyAppearance(to view: NSView) {
        view.window?.appearance = appearance
    }

    private var appearance: NSAppearance? {
        switch theme {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }
}

private struct AppBackgroundView: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()
    }
}

struct GlassPanelModifier: ViewModifier {
    var material: Material = .regularMaterial
    var cornerRadius: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .background(material, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: 6)
    }
}

extension View {
    func glassPanel(material: Material = .regularMaterial, cornerRadius: CGFloat = 8) -> some View {
        modifier(GlassPanelModifier(material: material, cornerRadius: cornerRadius))
    }
}

private struct SidebarResizeHandle: View {
    @Binding var width: Double?

    var body: some View {
        AppKitSidebarResizeHandle(width: $width)
            .frame(width: 18)
    }
}

private struct AppKitSidebarResizeHandle: NSViewRepresentable {
    @EnvironmentObject private var workspace: WorkspaceModel
    @Binding var width: Double?

    func makeNSView(context: Context) -> SidebarResizeHandleView {
        SidebarResizeHandleView()
    }

    func updateNSView(_ view: SidebarResizeHandleView, context: Context) {
        view.baseWidth = workspace.settings.sidebarWidth
        view.onResize = { newWidth in
            width = newWidth
        }
        view.onCommit = { newWidth in
            var settings = workspace.settings
            settings.sidebarWidth = newWidth
            workspace.settings = settings
            width = nil
        }
        view.needsDisplay = true
    }
}

private final class SidebarResizeHandleView: NSView {
    var baseWidth = 260.0
    var onResize: ((Double) -> Void)?
    var onCommit: ((Double) -> Void)?

    private let minWidth = 180.0
    private let maxWidth = 580.0
    private var dragStartX: CGFloat?
    private var dragStartWidth: Double?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragStartX = event.locationInWindow.x
        dragStartWidth = baseWidth
        NSCursor.resizeLeftRight.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartX, let dragStartWidth else {
            return
        }
        let newWidth = resizedWidth(startX: dragStartX, startWidth: dragStartWidth, event: event)
        onResize?(newWidth)
        NSCursor.resizeLeftRight.set()
    }

    override func mouseUp(with event: NSEvent) {
        guard let dragStartX, let dragStartWidth else {
            return
        }
        let newWidth = resizedWidth(startX: dragStartX, startWidth: dragStartWidth, event: event)
        self.dragStartX = nil
        self.dragStartWidth = nil
        onCommit?(newWidth)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.withAlphaComponent(0.55).setFill()
        NSRect(x: floor(bounds.midX), y: 0, width: 1, height: bounds.height).fill()
    }

    private func resizedWidth(startX: CGFloat, startWidth: Double, event: NSEvent) -> Double {
        let delta = event.locationInWindow.x - startX
        let proposedWidth = startWidth + Double(delta)
        return min(maxWidth, max(minWidth, proposedWidth.rounded()))
    }
}
