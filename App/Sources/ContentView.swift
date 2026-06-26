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

private struct GlassPanelModifier: ViewModifier {
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

private extension View {
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

private struct ToolbarView: View {
    @EnvironmentObject private var workspace: WorkspaceModel

    var body: some View {
        HStack(spacing: 8) {
            ToolbarIconButton(
                title: workspace.settings.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar",
                systemImage: "sidebar.left"
            ) {
                workspace.toggleSidebar()
            }

            ToolbarIconButton(title: "Open Folder", systemImage: "folder") {
                workspace.openDirectoryPanel()
            }

            ToolbarIconButton(title: "Open File", systemImage: "doc") {
                workspace.openFilePanel()
            }

            ToolbarIconButton(
                title: "Refresh",
                systemImage: "arrow.clockwise",
                isDisabled: workspace.selectedTab == nil
            ) {
                workspace.refreshSelectedTab()
            }

            WorkspacePathView()
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .frame(height: 46)
        .glassPanel(material: .bar)
    }
}

private struct ToolbarIconButton: View {
    let title: String
    let systemImage: String
    var isDisabled = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 30, height: 30)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.42 : 1)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHovered && !isDisabled ? Color.primary.opacity(0.08) : Color.clear)
        )
        .onHover { isHovered = $0 }
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct WorkspacePathView: View {
    @EnvironmentObject private var workspace: WorkspaceModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: workspace.rootURL == nil ? "doc.text.magnifyingglass" : "folder")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.leading, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    private var title: String {
        guard let rootURL = workspace.rootURL else {
            return "No Workspace"
        }
        return rootURL.lastPathComponent.isEmpty ? rootURL.path : rootURL.lastPathComponent
    }

    private var subtitle: String {
        workspace.rootURL?.path ?? "Open a folder or Markdown file"
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var workspace: WorkspaceModel

    var body: some View {
        VStack(spacing: 0) {
            if let rootURL = workspace.rootURL {
                SidebarHeaderView(rootURL: rootURL)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        DirectoryNodeView(
                            item: FileItem(
                                id: rootURL,
                                url: rootURL,
                                name: rootURL.lastPathComponent.isEmpty ? rootURL.path : rootURL.lastPathComponent,
                                kind: .directory,
                                size: 0
                            ),
                            level: 0,
                            initialChildren: workspace.rootChildren
                        )
                        .id(rootURL)
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
            } else {
                EmptySidebarView()
            }
        }
        .background(.thinMaterial)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.4))
                .frame(width: 1)
        }
    }
}

private struct SidebarHeaderView: View {
    let rootURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Workspace")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(rootURL.lastPathComponent.isEmpty ? rootURL.path : rootURL.lastPathComponent)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}

private struct EmptySidebarView: View {
    @EnvironmentObject private var workspace: WorkspaceModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)
            Text("No workspace")
                .font(.system(size: 15, weight: .semibold))
            Button("Open Folder") {
                workspace.openDirectoryPanel()
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct DirectoryNodeView: View {
    @EnvironmentObject private var workspace: WorkspaceModel
    let item: FileItem
    let level: Int
    let initialChildren: [FileItem]?
    @State private var children: [FileItem]?
    @State private var isLoading = false

    init(item: FileItem, level: Int, initialChildren: [FileItem]? = nil) {
        self.item = item
        self.level = level
        self.initialChildren = initialChildren
        _children = State(initialValue: initialChildren)
    }

    private var isExpanded: Bool {
        workspace.isDirectoryExpanded(item.url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                toggle()
            } label: {
                FileRowView(item: item, level: level, isExpanded: isExpanded)
            }
            .buttonStyle(.plain)

            if isExpanded {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.65)
                        .padding(.leading, CGFloat(level + 1) * 18 + 10)
                        .frame(height: 26)
                } else if let children {
                    ForEach(children) { child in
                        if child.isDirectory {
                            DirectoryNodeView(item: child, level: level + 1)
                        } else {
                            Button {
                                workspace.openFile(child.url)
                            } label: {
                                FileRowView(item: child, level: level + 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .task(id: isExpanded) {
            guard isExpanded else {
                return
            }
            await loadChildrenIfNeeded()
        }
        .onChange(of: item.url) {
            children = initialChildren
        }
        .onChange(of: initialChildren) {
            guard level == 0 else {
                return
            }
            children = initialChildren
        }
    }

    private func toggle() {
        let shouldLoadChildren = !isExpanded && children == nil
        workspace.toggleDirectoryExpansion(item.url)
        guard shouldLoadChildren else {
            return
        }
        Task {
            await loadChildrenIfNeeded()
        }
    }

    private func loadChildrenIfNeeded() async {
        guard children == nil, !isLoading else {
            return
        }
        isLoading = true
        let loaded = await workspace.children(of: item.url)
        children = loaded
        isLoading = false
    }
}

private struct FileRowView: View {
    @EnvironmentObject private var workspace: WorkspaceModel
    let item: FileItem
    let level: Int
    var isExpanded: Bool = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: disclosureIcon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 10)
                .opacity(item.isDirectory ? 1 : 0)
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 16)
            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .padding(.leading, CGFloat(level) * 16 + 8)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(rowBackground)
        }
        .onHover { isHovered = $0 }
    }

    private var isSelected: Bool {
        workspace.selectedTab?.url == item.url
    }

    private var icon: String {
        switch item.kind {
        case .directory:
            return isExpanded ? "folder.fill" : "folder"
        case .markdown:
            return item.name.lowercased() == "readme.md" ? "star.fill" : "doc.richtext"
        case .image:
            return "photo"
        case .text:
            return "curlybraces"
        case .unsupported:
            return "doc"
        }
    }

    private var disclosureIcon: String {
        isExpanded ? "chevron.down" : "chevron.right"
    }

    private var iconColor: Color {
        switch item.kind {
        case .directory:
            return .blue
        case .markdown:
            return .accentColor
        case .image:
            return .green
        case .text:
            return .purple
        case .unsupported:
            return .secondary
        }
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.18)
        }
        if isHovered {
            return Color.primary.opacity(0.06)
        }
        return .clear
    }
}

