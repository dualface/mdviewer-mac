import SwiftUI

struct SidebarView: View {
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
