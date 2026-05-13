import XCTest
@testable import KeyLayoutManager

final class PremiereFileInfoTests: XCTestCase {
    func testKnownKindsAreDescribed() {
        XCTAssertNotNil(PremiereFileInfo.description(for: "Mac/Default.kys"))
        XCTAssertNotNil(PremiereFileInfo.description(for: "Settings/Source Patcher Presets/A1.sppreset"))
    }

    func testKnownFilenamesAreDescribed() {
        XCTAssertNotNil(PremiereFileInfo.description(for: "Adobe Premiere Pro Prefs"))
        XCTAssertNotNil(PremiereFileInfo.description(for: "metadatacache.prmdc2"))
        XCTAssertNotNil(PremiereFileInfo.description(for: "metadatacache.prmdc2-wal"))
        XCTAssertNotNil(PremiereFileInfo.description(for: "Installed Guides.guides"))
        XCTAssertNotNil(PremiereFileInfo.description(for: "SharedView Column Settings"))
    }

    func testPathHintWorksForUnknownExtensions() {
        XCTAssertNotNil(PremiereFileInfo.description(for: "Workspaces/Editing.xml"))
        XCTAssertNotNil(PremiereFileInfo.description(for: "Settings/Effects Presets/Custom.thing"))
    }

    func testUnknownReturnsNil() {
        XCTAssertNil(PremiereFileInfo.description(for: "something-completely-random"))
    }
}
