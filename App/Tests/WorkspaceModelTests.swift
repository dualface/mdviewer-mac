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

    func testSelectedDocumentRefreshesWhenFileChanges() throws {
        let model = WorkspaceModel()
        let one = tempRoot.appendingPathComponent("one.md")

        model.openDocumentURL(one)
        XCTAssertEqual(model.selectedTab?.payload?.markdown, "# One")

        try "# Auto refreshed".write(to: one, atomically: true, encoding: .utf8)

        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { model, _ in
                (model as? WorkspaceModel)?.selectedTab?.payload?.markdown == "# Auto refreshed"
            },
            object: model
        )
        wait(for: [expectation], timeout: 2)
    }

    func testSelectedDocumentKeepsRefreshingAfterAtomicReplacement() throws {
        let model = WorkspaceModel()
        let one = tempRoot.appendingPathComponent("one.md")
        let replacement = tempRoot.appendingPathComponent("replacement.md")

        model.openDocumentURL(one)
        XCTAssertEqual(model.selectedTab?.payload?.markdown, "# One")

        try "# Replaced".write(to: replacement, atomically: true, encoding: .utf8)
        _ = try FileManager.default.replaceItemAt(one, withItemAt: replacement)

        let firstRefresh = XCTNSPredicateExpectation(
            predicate: NSPredicate { model, _ in
                (model as? WorkspaceModel)?.selectedTab?.payload?.markdown == "# Replaced"
            },
            object: model
        )
        wait(for: [firstRefresh], timeout: 2)

        try "# Replaced Again".write(to: one, atomically: true, encoding: .utf8)

        let secondRefresh = XCTNSPredicateExpectation(
            predicate: NSPredicate { model, _ in
                (model as? WorkspaceModel)?.selectedTab?.payload?.markdown == "# Replaced Again"
            },
            object: model
        )
        wait(for: [secondRefresh], timeout: 2)
    }

    func testOpeningExternalDocumentInsideCurrentWorkspaceKeepsWorkspaceAndExpandsDirectory() throws {
        let model = WorkspaceModel()
        let childDirectory = tempRoot.appendingPathComponent("child", isDirectory: true)
        let nested = childDirectory.appendingPathComponent("nested.md")
        try FileManager.default.createDirectory(at: childDirectory, withIntermediateDirectories: true)
        try "# Nested".write(to: nested, atomically: true, encoding: .utf8)

        model.openWorkspace(tempRoot)
        model.setSidebarVisible(true)
        let result = model.openExternalDocumentURL(nested)

        XCTAssertEqual(result, .handled)
        XCTAssertEqual(model.rootURL, tempRoot.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(model.selectedTab?.url, nested.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(model.selectedTab?.payload?.markdown, "# Nested")
        XCTAssertTrue(model.settings.isSidebarVisible)
        XCTAssertTrue(model.isDirectoryExpanded(childDirectory))
    }

    func testOpeningExternalDocumentOutsideCurrentWorkspaceRequestsNewWorkspaceWithoutChangingState() throws {
        let model = WorkspaceModel()
        let one = tempRoot.appendingPathComponent("one.md")
        let outsideRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outsideDocument = outsideRoot.appendingPathComponent("outside.md")
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        try "# Outside".write(to: outsideDocument, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: outsideRoot)
        }

        model.openWorkspace(tempRoot)
        model.openFile(one)
        let selectedTabID = model.selectedTabID
        let result = model.openExternalDocumentURL(outsideDocument)

        XCTAssertEqual(result, .needsWorkspace(outsideDocument.standardizedFileURL.resolvingSymlinksInPath()))
        XCTAssertEqual(model.rootURL, tempRoot.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(model.selectedTabID, selectedTabID)
        XCTAssertEqual(model.selectedTab?.url, one.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(model.tabs.map(\.url.lastPathComponent), ["one.md"])
    }

    func testOpeningExternalDocumentCanInitializeWorkspaceWhenAllowed() throws {
        let model = WorkspaceModel()
        let childDirectory = tempRoot.appendingPathComponent("child", isDirectory: true)
        let nested = childDirectory.appendingPathComponent("nested.md")
        try FileManager.default.createDirectory(at: childDirectory, withIntermediateDirectories: true)
        try "# Nested".write(to: nested, atomically: true, encoding: .utf8)

        let result = model.openExternalDocumentURL(nested, opensWorkspaceIfNeeded: true)

        XCTAssertEqual(result, .handled)
        XCTAssertEqual(model.rootURL, childDirectory.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(model.selectedTab?.url, nested.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(model.selectedTab?.payload?.markdown, "# Nested")
        XCTAssertFalse(model.settings.isSidebarVisible)
    }

    func testOpeningDocumentExpandsContainingDirectoryChain() throws {
        let model = WorkspaceModel()
        let firstLevel = tempRoot.appendingPathComponent("first", isDirectory: true)
        let secondLevel = firstLevel.appendingPathComponent("second", isDirectory: true)
        let nested = secondLevel.appendingPathComponent("nested.md")
        try FileManager.default.createDirectory(at: secondLevel, withIntermediateDirectories: true)
        try "# Nested".write(to: nested, atomically: true, encoding: .utf8)

        model.openWorkspace(tempRoot)
        model.openFile(nested)

        XCTAssertTrue(model.isDirectoryExpanded(tempRoot))
        XCTAssertTrue(model.isDirectoryExpanded(firstLevel))
        XCTAssertTrue(model.isDirectoryExpanded(secondLevel))
    }

    func testSidebarExpansionStateSurvivesVisibilityToggle() throws {
        let model = WorkspaceModel()
        let manualDirectory = tempRoot.appendingPathComponent("manual", isDirectory: true)
        try FileManager.default.createDirectory(at: manualDirectory, withIntermediateDirectories: true)

        model.openWorkspace(tempRoot)
        model.expandDirectory(manualDirectory)
        model.setSidebarVisible(false)
        model.setSidebarVisible(true)

        XCTAssertTrue(model.isDirectoryExpanded(manualDirectory))
    }

    func testShowingSidebarExpandsSelectedDocumentDirectory() throws {
        let model = WorkspaceModel()
        let childDirectory = tempRoot.appendingPathComponent("child", isDirectory: true)
        let nested = childDirectory.appendingPathComponent("nested.md")
        try FileManager.default.createDirectory(at: childDirectory, withIntermediateDirectories: true)
        try "# Nested".write(to: nested, atomically: true, encoding: .utf8)

        model.openWorkspace(tempRoot)
        model.setSidebarVisible(false)
        model.openFile(nested)
        model.collapseDirectory(childDirectory)
        model.setSidebarVisible(true)

        XCTAssertTrue(model.isDirectoryExpanded(childDirectory))
    }
}
