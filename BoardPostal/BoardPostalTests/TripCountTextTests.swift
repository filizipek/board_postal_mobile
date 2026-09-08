import XCTest
@testable import BoardPostal

final class TripCountTextTests: XCTestCase {
    func testZeroUsesPlural() {
        XCTAssertEqual(TripCountText.make(0), "0 trips")
    }

    func testOneUsesSingular() {
        XCTAssertEqual(TripCountText.make(1), "1 trip")
    }

    func testMultipleUsesPlural() {
        XCTAssertEqual(TripCountText.make(4), "4 trips")
    }
}
