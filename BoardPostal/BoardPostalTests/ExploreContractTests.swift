import XCTest
@testable import BoardPostal

final class ExploreContractTests: XCTestCase {
    func testDecodesCanonicalExplorePageContainingOneTrip() throws {
        let page: PaginatedResponse<PublicTripCard> = try decodeFixture("explore-page-one")
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items[0].title, "Published Istanbul")
    }

    func testDecodesMultipleTripsAndPaginationMetadata() throws {
        let page: PaginatedResponse<PublicTripCard> = try decodeFixture("explore-page-multiple")
        XCTAssertEqual(page.total, 3)
        XCTAssertEqual(page.page, 2)
        XCTAssertEqual(page.pageSize, 2)
        XCTAssertEqual(page.items.map(\.title), ["Alpine Weekend", "Quiet Coast"])
    }

    func testDecodesSuccessfulEmptyPage() throws {
        let page: PaginatedResponse<PublicTripCard> = try decodeFixture("explore-page-empty")
        XCTAssertEqual(page.total, 0)
        XCTAssertTrue(page.items.isEmpty)
    }

    func testDecodesOptionalAndNullCardFields() throws {
        let page: PaginatedResponse<PublicTripCard> = try decodeFixture("explore-page-multiple")
        let card = try XCTUnwrap(page.items.last)
        XCTAssertNil(card.coverPhotoUrl)
        XCTAssertNil(card.coverPhotoAttribution)
        XCTAssertNil(card.coverPhotoAttributionUrl)
        XCTAssertNil(card.destinations.first?.city)
        XCTAssertNil(card.owner.avatarUrl)
        XCTAssertNil(card.owner.avatarId)
    }

    func testMalformedJSONThrowsInsteadOfProducingEmptyPage() {
        XCTAssertThrowsError(try decodeFixture("explore-page-malformed") as PaginatedResponse<PublicTripCard>)
    }

    private func decodeFixture<T: Decodable>(_ name: String) throws -> T {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try JSONDecoder.bpDecoder.decode(T.self, from: Data(contentsOf: url))
    }
}
