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

    func testDecodesCanonicalProductionResponseWithNullableAndOmittedFields() throws {
        let days: [TripDay] = try decodeFixture("itinerary-production-two-days")

        XCTAssertEqual(days.map(\.dayNumber), [1, 2])
        XCTAssertEqual(days[0].items.map(\.itemType), [.place, .transport, .accommodation, .note])
        XCTAssertEqual(days[0].items[1].title as String?, nil)
        XCTAssertNil(days[0].items[1].notes)
        XCTAssertNil(days[0].items[2].time)
        XCTAssertTrue(days[1].items.isEmpty)
    }

    func testDecodesPartialCreatedDayWithEmptyItems() throws {
        let day: TripDay = try decodeFixture("itinerary-created-day-partial")

        XCTAssertEqual(day.dayNumber, 3)
        XCTAssertTrue(day.items.isEmpty)
        XCTAssertNil(day.tripId)
    }

    func testSanitizedDiagnosticIdentifiesModelAndCodingPathWithoutPayload() throws {
        let data = Data(#"[{"id":"day-1","dayNumber":1,"title":null,"date":null,"orderIndex":0,"items":[{"id":"item-1","type":"note","title":7,"orderIndex":0}]}]"#.utf8)

        do {
            let _: [TripDay] = try JSONDecoder.bpDecoder.decode([TripDay].self, from: data)
            XCTFail("Expected decoding failure")
        } catch {
            let diagnostic = DecodingDiagnostics.sanitizedDescription(for: error, model: [TripDay].self)
            XCTAssertTrue(diagnostic.contains("TripDay"))
            XCTAssertTrue(diagnostic.contains("[0].items[0].title"))
            XCTAssertFalse(diagnostic.contains("item-1"))
            XCTAssertFalse(diagnostic.contains("day-1"))
        }

        XCTAssertEqual(
            APIError.decodingError("internal path").localizedDescription,
            "We couldn't load this data. Please try again."
        )
    }

    private func decodeFixture<T: Decodable>(_ name: String) throws -> T {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try JSONDecoder.bpDecoder.decode(T.self, from: Data(contentsOf: url))
    }
}
