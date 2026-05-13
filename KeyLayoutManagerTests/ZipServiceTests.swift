import XCTest
@testable import KeyLayoutManager

final class ZipServiceTests: XCTestCase {
    var tmpRoot: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        tmpRoot = fm.temporaryDirectory
            .appendingPathComponent("PKZip-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tmpRoot)
    }

    func testCreateListExtractRoundTrip() async throws {
        let profileRoot = tmpRoot.appendingPathComponent("Profile-test", isDirectory: true)
        let macDir = profileRoot.appendingPathComponent("Mac", isDirectory: true)
        let presetsDir = profileRoot
            .appendingPathComponent("Settings", isDirectory: true)
            .appendingPathComponent("Source Patcher Presets", isDirectory: true)
        try fm.createDirectory(at: macDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: presetsDir, withIntermediateDirectories: true)

        let kysURL = macDir.appendingPathComponent("Default.kys")
        let presetURL = presetsDir.appendingPathComponent("Stereo.sppreset")
        try Data("keyboard contents".utf8).write(to: kysURL)
        try Data("preset contents".utf8).write(to: presetURL)

        let zipURL = tmpRoot.appendingPathComponent("backup.zip")
        let manifest = BackupManifest(appVersion: "test",
                                      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                                      sourceVersion: "26.0",
                                      sourceProfileName: "test")

        let service = ZipService()
        try await service.createZip(contents: profileRoot, manifest: manifest, to: zipURL)
        XCTAssertTrue(fm.fileExists(atPath: zipURL.path))

        let entries = try await service.listEntries(zip: zipURL)
        let paths = Set(entries.map(\.path))
        XCTAssertTrue(paths.contains(ZipService.manifestFilename), "manifest at zip root")
        XCTAssertTrue(paths.contains("Mac/Default.kys"))
        XCTAssertTrue(paths.contains("Settings/Source Patcher Presets/Stereo.sppreset"))

        let recoveredManifest = await service.readManifest(zip: zipURL)
        XCTAssertEqual(recoveredManifest?.sourceVersion, "26.0")
        XCTAssertEqual(recoveredManifest?.sourceProfileName, "test")

        let extractDir = tmpRoot.appendingPathComponent("extracted", isDirectory: true)
        let extracted = try await service.extract(
            entries: ["Mac/Default.kys"],
            from: zipURL,
            into: extractDir
        )
        let extractedKys = try XCTUnwrap(extracted["Mac/Default.kys"])
        XCTAssertEqual(try String(contentsOf: extractedKys, encoding: .utf8), "keyboard contents")

        // The preset should NOT have been extracted since we asked for one entry only.
        let presetExtractPath = extractDir
            .appendingPathComponent("Settings", isDirectory: true)
            .appendingPathComponent("Source Patcher Presets", isDirectory: true)
            .appendingPathComponent("Stereo.sppreset")
        XCTAssertFalse(fm.fileExists(atPath: presetExtractPath.path), "only requested entry was extracted")
    }

    func testListEntriesSkipsMacOSMetadata() async throws {
        let zipURL = tmpRoot.appendingPathComponent("synthetic.zip")
        let staging = tmpRoot.appendingPathComponent("stage", isDirectory: true)
        let macosx = staging.appendingPathComponent("__MACOSX", isDirectory: true)
        let nested = staging.appendingPathComponent("Sub", isDirectory: true)
        try fm.createDirectory(at: macosx, withIntermediateDirectories: true)
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("noise".utf8).write(to: macosx.appendingPathComponent("noise.txt"))
        try Data("ok".utf8).write(to: staging.appendingPathComponent("real.txt"))
        try Data("dot".utf8).write(to: staging.appendingPathComponent(".DS_Store"))
        try Data("dot".utf8).write(to: nested.appendingPathComponent(".DS_Store"))
        try Data("ad".utf8).write(to: staging.appendingPathComponent("._real.txt"))

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc.currentDirectoryURL = staging
        proc.arguments = ["-rq", zipURL.path, "."]
        try proc.run()
        proc.waitUntilExit()

        let entries = try await ZipService().listEntries(zip: zipURL)
        let paths = entries.map(\.path)
        XCTAssertTrue(paths.contains("real.txt"))
        XCTAssertFalse(paths.contains(where: { $0.hasPrefix("__MACOSX/") }))
        XCTAssertFalse(paths.contains(where: { ($0 as NSString).lastPathComponent == ".DS_Store" }))
        XCTAssertFalse(paths.contains(where: { ($0 as NSString).lastPathComponent.hasPrefix("._") }))
    }

