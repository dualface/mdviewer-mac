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

    func testOpeningSameDocumentSelectsExistingTab() throws {
        let model = WorkspaceModel()
        let one = tempRoot.appendingPathComponent("one.md")

        model.openDocumentURL(one)
        let firstTabID = try XCTUnwrap(model.selectedTabID)
        model.openDocumentURL(one.standardizedFileURL)

        XCTAssertEqual(model.tabs.count, 1)
        XCTAssertEqual(model.selectedTabID, firstTabID)
    }
}
