import XCTest
@testable import KeyLayoutManager

final class BackupManifestTests: XCTestCase {
    func testRoundTripEncodingDecoding() throws {
        let original = BackupManifest(
            appVersion: "1.0 (42)",
            createdAt: Date(timeIntervalSince1970: 1_715_500_000),
            sourceVersion: "26.0",
            sourceProfileName: "Profile-truls"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackupManifest.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, BackupManifest.currentSchemaVersion)
        XCTAssertEqual(decoded.appVersion, "1.0 (42)")
        XCTAssertEqual(decoded.sourceVersion, "26.0")
        XCTAssertEqual(decoded.sourceProfileName, "Profile-truls")
        XCTAssertEqual(decoded.kind, BackupManifest.kindFullProfile)
        XCTAssertEqual(decoded.createdAt.timeIntervalSince1970, 1_715_500_000, accuracy: 1)
    }

    func testDefaultsApplied() {
        let m = BackupManifest(appVersion: "x",
                               sourceVersion: "26.0",
                               sourceProfileName: "p")
        XCTAssertEqual(m.schemaVersion, 1)
        XCTAssertEqual(m.kind, "full-profile")
    }
}
