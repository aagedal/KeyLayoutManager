import XCTest
@testable import KeyLayoutManager

final class CopyServiceTests: XCTestCase {
    var tmpRoot: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        tmpRoot = fm.temporaryDirectory.appendingPathComponent("PKCopy-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tmpRoot)
    }

    func testCopyToFreshDestination() async throws {
        let (source, dest) = try makeSourceAndDest(contents: "hello")
        let outcome = try await CopyService().copy(source, into: dest, policy: .overwrite)
        if case .copied(let url) = outcome {
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "hello")
        } else {
            XCTFail("expected .copied, got \(outcome)")
        }
    }

    func testOverwriteReplacesExistingFile() async throws {
        let (source, dest) = try makeSourceAndDest(contents: "new")
        try Data("old".utf8).write(to: dest.appendingPathComponent("file.kys"))

        let outcome = try await CopyService().copy(source, into: dest, policy: .overwrite)
        guard case .copied(let url) = outcome else { return XCTFail() }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "new")
    }

    func testKeepBothBumpsName() async throws {
        let (source, dest) = try makeSourceAndDest(contents: "new")
        try Data("existing".utf8).write(to: dest.appendingPathComponent("file.kys"))

        let outcome = try await CopyService().copy(source, into: dest, policy: .keepBoth)
        guard case .renamed(let url) = outcome else { return XCTFail("got \(outcome)") }
        XCTAssertEqual(url.lastPathComponent, "file (2).kys")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "new")
        // original untouched
        let original = dest.appendingPathComponent("file.kys")
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "existing")
    }

    func testKeepBothBumpsRepeatedly() async throws {
        let (source, dest) = try makeSourceAndDest(contents: "new")
        try Data("a".utf8).write(to: dest.appendingPathComponent("file.kys"))
        try Data("b".utf8).write(to: dest.appendingPathComponent("file (2).kys"))

        let outcome = try await CopyService().copy(source, into: dest, policy: .keepBoth)
        guard case .renamed(let url) = outcome else { return XCTFail() }
        XCTAssertEqual(url.lastPathComponent, "file (3).kys")
    }

    func testSkipLeavesExisting() async throws {
        let (source, dest) = try makeSourceAndDest(contents: "new")
        let existing = dest.appendingPathComponent("file.kys")
        try Data("existing".utf8).write(to: existing)

        let outcome = try await CopyService().copy(source, into: dest, policy: .skip)
        if case .skipped = outcome {} else { XCTFail("expected .skipped") }
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "existing")
    }

    func testPromptRoutesThroughHandler() async throws {
        let (source, dest) = try makeSourceAndDest(contents: "new")
        try Data("existing".utf8).write(to: dest.appendingPathComponent("file.kys"))

        let outcome = try await CopyService().copy(source, into: dest, policy: .prompt) { _ in
            .keepBoth
        }
        guard case .renamed(let url) = outcome else { return XCTFail() }
        XCTAssertEqual(url.lastPathComponent, "file (2).kys")
    }

    func testPromptWithoutHandlerSkips() async throws {
        let (source, dest) = try makeSourceAndDest(contents: "new")
        try Data("existing".utf8).write(to: dest.appendingPathComponent("file.kys"))

        let outcome = try await CopyService().copy(source, into: dest, policy: .prompt)
        if case .skipped = outcome {} else { XCTFail("expected .skipped") }
    }

    func testCreatesMissingDestinationDirectory() async throws {
        let source = tmpRoot.appendingPathComponent("file.kys")
        try Data("hi".utf8).write(to: source)
        let dest = tmpRoot.appendingPathComponent("a/b/c", isDirectory: true)
        XCTAssertFalse(fm.fileExists(atPath: dest.path))

        let outcome = try await CopyService().copy(source, into: dest, policy: .overwrite)
        if case .copied = outcome {} else { XCTFail() }
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("file.kys").path))
    }

    func testOverwriteSameFilePreservesSource() async throws {
        let (source, _) = try makeSourceAndDest(contents: "original")
        let outcome = try await CopyService().copy(source, into: source.deletingLastPathComponent(), policy: .overwrite)
        XCTAssertEqual(outcome, .skipped(source))
        XCTAssertEqual(try String(contentsOf: source), "original")
    }

    func testFailedOverwritePreservesDestination() async throws {
        let (source, dest) = try makeSourceAndDest(contents: "new")
        let target = dest.appendingPathComponent(source.lastPathComponent)
        try Data("old".utf8).write(to: target)
        try fm.removeItem(at: source)
        do {
            _ = try await CopyService().copy(source, into: dest, policy: .overwrite)
            XCTFail("Missing source should fail")
        } catch {}
        XCTAssertEqual(try String(contentsOf: target), "old")
    }

    // MARK: - helpers

    private func makeSourceAndDest(contents: String) throws -> (URL, URL) {
        let source = tmpRoot.appendingPathComponent("source/file.kys")
        try fm.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: source)

        let dest = tmpRoot.appendingPathComponent("dest", isDirectory: true)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        return (source, dest)
    }
}
