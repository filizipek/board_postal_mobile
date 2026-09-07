import XCTest
@testable import BoardPostal

@MainActor
final class ItineraryContractTests: XCTestCase {
    func testDecodesValidDayResponse() throws {
        let day: TripDay = try decodeFixture("itinerary-day")

        XCTAssertEqual(day.id, "30000000-0000-0000-0000-000000000001")
        XCTAssertEqual(day.date, "2026-04-01")
        XCTAssertEqual(day.items.map(\.type), ["transport"])
    }

    func testDecodesEveryValidItemType() throws {
        let items: [TripDayItem] = try decodeFixture("itinerary-items")

        XCTAssertEqual(items.map(\.itemType), [.place, .transport, .accommodation, .note])
        XCTAssertEqual(items[0].placeId, "50000000-0000-0000-0000-000000000001")
        XCTAssertNil(items[1].placeId)
    }

    func testDecodesCreateResponseWithOmittedOptionalFields() throws {
        let item: TripDayItem = try decodeFixture("itinerary-created-item-partial")

        XCTAssertEqual(item.title, "Sagrada Família")
        XCTAssertNil(item.notes)
        XCTAssertNil(item.placeId)
        XCTAssertNil(item.tripDayId)
    }

    private func decodeFixture<T: Decodable>(_ name: String) throws -> T {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try JSONDecoder.bpDecoder.decode(T.self, from: Data(contentsOf: url))
    }
}
