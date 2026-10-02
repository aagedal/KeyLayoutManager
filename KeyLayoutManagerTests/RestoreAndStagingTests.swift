import XCTest
@testable import KeyLayoutManager

final class RestoreAndStagingTests: XCTestCase {
    func testSameNamedSourcesRemainDistinct() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let stage = TempStage()
        defer { try? fm.removeItem(at: root); stage.wipe() }
        let sources = ["a", "b"].map { root.appendingPathComponent($0).appendingPathComponent("Default.kys") }
        for (n, source) in sources.enumerated() {
            try fm.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("contents-\(n)".utf8).write(to: source)
        }
        let first = try stage.stage(sources[0])
        let second = try stage.stage(sources[1])
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try String(contentsOf: first), "contents-0")
        XCTAssertEqual(try String(contentsOf: second), "contents-1")
    }

    @MainActor
    func testRestorePreservesResultsFailedAndUnselectedItems() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let good = root.appendingPathComponent("good.kys")
        try Data("layout".utf8).write(to: good)
        let model = RestoreViewModel()
        model.selectedDestination = ProfileLocation(version: "26.0", profileName: "test", profileRootURL: root.appendingPathComponent("profile"))
        let success = IncomingItem.looseFile(url: good, kind: .kys)
        let failed = IncomingItem.looseFile(url: root.appendingPathComponent("missing.kys"), kind: .kys)
        var unselected = IncomingItem.looseFile(url: root.appendingPathComponent("unselected.kys"), kind: .kys)
        unselected.isSelected = false
        model.incomingItems = [success, failed, unselected]
        await model.performRestore()
        XCTAssertEqual(model.incomingItems.map(\.id), [failed.id, unselected.id])
        XCTAssertTrue(model.statusMessage?.contains("1 copied") == true)
        XCTAssertTrue(model.errorMessage?.contains("missing.kys") == true)
        XCTAssertFalse(model.isRestoring)
    }
}
