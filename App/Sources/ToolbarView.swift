import AppKit
import SwiftUI

struct ToolbarView: View {
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

            HStack(spacing: 4) {
                PreviewWidthSegmentedControl(selection: previewWidthBinding)
                    .frame(width: 132, height: 24)
                    .help("Preview Width")
                    .accessibilityLabel("Preview Width")

                Picker("Font Size", selection: previewFontSizeBinding) {
                    ForEach(PreviewFont.sizes, id: \.self) { size in
                        Text("\(Int(size))px").tag(size)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 82)
                .help("Preview Font Size")
                .accessibilityLabel("Preview Font Size")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 46)
        .glassPanel(material: .bar)
    }

    private var previewWidthBinding: Binding<PreviewWidth> {
        Binding {
            workspace.settings.previewWidth
        } set: { width in
            workspace.setPreviewWidth(width)
        }
    }

    private var previewFontSizeBinding: Binding<Double> {
        Binding {
            workspace.settings.fontSize
        } set: { fontSize in
            workspace.setPreviewFontSize(fontSize)
        }
    }
}

private struct PreviewWidthSegmentedControl: NSViewRepresentable {
    @Binding var selection: PreviewWidth

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 132, height: 24))
        let control = NSSegmentedControl(
            images: PreviewWidth.allCases.map(\.toolbarImage),
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.selectionDidChange(_:))
        )
        control.translatesAutoresizingMaskIntoConstraints = false
        control.segmentStyle = .texturedRounded
        control.controlSize = .small
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        for index in PreviewWidth.allCases.indices {
            control.setWidth(33, forSegment: index)
            control.setToolTip(PreviewWidth.allCases[index].label, forSegment: index)
        }
        container.addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        context.coordinator.control = control
        return container
    }

    func updateNSView(_ view: NSView, context: Context) {
        let control = context.coordinator.control ?? view.subviews.compactMap { $0 as? NSSegmentedControl }.first
        guard let control else {
            return
        }
        control.target = context.coordinator
        control.action = #selector(Coordinator.selectionDidChange(_:))
        control.selectedSegment = PreviewWidth.allCases.firstIndex(of: selection) ?? 0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    final class Coordinator: NSObject {
        weak var control: NSSegmentedControl?
        private let selection: Binding<PreviewWidth>

        init(selection: Binding<PreviewWidth>) {
            self.selection = selection
        }

        @MainActor @objc func selectionDidChange(_ sender: NSSegmentedControl) {
            guard PreviewWidth.allCases.indices.contains(sender.selectedSegment) else {
                return
            }
            selection.wrappedValue = PreviewWidth.allCases[sender.selectedSegment]
        }
    }
}

private extension PreviewWidth {
    var toolbarImage: NSImage {
        let size = NSSize(width: 18, height: 14)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.labelColor.setStroke()
        let rect = NSRect(
            x: (size.width - toolbarIndicatorWidth) / 2,
            y: 2,
            width: toolbarIndicatorWidth,
            height: 10
        )
        let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        path.lineWidth = 1.5
        path.stroke()

        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = label
        return image
    }

    private var toolbarIndicatorWidth: CGFloat {
        switch self {
        case .full:
            return 16
        case .wide:
            return 13
        case .medium:
            return 10
        case .narrow:
            return 7
        }
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

            Text(displayPath)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.leading, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(displayPath)
    }

    private var displayPath: String {
        workspace.rootURL?.path ?? "Open a folder or Markdown file"
    }
}
