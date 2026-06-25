import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var workspace: WorkspaceModel

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView()
            Divider()
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: workspace.settings.sidebarWidth)
                    .background(Color(nsColor: .controlBackgroundColor))
                SidebarResizeHandle()
                VStack(spacing: 0) {
                    TabBarView()
                    Divider()
                    PreviewContainerView()
                }
            }
        }
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
    @EnvironmentObject private var workspace: WorkspaceModel

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .overlay {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                var settings = workspace.settings
                                settings.sidebarWidth = min(520, max(180, settings.sidebarWidth + value.translation.width))
                                workspace.settings = settings
                            }
                    )
            }
    }
}

private struct ToolbarView: View {
    @EnvironmentObject private var workspace: WorkspaceModel

    var body: some View {
        HStack(spacing: 10) {
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

            Stepper(value: settingsBinding(\.fontSize), in: 12...28, step: 1) {
                Text("\(Int(workspace.settings.fontSize))px")
                    .monospacedDigit()
                    .frame(width: 42, alignment: .trailing)
            }
            .help("Font Size")

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
        .frame(height: workspace.tabs.isEmpty ? 0 : 34)
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
    }
}
