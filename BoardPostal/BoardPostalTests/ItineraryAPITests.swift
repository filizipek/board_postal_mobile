import XCTest
@testable import BoardPostal

@MainActor
final class ItineraryAPITests: XCTestCase {
    private var api: APIClient!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ItineraryURLProtocolStub.self]
        api = APIClient(session: URLSession(configuration: configuration))
    }

    override func tearDown() {
        api = nil
        super.tearDown()
    }

    func testDayUpdateAcceptsNoContent() async throws {
        try await api.updateDay(
            tripId: "10000000-0000-0000-0000-000000000001",
            dayId: "30000000-0000-0000-0000-000000000001",
            body: UpdateDayRequest(title: "Updated", date: nil, orderIndex: nil)
        )
    }

    func testItemUpdateAcceptsNoContentAndReturnsLocalProjection() async throws {
        let items: [TripDayItem] = try decodeFixture("itinerary-items")
        let original = items[1]

        let updated = try await api.updateDayItem(
            tripId: "10000000-0000-0000-0000-000000000001",
            dayId: "30000000-0000-0000-0000-000000000001",
            item: original,
            title: "Metro to the hotel",
            type: original.type,
            notes: "Use the airport line",
            time: "10:30"
        )

        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.title, "Metro to the hotel")
        XCTAssertEqual(updated.notes, "Use the airport line")
        XCTAssertEqual(updated.time, "10:30")
        XCTAssertEqual(updated.type, original.type)
        XCTAssertEqual(updated.orderIndex, original.orderIndex)
    }

    func testNonSuccessUpdateRemainsAnError() async throws {
        do {
            try await api.updateDay(
                tripId: "10000000-0000-0000-0000-000000000001",
                dayId: "30000000-0000-0000-0000-000000000002",
                body: UpdateDayRequest(title: "Updated", date: nil, orderIndex: nil)
            )
            XCTFail("Expected server error")
        } catch APIError.serverError(let status) {
            XCTAssertEqual(status, 500)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testValidationResponseUsesFieldMessages() async throws {
        do {
            let _: TripDayItem = try await api.createDayItem(
                tripId: "10000000-0000-0000-0000-000000000001",
                dayId: "30000000-0000-0000-0000-000000000001",
                body: CreateDayItemRequest(type: "note", title: "", notes: nil, time: "24:00", orderIndex: 0, placeId: nil)
            )
            XCTFail("Expected validation failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("'Title' must not be empty."))
            XCTAssertTrue(error.localizedDescription.contains("Time must be in HH:mm format."))
            XCTAssertFalse(error.localizedDescription == "One or more validation errors occurred.")
        }
    }

    private func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func decodeFixture<T: Decodable>(_ name: String) throws -> T {
        try JSONDecoder.bpDecoder.decode(T.self, from: fixtureData(name))
    }
}

private final class ItineraryURLProtocolStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (status, data) = response(for: request)
            let response = try XCTUnwrap(HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private func response(for request: URLRequest) -> (Int, Data) {
        if request.httpMethod == "POST" {
            let validationJSON = """
            {
              "title": "One or more validation errors occurred.",
              "status": 400,
              "errors": {
                "Title": ["'Title' must not be empty."],
                "Time": ["Time must be in HH:mm format."]
              }
            }
            """
            return (400, Data(validationJSON.utf8))
        }
        if request.url?.path.hasSuffix("30000000-0000-0000-0000-000000000002") == true {
            return (500, Data())
        }
        return (204, Data())
    }
}
