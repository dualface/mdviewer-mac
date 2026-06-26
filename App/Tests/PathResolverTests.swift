import XCTest
@testable import MDViewerMac

final class PathResolverTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: tempRoot.appendingPathComponent("docs/assets", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "hello".write(
            to: tempRoot.appendingPathComponent("docs/readme.md"),
            atomically: true,
            encoding: .utf8
        )
        try Data().write(to: tempRoot.appendingPathComponent("docs/assets/image.png"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testRelativePathStaysInsideWorkspace() throws {
        let resolver = PathResolver(rootURL: tempRoot)
        let file = tempRoot.appendingPathComponent("docs/readme.md")

        XCTAssertEqual(try resolver.relativePath(for: file), "/docs/readme.md")
        XCTAssertTrue(resolver.contains(file))
    }

    func testRejectsOutsideWorkspace() throws {
        let resolver = PathResolver(rootURL: tempRoot)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside.md")

        XCTAssertFalse(resolver.contains(outside))
        XCTAssertThrowsError(try resolver.relativePath(for: outside))
    }

    func testResolvesRelativeLinkFromDocument() throws {
        let resolver = PathResolver(rootURL: tempRoot)
        let doc = tempRoot.appendingPathComponent("docs/readme.md")

        let resolved = try resolver.resolveLink("assets/image.png", from: doc)

        XCTAssertEqual(resolved?.lastPathComponent, "image.png")
        XCTAssertTrue(resolver.contains(resolved!))
    }

    func testRejectsTraversalOutsideWorkspace() throws {
        let resolver = PathResolver(rootURL: tempRoot)
        let doc = tempRoot.appendingPathComponent("docs/readme.md")

        XCTAssertThrowsError(try resolver.resolveLink("../../escape.png", from: doc))
    }

    func testWorkspacePathAllowsDotsInsideFileName() throws {
        let resolver = PathResolver(rootURL: tempRoot)
        let file = tempRoot.appendingPathComponent("docs/notes..md")
        try "dots".write(to: file, atomically: true, encoding: .utf8)

        let resolved = try resolver.resolveWorkspacePath("/docs/notes..md")

        XCTAssertEqual(resolved, file.standardizedFileURL.resolvingSymlinksInPath())
    }

    func testWorkspacePathRejectsTraversalComponents() throws {
        let resolver = PathResolver(rootURL: tempRoot)

        XCTAssertThrowsError(try resolver.resolveWorkspacePath("/docs/../escape.md"))
    }
}