    func testCreateZipExcludesNoiseFiles() async throws {
        let profileRoot = tmpRoot.appendingPathComponent("Profile-x", isDirectory: true)
        let mac = profileRoot.appendingPathComponent("Mac", isDirectory: true)
        try fm.createDirectory(at: mac, withIntermediateDirectories: true)
        try Data("layout".utf8).write(to: mac.appendingPathComponent("Default.kys"))
        try Data("junk".utf8).write(to: profileRoot.appendingPathComponent(".DS_Store"))
        try Data("junk".utf8).write(to: mac.appendingPathComponent(".DS_Store"))
        try Data("ad".utf8).write(to: mac.appendingPathComponent("._Default.kys"))
        try Data("cache".utf8).write(to: profileRoot.appendingPathComponent("metadatacache.prmdc2"))
        try Data("wal".utf8).write(to: profileRoot.appendingPathComponent("metadatacache.prmdc2-wal"))
        try Data("shm".utf8).write(to: profileRoot.appendingPathComponent("metadatacache.prmdc2-shm"))

        let zipURL = tmpRoot.appendingPathComponent("clean.zip")
        let manifest = BackupManifest(appVersion: "test",
                                      sourceVersion: "26.0",
                                      sourceProfileName: "x")
        try await ZipService().createZip(contents: profileRoot, manifest: manifest, to: zipURL)

        let entries = try await ZipService().listEntries(zip: zipURL)
        let paths = entries.map(\.path)
        XCTAssertTrue(paths.contains("Mac/Default.kys"))
        XCTAssertFalse(paths.contains(where: { ($0 as NSString).lastPathComponent == ".DS_Store" }))
        XCTAssertFalse(paths.contains(where: { ($0 as NSString).lastPathComponent.hasPrefix("._") }))
        XCTAssertFalse(paths.contains(where: { ($0 as NSString).lastPathComponent.hasPrefix("metadatacache.prmdc2") }))
    }

    func testListEntriesSkipsMetadataCacheFromExistingZip() async throws {
        let zipURL = tmpRoot.appendingPathComponent("legacy.zip")
        let staging = tmpRoot.appendingPathComponent("legacy", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("ok".utf8).write(to: staging.appendingPathComponent("real.txt"))
        try Data("cache".utf8).write(to: staging.appendingPathComponent("metadatacache.prmdc2"))
        try Data("wal".utf8).write(to: staging.appendingPathComponent("metadatacache.prmdc2-wal"))

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc.currentDirectoryURL = staging
        proc.arguments = ["-rq", zipURL.path, "."]
        try proc.run()
        proc.waitUntilExit()

        let paths = try await ZipService().listEntries(zip: zipURL).map(\.path)
        XCTAssertTrue(paths.contains("real.txt"))
        XCTAssertFalse(paths.contains(where: { ($0 as NSString).lastPathComponent.hasPrefix("metadatacache.prmdc2") }))
    }

    func testReadManifestReturnsNilForArbitraryZip() async throws {
        let zipURL = tmpRoot.appendingPathComponent("plain.zip")
        let staging = tmpRoot.appendingPathComponent("plain", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("hi".utf8).write(to: staging.appendingPathComponent("hi.txt"))

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc.currentDirectoryURL = staging
        proc.arguments = ["-rq", zipURL.path, "."]
        try proc.run()
        proc.waitUntilExit()

        let manifest = await ZipService().readManifest(zip: zipURL)
        XCTAssertNil(manifest)
    }
}
