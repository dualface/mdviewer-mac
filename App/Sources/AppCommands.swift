import SwiftUI

struct AppCommands: Commands {
    @ObservedObject var workspace: WorkspaceModel

    private let tabShortcutKeys: [Character] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    private let previewWidthShortcuts: [(key: Character, width: PreviewWidth)] = [
        ("1", .full),
        ("2", .wide),
        ("3", .medium),
        ("4", .narrow),
    ]

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button {
                workspace.openFilePanel()
            } label: {
                Label("Open File...", systemImage: "doc")
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button {
                workspace.openDirectoryPanel()
            } label: {
                Label("Open Folder...", systemImage: "folder")
            }
            .keyboardShortcut("e", modifiers: [.command])

            Divider()

            Button {
                workspace.closeSelectedTab()
            } label: {
                Label("Close File", systemImage: "xmark.circle")
            }
            .keyboardShortcut("w", modifiers: [.command])
            .disabled(workspace.selectedTab == nil)

            Button {
                workspace.closeOtherTabs()
            } label: {
                Label("Close Other Files", systemImage: "rectangle.stack.badge.minus")
            }
            .keyboardShortcut("w", modifiers: [.command, .option])
            .disabled(workspace.selectedTab == nil || workspace.tabs.count <= 1)

            Button {
                workspace.closeAllTabs()
            } label: {
                Label("Close All Files", systemImage: "xmark.circle.fill")
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .disabled(workspace.tabs.isEmpty)
        }

        CommandGroup(replacing: .sidebar) {
            Button {
                workspace.refreshSelectedTab()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: [.command])

            Menu {
                ForEach(AppTheme.allCases, id: \.self) { theme in
                    Button {
                        workspace.setTheme(theme)
                    } label: {
                        Label(theme.label, systemImage: theme.menuSystemImage)
                    }
                    .disabled(workspace.settings.theme == theme)
                }
            } label: {
                Label("Theme", systemImage: "circle.lefthalf.filled")
            }

            Divider()

            Menu {
                ForEach(previewWidthShortcuts, id: \.width) { shortcut in
                    Button {
                        workspace.setPreviewWidth(shortcut.width)
                    } label: {
                        Label(shortcut.width.label, systemImage: shortcut.width.menuSystemImage)
                    }
                    .keyboardShortcut(KeyEquivalent(shortcut.key), modifiers: [.option])
                    .disabled(workspace.settings.previewWidth == shortcut.width)
                }
            } label: {
                Label("Preview Width", systemImage: "arrow.left.and.right")
            }

            Divider()

            Menu {
                Menu {
                    ForEach(PreviewFont.sizes, id: \.self) { size in
                        Button {
                            workspace.setPreviewFontSize(size)
                        } label: {
                            Label("\(Int(size))px", systemImage: "textformat.size")
                        }
                        .disabled(workspace.settings.fontSize == size)
                    }
                } label: {
                    Label("Size", systemImage: "textformat.size")
                }

                Divider()

                Menu {
                    ForEach(PreviewFont.options) { option in
                        Button {
                            workspace.setPreviewFontFamily(option.id)
                        } label: {
                            Label(option.label, systemImage: option.menuSystemImage)
                        }
                        .disabled(workspace.settings.fontFamily == option.id)
                    }
                } label: {
                    Label("Family", systemImage: "textformat")
                }
            } label: {
                Label("Preview Font", systemImage: "textformat")
            }

            Divider()

            Button {
                workspace.toggleSidebar()
            } label: {
                Label(workspace.settings.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar", systemImage: "sidebar.left")
            }
            .keyboardShortcut("b", modifiers: [.command])

            Button {
                workspace.toggleToolbar()
            } label: {
                Label(workspace.settings.isToolbarVisible ? "Hide Toolbar" : "Show Toolbar", systemImage: "menubar.rectangle")
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
        }

        CommandGroup(after: .windowArrangement) {
            ForEach(0..<10, id: \.self) { index in
                Button {
                    workspace.selectTab(at: index)
                } label: {
                    Label("Select File \(index + 1)", systemImage: "doc.text")
                }
                .keyboardShortcut(KeyEquivalent(tabShortcutKeys[index]), modifiers: [.command])
                .disabled(workspace.tabs.count <= index)
            }
        }
    }
}

private extension AppTheme {
    var menuSystemImage: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max"
        case .dark:
            return "moon"
        }
    }
}

private extension PreviewWidth {
    var menuSystemImage: String {
        switch self {
        case .full:
            return "arrow.left.and.right"
        case .wide:
            return "rectangle"
        case .medium:
            return "rectangle.center.inset.filled"
        case .narrow:
            return "sidebar.right"
        }
    }
}

private extension PreviewFontOption {
    var menuSystemImage: String {
        switch id {
        case FontFamily.systemID:
            return "textformat"
        case FontFamily.serifID:
            return "textformat.alt"
        case FontFamily.monospaceID, "Menlo":
            return "curlybraces"
        default:
            return "textformat.abc"
        }
    }
}
