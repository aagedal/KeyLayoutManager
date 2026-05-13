import XCTest
@testable import PremiereKeyboarder

final class PremiereScannerTests: XCTestCase {
    var tmpRoot: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        tmpRoot = fm.temporaryDirectory.appendingPathComponent("PKTest-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tmpRoot)
    }

    func testDiscoversKysAcrossVersionsAndIgnoresNonVersionFolders() throws {
        try makeKys(version: "26.0", profile: "alice", filename: "Alice.kys", bytes: 100)
        try makeKys(version: "26.0", profile: "alice", filename: "Backup.kys", bytes: 200)
        try makeKys(version: "25.0", profile: "bob",   filename: "Bob.kys",   bytes: 50)
        try fm.createDirectory(at: premiere().appendingPathComponent("Cloud Media", isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: premiere().appendingPathComponent("Adobe Premiere Pro Auto-Save", isDirectory: true), withIntermediateDirectories: true)
        Data("junk".utf8).write(to: premiere().appendingPathComponent(".DS_Store"), atomically: true)

        let scanner = PremiereScanner(documentsRoot: tmpRoot)
        let installs = try scanner.scan()

        XCTAssertEqual(installs.map(\.version), ["26.0", "25.0"], "newest version first")
        XCTAssertEqual(installs[0].profiles.map(\.profileName), ["alice"])
        XCTAssertEqual(installs[1].profiles.map(\.profileName), ["bob"])

        let layouts = try scanner.scanLayouts()
        XCTAssertEqual(Set(layouts.map(\.displayName)), Set(["Alice", "Backup", "Bob"]))
        XCTAssertTrue(layouts.allSatisfy { $0.byteSize > 0 })
    }

    func testEmptyMacFolderProducesNoLayouts() throws {
        let macURL = premiere()
            .appendingPathComponent("26.0", isDirectory: true)
            .appendingPathComponent("Profile-alice", isDirectory: true)
            .appendingPathComponent("Mac", isDirectory: true)
        try fm.createDirectory(at: macURL, withIntermediateDirectories: true)

        let scanner = PremiereScanner(documentsRoot: tmpRoot)
        let layouts = try scanner.scanLayouts()
        XCTAssertTrue(layouts.isEmpty)

        let dests = try scanner.destinations()
        XCTAssertEqual(dests.count, 1)
        XCTAssertEqual(dests.first?.profileName, "alice")
    }

    func testMissingMacFolderIsNotAnError() throws {
        let profileURL = premiere()
            .appendingPathComponent("26.0", isDirectory: true)
            .appendingPathComponent("Profile-alice", isDirectory: true)
        try fm.createDirectory(at: profileURL, withIntermediateDirectories: true)

        let scanner = PremiereScanner(documentsRoot: tmpRoot)
        XCTAssertNoThrow(try scanner.scanLayouts())
        XCTAssertEqual(try scanner.destinations().count, 1)
    }

    func testVersionSortingHandlesMultiDigit() throws {
        try makeKys(version: "26.10", profile: "alice", filename: "A.kys")
        try makeKys(version: "26.9",  profile: "alice", filename: "B.kys")
        try makeKys(version: "25.0",  profile: "alice", filename: "C.kys")

        let scanner = PremiereScanner(documentsRoot: tmpRoot)
        let versions = try scanner.scan().map(\.version)
        XCTAssertEqual(versions, ["26.10", "26.9", "25.0"])
    }

    func testReturnsEmptyWhenPremiereRootMissing() throws {
        let scanner = PremiereScanner(documentsRoot: tmpRoot)
        XCTAssertEqual(try scanner.scan().count, 0)
        XCTAssertEqual(try scanner.destinations().count, 0)
    }

    // MARK: - helpers

    private func premiere() -> URL {
        tmpRoot
            .appendingPathComponent("Adobe", isDirectory: true)
            .appendingPathComponent("Premiere Pro", isDirectory: true)
    }

    @discardableResult
    private func makeKys(version: String, profile: String, filename: String, bytes: Int = 10) throws -> URL {
        let macURL = premiere()
            .appendingPathComponent(version, isDirectory: true)
            .appendingPathComponent("Profile-\(profile)", isDirectory: true)
            .appendingPathComponent("Mac", isDirectory: true)
        try fm.createDirectory(at: macURL, withIntermediateDirectories: true)
        let fileURL = macURL.appendingPathComponent(filename)
        try Data(repeating: 0x41, count: bytes).write(to: fileURL)
        return fileURL
    }
}