private struct TabBarView: View {
    @EnvironmentObject private var workspace: WorkspaceModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(workspace.tabs) { tab in
                    TabChipView(tab: tab, isSelected: tab.id == workspace.selectedTabID)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .frame(height: 46)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.35))
                .frame(height: 1)
        }
    }
}

private struct TabChipView: View {
    @EnvironmentObject private var workspace: WorkspaceModel
    let tab: OpenTab
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 7) {
            Button {
                workspace.selectTab(tab.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    Text(tab.title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 170)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select \(tab.title)")

            Button {
                workspace.closeTab(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 16, height: 16)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(isSelected || isHovered ? 1 : 0.65)
            .help("Close")
            .accessibilityLabel("Close \(tab.title)")
        }
        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
        .padding(.leading, 10)
        .padding(.trailing, 7)
        .frame(height: 30)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(backgroundColor)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.24) : Color.clear, lineWidth: 1)
        }
        .onHover { isHovered = $0 }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color(nsColor: .textBackgroundColor).opacity(0.9)
        }
        if isHovered {
            return Color.primary.opacity(0.06)
        }
        return Color.clear
    }
}

private struct PreviewContainerView: View {
    @EnvironmentObject private var workspace: WorkspaceModel

    var body: some View {
        ZStack {
            if let selectedTab = workspace.selectedTab {
                if selectedTab.payload != nil {
                    RenderingPlaceholderView(title: selectedTab.title)
                }

                ForEach(workspace.tabs) { tab in
                    if let payload = tab.payload {
                        RendererWebView(
                            workspace: workspace,
                            tabID: tab.id,
                            payload: payload
                        )
                        .opacity(tab.id == workspace.selectedTabID ? 1 : 0)
                        .allowsHitTesting(tab.id == workspace.selectedTabID)
                        .accessibilityHidden(tab.id != workspace.selectedTabID)
                    }
                }

                if selectedTab.payload == nil {
                    PreviewErrorView(message: selectedTab.errorMessage)
                }
            } else {
                EmptyPreviewView()
            }
            if let statusMessage = workspace.statusMessage, workspace.selectedTab != nil {
                VStack {
                    Spacer()
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassPanel(material: .regularMaterial, cornerRadius: 8)
                        .padding(12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct PreviewErrorView: View {
    let message: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.secondary)
            Text(message ?? "Unable to preview this file.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct EmptyPreviewView: View {
    @EnvironmentObject private var workspace: WorkspaceModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text("Open Document")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Choose a Markdown file or workspace folder to start previewing.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 8) {
                Button {
                    workspace.openFilePanel()
                } label: {
                    Label("Open Document", systemImage: "doc")
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Button {
                    workspace.openDirectoryPanel()
                } label: {
                    Label("Open Folder", systemImage: "folder")
                }
                .controlSize(.large)
            }
            .padding(.top, 4)

            if let statusMessage = workspace.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .padding(28)
        .glassPanel(material: .thinMaterial, cornerRadius: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }
}

private struct RenderingPlaceholderView: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            VStack(spacing: 4) {
                Text("Rendering document")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 280)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rendering document")
    }
}
