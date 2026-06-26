import XCTest
@testable import MDViewerMac

@MainActor
final class WorkspaceModelTests: XCTestCase {
    private var tempRoot: URL!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUpWithError() throws {
        defaultsSuiteName = "WorkspaceModelTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        XCTAssertNotNil(defaults)
        AppStorage.defaults = defaults

        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try "# One".write(to: tempRoot.appendingPathComponent("one.md"), atomically: true, encoding: .utf8)
        try "# Two".write(to: tempRoot.appendingPathComponent("two.md"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        AppStorage.defaults = .standard
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testOpeningDocumentInsideCurrentWorkspaceDoesNotResetTabs() throws {
        let model = WorkspaceModel()
        let one = tempRoot.appendingPathComponent("one.md")
        let two = tempRoot.appendingPathComponent("two.md")

        model.openWorkspace(tempRoot)
        model.openFile(one)
        model.openDocumentURL(two)

        XCTAssertEqual(model.tabs.map(\.url.lastPathComponent), ["one.md", "two.md"])
        XCTAssertEqual(model.selectedTab?.url.lastPathComponent, "two.md")
        XCTAssertEqual(model.rootURL, tempRoot.standardizedFileURL.resolvingSymlinksInPath())
    }

    func testOpeningSameDocumentSelectsAndRefreshesExistingTab() throws {
        let model = WorkspaceModel()
        let one = tempRoot.appendingPathComponent("one.md")

        model.openDocumentURL(one)
        let firstTabID = try XCTUnwrap(model.selectedTabID)
        XCTAssertEqual(model.selectedTab?.payload?.markdown, "# One")

        try "# Changed".write(to: one, atomically: true, encoding: .utf8)
        model.openDocumentURL(one.standardizedFileURL)

        XCTAssertEqual(model.tabs.count, 1)
        XCTAssertEqual(model.selectedTabID, firstTabID)
        XCTAssertEqual(model.selectedTab?.payload?.markdown, "# Changed")
    }

    func testOpeningMarkdownFromExternalEventSwitchesToContainingDirectoryWithoutShowingSidebar() throws {
        let model = WorkspaceModel()
        let childDirectory = tempRoot.appendingPathComponent("child", isDirectory: true)
        let nested = childDirectory.appendingPathComponent("nested.md")
        try FileManager.default.createDirectory(at: childDirectory, withIntermediateDirectories: true)
        try "# Nested".write(to: nested, atomically: true, encoding: .utf8)

        model.openWorkspace(tempRoot)
        model.setSidebarVisible(true)
        model.openExternalDocumentURL(nested)

        XCTAssertEqual(model.rootURL, childDirectory.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(model.selectedTab?.url, nested.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(model.selectedTab?.payload?.markdown, "# Nested")
        XCTAssertFalse(model.settings.isSidebarVisible)
    }
}
