import SwiftUI

struct TabBarView: View {
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
