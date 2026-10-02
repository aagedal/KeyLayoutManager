import XCTest
@testable import KeyLayoutManager

final class RestoreAndStagingTests: XCTestCase {
    @MainActor
    func testWorkspaceDiscoveryAndLooseRestore() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let profile = root.appendingPathComponent("Adobe/Premiere Pro/26.0/Profile-test")
        let layouts = profile.appendingPathComponent("Layouts")
        try fm.createDirectory(at: layouts, withIntermediateDirectories: true)
        let workspace = layouts.appendingPathComponent("UserWorkspace.xml")
        let xml = "<?xml version='1.0'?><prop.map><prop.list><prop.pair><key>DVA_Wrkspce</key><string>1.2</string></prop.pair></prop.list></prop.map>"
        try Data(xml.utf8).write(to: workspace)
        let config = layouts.appendingPathComponent("WorkspaceConfig.xml")
        try Data("<prop.map><key>BuiltInKeys</key></prop.map>".utf8).write(to: config)
        let malformed = layouts.appendingPathComponent("Broken.xml")
        try Data("<prop.map><key>DVA_Wrkspce</key>".utf8).write(to: malformed)
        let scanner = PremiereScanner(documentsRoot: root)
        XCTAssertEqual(try scanner.scanItems(of: .workspace).map { $0.fileURL.resolvingSymlinksInPath() }, [workspace.resolvingSymlinksInPath()])
        XCTAssertNil(PremiereItemKind.kind(forFile: config))
        XCTAssertNil(PremiereItemKind.kind(forFile: malformed))

        // A renamed export must still be recognized by its contents.
        let exported = root.appendingPathComponent("My panels.XML")
        try fm.copyItem(at: workspace, to: exported)
        let model = RestoreViewModel(scanner: scanner)
        let destination = root.appendingPathComponent("destination")
        model.selectedDestination = ProfileLocation(version: "26.0", profileName: "dest", profileRootURL: destination)
        await model.add(urls: [exported])
        XCTAssertEqual(model.incomingItems.first?.relativePath, "Layouts/My panels.XML")
        await model.performRestore()
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("Layouts/My panels.XML")), xml)
        XCTAssertTrue(model.incomingItems.isEmpty)
    }

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
