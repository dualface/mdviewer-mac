import SwiftUI

@main
struct MDViewerMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var workspace = WorkspaceModel()

    var body: some Scene {
        Window("MarkdownViewer", id: "main") {
            ContentView()
                .environmentObject(workspace)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear {
                    appDelegate.attach(workspace)
                }
        }
        .commands {
            AppCommands(workspace: workspace)
        }
    }
}
