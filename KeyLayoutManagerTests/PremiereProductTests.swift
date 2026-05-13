import XCTest
@testable import KeyLayoutManager

final class PremiereProductTests: XCTestCase {
    func testProductNameSwitchesAtVersion26() {
        XCTAssertEqual(PremiereProduct.productName(forVersion: "26.0"), "Premiere")
        XCTAssertEqual(PremiereProduct.productName(forVersion: "26.10"), "Premiere")
        XCTAssertEqual(PremiereProduct.productName(forVersion: "27.0"), "Premiere")
        XCTAssertEqual(PremiereProduct.productName(forVersion: "25.6.1"), "Premiere Pro")
        XCTAssertEqual(PremiereProduct.productName(forVersion: "24.0"), "Premiere Pro")
    }

    func testDisplayName() {
        XCTAssertEqual(PremiereProduct.displayName(forVersion: "26.0"), "Premiere 26.0")
        XCTAssertEqual(PremiereProduct.displayName(forVersion: "25.6.1"), "Premiere Pro 25.6.1")
    }

    func testMalformedVersionFallsBackToProBranch() {
        XCTAssertEqual(PremiereProduct.productName(forVersion: ""), "Premiere Pro")
        XCTAssertEqual(PremiereProduct.productName(forVersion: "garbage"), "Premiere Pro")
    }
}
