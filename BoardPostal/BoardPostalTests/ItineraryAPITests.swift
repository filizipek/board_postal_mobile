import XCTest
@testable import BoardPostal

@MainActor
final class ItineraryAPITests: XCTestCase {
    private var api: APIClient!

    override func setUp() {
        super.setUp()
        ItineraryURLProtocolStub.requests = []
        ItineraryURLProtocolStub.overrideResponse = nil
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

    func testValidAddItemSendsOneExactRequestForEveryType() async throws {
        let day: TripDay = try decodeFixture("itinerary-day")
        for (index, type) in ["place", "transport", "accommodation", "note"].enumerated() {
            ItineraryURLProtocolStub.requests = []
            ItineraryURLProtocolStub.overrideResponse = (201, Data(#"{"id":"created","type":"note","title":"Server title","time":"09:00","orderIndex":7}"#.utf8))
            let vm = ItineraryViewModel(tripId: "trip-1", days: [day], api: api)
            let time = index.isMultiple(of: 2) ? "09:00" : "23:59"
            let error = await vm.addItem(to: day, type: type, title: "Note", notes: "Details", time: time)
            XCTAssertNil(error)
            let request = try XCTUnwrap(ItineraryURLProtocolStub.requests.only)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/trips/trip-1/days/\(day.id)/items")
            let body = try decodedBody(request)
            XCTAssertEqual(Set(body.keys), Set(["type", "title", "notes", "time", "orderIndex"]))
            XCTAssertEqual(body["type"] as? String, type)
            XCTAssertEqual(body["title"] as? String, "Note")
            XCTAssertEqual(body["notes"] as? String, "Details")
            XCTAssertEqual(body["time"] as? String, time)
            XCTAssertEqual(body["orderIndex"] as? Int, (day.items.map(\.orderIndex).max() ?? -1) + 1)
            XCTAssertEqual(vm.days[0].items.last?.notes, "Details")
            XCTAssertEqual(vm.days[0].items.last?.title, "Server title")
            XCTAssertEqual(vm.days[0].items.last?.orderIndex, 7)
        }
    }

    func testInvalidFormInputsExposeInlineErrorWithoutRequest() async throws {
        let day: TripDay = try decodeFixture("itinerary-day")
        let vm = ItineraryViewModel(tripId: "trip-1", days: [day], api: api)
        let form = AddDayItemFormState()
        form.title = "Note"
        for time in ["9:00", "09.30", "24:00", "09:60", "٠٩:٠٠"] {
            form.time = time
            let canDismiss = await form.save(day: day, viewModel: vm)
            XCTAssertFalse(canDismiss)
            XCTAssertTrue(form.saveError?.contains("HH:mm") == true)
            XCTAssertEqual(form.time, time)
            XCTAssertTrue(ItineraryURLProtocolStub.requests.isEmpty)
        }
        form.time = ""
        for title in [" \n ", String(repeating: "x", count: 121), String(repeating: "😀", count: 61)] {
            form.title = title
            let canDismiss = await form.save(day: day, viewModel: vm)
            XCTAssertFalse(canDismiss)
            XCTAssertTrue(form.saveError?.contains("Title") == true)
            XCTAssertTrue(ItineraryURLProtocolStub.requests.isEmpty)
        }
        form.title = "Note"
        form.notes = String(repeating: "x", count: 501)
        let canDismiss = await form.save(day: day, viewModel: vm)
        XCTAssertFalse(canDismiss)
        XCTAssertTrue(form.saveError?.contains("Notes") == true)
        XCTAssertTrue(ItineraryURLProtocolStub.requests.isEmpty)
    }

    func testEmptyOptionalsAreNotEncodedAndTimeWhitespaceIsNormalized() async throws {
        let day: TripDay = try decodeFixture("itinerary-day")
        ItineraryURLProtocolStub.overrideResponse = (201, Data(#"{"id":"created","type":"note","title":"Note","time":null,"orderIndex":0}"#.utf8))
        for time in [" \n ", " 09:00 "] {
            ItineraryURLProtocolStub.requests = []
            let vm = ItineraryViewModel(tripId: "trip-1", days: [day], api: api)
            _ = await vm.addItem(to: day, type: "note", title: "Note", notes: " \n ", time: time)
            let body = try decodedBody(XCTUnwrap(ItineraryURLProtocolStub.requests.only))
            XCTAssertNil(body["notes"])
            XCTAssertNil(body["placeId"])
            XCTAssertEqual(body["time"] as? String, time.contains("09:00") ? "09:00" : nil)
        }
    }

    func testCreationRetainsOmittedOptionalsButHonorsReturnedValuesAndNulls() async throws {
        let body = CreateDayItemRequest(type: "place", title: "Submitted", notes: "Submitted notes", time: nil, orderIndex: 0, placeId: "place-1")
        for optionalJSON in ["", #", "notes":null,"placeId":null"#, #", "notes":"Server notes","placeId":"server-place""#] {
            ItineraryURLProtocolStub.overrideResponse = (201, Data((#"{"id":"server-id","type":"place","title":"Server title","time":null,"orderIndex":4"# + optionalJSON + "}").utf8))
            let item = try await api.createDayItem(tripId: "trip-1", dayId: "day-1", body: body)
            XCTAssertEqual(item.id, "server-id")
            XCTAssertEqual(item.title, "Server title")
            XCTAssertEqual(item.orderIndex, 4)
            XCTAssertEqual(item.notes, optionalJSON.isEmpty ? "Submitted notes" : (optionalJSON.contains("Server notes") ? "Server notes" : nil))
            XCTAssertEqual(item.placeId, optionalJSON.isEmpty ? "place-1" : (optionalJSON.contains("server-place") ? "server-place" : nil))
        }
    }

    func testBackendFailurePreservesFormAndRetryCanDismissOnlyAfterSuccess() async throws {
        let day: TripDay = try decodeFixture("itinerary-day")
        let vm = ItineraryViewModel(tripId: "trip-1", days: [day], api: api)
        let form = AddDayItemFormState()
        form.selectedType = "transport"
        form.title = "Train"
        form.notes = "Keep details"
        form.time = "09:00"
        let failed = await form.save(day: day, viewModel: vm)
        XCTAssertFalse(failed, "The sheet must remain open")
        XCTAssertTrue(form.saveError?.contains("Time must be in HH:mm format.") == true)
        XCTAssertEqual(form.title, "Train")
        XCTAssertEqual(form.notes, "Keep details")
        XCTAssertEqual(form.time, "09:00")
        XCTAssertEqual(form.selectedType, "transport")
        XCTAssertEqual(vm.days[0].items.count, day.items.count)
        XCTAssertNil(vm.activeMutation)
        ItineraryURLProtocolStub.overrideResponse = (201, Data(#"{"id":"created","type":"transport","title":"Train","time":"09:00","orderIndex":0}"#.utf8))
        let succeeded = await form.save(day: day, viewModel: vm)
        XCTAssertTrue(succeeded)
        XCTAssertNil(form.saveError)
        XCTAssertEqual(ItineraryURLProtocolStub.requests.count, 2)
        XCTAssertEqual(vm.days[0].items.last?.notes, "Keep details")
    }

    func testItemUpdateAcceptsNoContentAndReturnsLocalProjection() async throws {
        let items: [TripDayItem] = try decodeFixture("itinerary-items")
        let original = items[1]

        let updated = try await api.updateDayItem(
            tripId: "10000000-0000-0000-0000-000000000001",
            dayId: "30000000-0000-0000-0000-000000000001",
            item: original,
            title: "Metro to the hotel",
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

    func testItemCreationStillSendsSelectedType() async throws {
        do {
            let _: TripDayItem = try await api.createDayItem(
                tripId: "10000000-0000-0000-0000-000000000001",
                dayId: "30000000-0000-0000-0000-000000000001",
                body: CreateDayItemRequest(
                    type: "transport", title: "Train", notes: nil,
                    time: "08:30", orderIndex: 2, placeId: nil))
            XCTFail("Expected stubbed validation response")
        } catch {}

        let request = try XCTUnwrap(ItineraryURLProtocolStub.requests.only)
        let body = try decodedBody(request)
        XCTAssertEqual(body["type"] as? String, "transport")
    }

    func testItemUpdateBodyContainsOnlyBackendSupportedFields() async throws {
        let items: [TripDayItem] = try decodeFixture("itinerary-items")
        let original = items[1]

        _ = try await api.updateDayItem(
            tripId: "10000000-0000-0000-0000-000000000001",
            dayId: "30000000-0000-0000-0000-000000000001",
            item: original,
            title: "Updated title",
            notes: "Updated notes",
            time: "11:45")

        let request = try XCTUnwrap(ItineraryURLProtocolStub.requests.only)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(
            Set(try decodedBody(request).keys),
            Set(["title", "notes", "time"]))
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

    func testDayReorderSendsExactPutRouteAndBodyOnce() async throws {
        let tripId = "10000000-0000-0000-0000-000000000001"
        let orderedIds = [
            "30000000-0000-0000-0000-000000000002",
            "30000000-0000-0000-0000-000000000001"
        ]

        try await api.reorderDays(tripId: tripId, orderedIds: orderedIds)

        let request = try XCTUnwrap(ItineraryURLProtocolStub.requests.only)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/api/trips/\(tripId)/days/reorder")
        XCTAssertEqual(try decodedOrderedIds(request), orderedIds)
    }

    func testItemReorderSendsExactPutRouteAndBodyOnce() async throws {
        let tripId = "10000000-0000-0000-0000-000000000001"
        let dayId = "30000000-0000-0000-0000-000000000001"
        let orderedIds = [
            "40000000-0000-0000-0000-000000000002",
            "40000000-0000-0000-0000-000000000001"
        ]

        try await api.reorderDayItems(
            tripId: tripId, dayId: dayId, orderedIds: orderedIds)

        let request = try XCTUnwrap(ItineraryURLProtocolStub.requests.only)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(
            request.url?.path,
            "/api/trips/\(tripId)/days/\(dayId)/items/reorder")
        XCTAssertEqual(try decodedOrderedIds(request), orderedIds)
    }

    private func decodedOrderedIds(_ request: URLRequest) throws -> [String] {
        let object = try decodedBody(request)
        return try XCTUnwrap(object["orderedIds"] as? [String])
    }

    private func decodedBody(_ request: URLRequest) throws -> [String: Any] {
        let body = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any])
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
    static var overrideResponse: (Int, Data)?
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            var recordedRequest = request
            if recordedRequest.httpBody == nil,
               let stream = recordedRequest.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var body = Data()
                var buffer = [UInt8](repeating: 0, count: 1_024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count > 0 else { break }
                    body.append(buffer, count: count)
                }
                recordedRequest.httpBody = body
            }
            Self.requests.append(recordedRequest)
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
        if let response = Self.overrideResponse { return response }
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

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
