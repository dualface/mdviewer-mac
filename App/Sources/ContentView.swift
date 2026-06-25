import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var workspace: WorkspaceModel
    @State private var liveSidebarWidth: Double?

    private var sidebarWidth: Double {
        liveSidebarWidth ?? workspace.settings.sidebarWidth
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView()
            Divider()
            HStack(spacing: 0) {
                if workspace.settings.isSidebarVisible {
                    SidebarView()
                        .frame(width: sidebarWidth)
                        .background(Color(nsColor: .controlBackgroundColor))
                    SidebarResizeHandle(width: $liveSidebarWidth)
                }
                VStack(spacing: 0) {
                    if !workspace.tabs.isEmpty {
                        TabBarView()
                        Divider()
                    }
                    PreviewContainerView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(colorScheme)
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

private struct SidebarResizeHandle: View {
    @Binding var width: Double?

    var body: some View {
        AppKitSidebarResizeHandle(width: $width)
            .frame(width: 28)
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
        NSColor.separatorColor.setFill()
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
        HStack(spacing: 10) {
            Button {
                var settings = workspace.settings
                settings.isSidebarVisible.toggle()
                workspace.settings = settings
            } label: {
                Label("Toggle Sidebar", systemImage: workspace.settings.isSidebarVisible ? "sidebar.left" : "sidebar.left")
            }
            .labelStyle(.iconOnly)
            .help(workspace.settings.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")

            Button {
                workspace.openDirectoryPanel()
            } label: {
                Label("Open Folder", systemImage: "folder")
            }
            .labelStyle(.iconOnly)
            .help("Open Folder")

            Button {
                workspace.openFilePanel()
            } label: {
                Label("Open File", systemImage: "doc")
            }
            .labelStyle(.iconOnly)
            .help("Open File")

            Button {
                workspace.refreshSelectedTab()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .labelStyle(.iconOnly)
            .disabled(workspace.selectedTab == nil)
            .help("Refresh")

            if let rootURL = workspace.rootURL {
                Text(rootURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Open a folder or Markdown file")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Width", selection: settingsBinding(\.previewWidth)) {
                ForEach(PreviewWidth.allCases, id: \.self) { width in
                    Text(width.label).tag(width)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
            .help("Preview Width")

            Picker("Font Size", selection: settingsBinding(\.fontSize)) {
                ForEach(fontSizes, id: \.self) { size in
                    Text("\(Int(size))px").tag(size)
                }
            }
            .labelsHidden()
            .frame(width: 82)
            .help("Font Size")

            Picker("Font", selection: settingsBinding(\.fontFamily)) {
                ForEach(fontOptions, id: \.id) { option in
                    Text(option.name).tag(option.id)
                }
            }
            .labelsHidden()
            .frame(width: 150)
            .help("Font")

            Picker("Theme", selection: settingsBinding(\.theme)) {
                Text("System").tag(AppTheme.system)
                Text("Light").tag(AppTheme.light)
                Text("Dark").tag(AppTheme.dark)
            }
            .labelsHidden()
            .frame(width: 110)
            .help("Theme")
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
    }

    private var fontSizes: [Double] {
        [12, 13, 14, 15, 16, 17, 18, 20, 22, 24, 28]
    }

    private var fontOptions: [FontOption] {
        [
            FontOption(id: FontFamily.systemID, name: "System"),
            FontOption(id: FontFamily.serifID, name: "Serif"),
            FontOption(id: FontFamily.monospaceID, name: "Mono"),
            FontOption(id: "Avenir Next", name: "Avenir Next"),
            FontOption(id: "Georgia", name: "Georgia"),
            FontOption(id: "Helvetica Neue", name: "Helvetica"),
            FontOption(id: "Menlo", name: "Menlo")
        ]
    }

    private func settingsBinding<Value>(_ keyPath: WritableKeyPath<PersistedSettings, Value>) -> Binding<Value> {
        Binding {
            workspace.settings[keyPath: keyPath]
        } set: { value in
            var settings = workspace.settings
            settings[keyPath: keyPath] = value
            workspace.settings = settings
        }
    }
}

private struct FontOption: Hashable {
    let id: String
    let name: String
}

private struct SidebarView: View {
    @EnvironmentObject private var workspace: WorkspaceModel

    var body: some View {
        VStack(spacing: 0) {
            if let rootURL = workspace.rootURL {
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
                            startsExpanded: true,
                            initialChildren: workspace.rootChildren
                        )
                        .id(rootURL)
                    }
                    .padding(.vertical, 6)
                }
            } else {
                EmptySidebarView()
            }
        }
    }
}

private struct EmptySidebarView: View {
    @EnvironmentObject private var workspace: WorkspaceModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("No workspace")
                .font(.headline)
            Button("Open Folder") {
                workspace.openDirectoryPanel()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct DirectoryNodeView: View {
    @EnvironmentObject private var workspace: WorkspaceModel
    let item: FileItem
    let level: Int
    let startsExpanded: Bool
    let initialChildren: [FileItem]?
    @State private var isExpanded: Bool
    @State private var children: [FileItem]?
    @State private var isLoading = false

    init(item: FileItem, level: Int, startsExpanded: Bool = false, initialChildren: [FileItem]? = nil) {
        self.item = item
        self.level = level
        self.startsExpanded = startsExpanded
        self.initialChildren = initialChildren
        _isExpanded = State(initialValue: startsExpanded)
        _children = State(initialValue: initialChildren)
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
        .onChange(of: item.url) {
            isExpanded = startsExpanded
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
        isExpanded.toggle()
        guard isExpanded, children == nil else {
            return
        }
        isLoading = true
        Task {
            let loaded = await workspace.children(of: item.url)
            children = loaded
            isLoading = false
        }
    }
}

private struct FileRowView: View {
    @EnvironmentObject private var workspace: WorkspaceModel
    let item: FileItem
    let level: Int
    var isExpanded: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(iconColor)
                .frame(width: 16)
            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .padding(.leading, CGFloat(level) * 18 + 8)
        .padding(.trailing, 8)
        .frame(height: 26)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
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
}

private struct TabBarView: View {
    @EnvironmentObject private var workspace: WorkspaceModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(workspace.tabs) { tab in
                    HStack(spacing: 8) {
                        Button {
                            workspace.selectedTabID = tab.id
                        } label: {
                            Text(tab.title)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 180)
                        }
                        .buttonStyle(.plain)

                        Button {
                            workspace.closeTab(tab.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .help("Close")
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(tab.id == workspace.selectedTabID ? Color(nsColor: .textBackgroundColor) : Color.clear)
                    .overlay(alignment: .bottom) {
                        if tab.id == workspace.selectedTabID {
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(height: 2)
                        }
                    }
                    Divider()
                }
            }
        }
        .frame(height: 34)
    }
}

private struct PreviewContainerView: View {
    @EnvironmentObject private var workspace: WorkspaceModel

    var body: some View {
        ZStack {
            if let tab = workspace.selectedTab {
                if let payload = tab.payload {
                    RendererWebView(workspace: workspace, payload: payload)
                        .id(tab.id)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text(tab.errorMessage ?? "Unable to preview this file.")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                    Text("Select a file to preview")
                        .foregroundStyle(.secondary)
                    if let statusMessage = workspace.statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            if let statusMessage = workspace.statusMessage, workspace.selectedTab != nil {
                VStack {
                    Spacer()
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
