import SwiftUI

struct PreviewContainerView: View {
    @EnvironmentObject private var workspace: WorkspaceModel

    var body: some View {
        ZStack {
            if let selectedTab = workspace.selectedTab {
                if selectedTab.isLoading || selectedTab.payload != nil {
                    RenderingPlaceholderView(title: selectedTab.title)
                }

                ForEach(workspace.tabs) { tab in
                    if let payload = tab.payload {
                        RendererWebView(
                            workspace: workspace,
                            tabID: tab.id,
                            payload: payload,
                            isVisible: tab.id == workspace.selectedTabID
                        )
                        .opacity(tab.id == workspace.selectedTabID ? 1 : 0)
                        .allowsHitTesting(tab.id == workspace.selectedTabID)
                        .accessibilityHidden(tab.id != workspace.selectedTabID)
                    }
                }

                if selectedTab.payload == nil && !selectedTab.isLoading {
                    PreviewErrorView(message: selectedTab.errorMessage)
                }
            } else {
                EmptyPreviewView()
            }
            if let statusMessage = workspace.selectedTab?.statusMessage ?? workspace.statusMessage,
               workspace.selectedTab != nil {
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
    @FocusState private var focusedControl: EmptyPreviewFocus?

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
                .focused($focusedControl, equals: .openDocument)

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
        .onAppear {
            focusOpenDocumentButton()
        }
        .onChange(of: workspace.tabs.isEmpty) { _, isEmpty in
            if isEmpty {
                focusOpenDocumentButton()
            }
        }
    }

    private func focusOpenDocumentButton() {
        DispatchQueue.main.async {
            focusedControl = .openDocument
        }
    }

    private enum EmptyPreviewFocus: Hashable {
        case openDocument
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
