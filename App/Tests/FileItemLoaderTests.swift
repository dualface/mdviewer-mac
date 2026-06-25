import XCTest
@testable import MDViewerMac

final class FileItemLoaderTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempRoot.appendingPathComponent("BFolder"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempRoot.appendingPathComponent("AFolder"), withIntermediateDirectories: true)
        try "# Title".write(to: tempRoot.appendingPathComponent("readme.md"), atomically: true, encoding: .utf8)
        try "{}".write(to: tempRoot.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        try "hidden".write(to: tempRoot.appendingPathComponent(".hidden.md"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testChildrenHideDotFilesAndSortDirectoriesFirst() throws {
        let children = try FileItemLoader.children(of: tempRoot)

        XCTAssertEqual(children.map(\.name), ["AFolder", "BFolder", "config.json", "readme.md"])
        XCTAssertEqual(children[0].kind, .directory)
        XCTAssertEqual(children[2].kind, .text)
        XCTAssertEqual(children[3].kind, .markdown)
    }
}
