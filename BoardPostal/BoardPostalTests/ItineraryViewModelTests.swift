import XCTest
@testable import BoardPostal

@MainActor
final class ItineraryViewModelTests: XCTestCase {
    func testConcurrentAddItemAcceptsOnlyOneRequestAndAppendsOnce() async throws {
        let day: TripDay = try decodeFixture("itinerary-day")
        let created: TripDayItem = try decodeFixture("itinerary-created-item-partial")
        let api = DelayedItineraryAPI()
        let viewModel = ItineraryViewModel(tripId: "trip-1", days: [day], api: api)

        let first = Task { await viewModel.addItem(to: day, type: "place", title: "First", notes: nil, time: nil) }
        await api.waitForItemRequestCount(1)
        let second = Task { await viewModel.addItem(to: day, type: "note", title: "Second", notes: nil, time: nil) }
        await api.allowScheduling()

        XCTAssertEqual(api.createItemCallCount, 1)
        XCTAssertTrue(viewModel.isSavingItem)

        api.completeItemRequests(with: .success(created))
        let results = await (first.value, second.value)

        XCTAssertEqual(viewModel.days[0].items.count, day.items.count + 1)
        XCTAssertFalse(viewModel.isSavingItem)
        XCTAssertEqual([results.0, results.1].compactMap { $0 }.count, 1)
    }

    func testConcurrentAddDayAcceptsOnlyOneRequestAndAppendsOnce() async throws {
        let created: TripDay = try decodeFixture("itinerary-day")
        let api = DelayedItineraryAPI()
        let viewModel = ItineraryViewModel(tripId: "trip-1", days: [], api: api)

        let first = Task { await viewModel.addDay() }
        await api.waitForDayRequestCount(1)
        let second = Task { await viewModel.addDay() }
        await api.allowScheduling()

        XCTAssertEqual(api.createDayCallCount, 1)
        XCTAssertTrue(viewModel.isAddingDay)

        api.completeDayRequests(with: .success(created))
        _ = await (first.value, second.value)

        XCTAssertEqual(viewModel.days.count, 1)
        XCTAssertFalse(viewModel.isAddingDay)
    }

    func testDayUpdatePreservesItemsAddedWhileRequestIsInFlight() async throws {
        let day: TripDay = try decodeFixture("itinerary-day")
        let items: [TripDayItem] = try decodeFixture("itinerary-items")
        let newerItem = items[3]
        let api = DelayedItineraryAPI()
        let viewModel = ItineraryViewModel(tripId: "trip-1", days: [day], api: api)

        let update = Task { await viewModel.updateDay(day, title: "Updated", date: nil) }
        await api.waitForUpdateDayRequest()
        viewModel.days[0] = TripDay(
            id: day.id,
            tripId: day.tripId,
            dayNumber: day.dayNumber,
            title: day.title,
            date: day.date,
            orderIndex: day.orderIndex,
            items: day.items + [newerItem]
        )

        api.completeDayUpdate(with: .success(()))
        await update.value

        XCTAssertEqual(viewModel.days[0].items.map(\.id), (day.items + [newerItem]).map(\.id))
    }

    func testSuccessfulCreationImmediatelyAddsVisibleItemAndEndsSaving() async throws {
        let day: TripDay = try decodeFixture("itinerary-day")
        let created: TripDayItem = try decodeFixture("itinerary-created-item-partial")
        let api = ItineraryAPIStub(createItemResult: .success(created))
        let viewModel = ItineraryViewModel(tripId: "trip-1", days: [day], api: api)

        let result = await viewModel.addItem(
            to: day,
            type: "place",
            title: try XCTUnwrap(created.title),
            notes: nil,
            time: nil
        )

        XCTAssertNil(result, "A nil result signals that the sheet may dismiss")
        XCTAssertEqual(viewModel.days[0].items.last?.id, created.id)
        XCTAssertEqual(viewModel.days[0].items.last?.title, "Sagrada Família")
        XCTAssertNil(viewModel.error)
        XCTAssertFalse(viewModel.isSavingItem)
    }

    func testFailedCreationDoesNotInsertBlankItemAndEndsSaving() async throws {
        let day: TripDay = try decodeFixture("itinerary-day")
        let api = ItineraryAPIStub(createItemResult: .failure(APIError.validationError("'Title' must not be empty.")))
        let viewModel = ItineraryViewModel(tripId: "trip-1", days: [day], api: api)

        let result = await viewModel.addItem(
            to: day,
            type: "note",
            title: "",
            notes: nil,
            time: nil
        )

        XCTAssertEqual(viewModel.days[0].items.count, day.items.count)
        XCTAssertEqual(result, "'Title' must not be empty.")
        XCTAssertEqual(viewModel.error, "'Title' must not be empty.")
        XCTAssertFalse(viewModel.isSavingItem)
    }

    func testTimedOutCreationEndsSavingAndDoesNotInsertItem() async throws {
        let day: TripDay = try decodeFixture("itinerary-day")
        let api = ItineraryAPIStub(createItemResult: .failure(URLError(.timedOut)))
        let viewModel = ItineraryViewModel(tripId: "trip-1", days: [day], api: api)

        let error = await viewModel.addItem(
            to: day,
            type: "place",
            title: "Slow place",
            notes: nil,
            time: nil
        )

        XCTAssertNotNil(error)
        XCTAssertEqual(viewModel.days[0].items.count, day.items.count)
        XCTAssertFalse(viewModel.isSavingItem)
    }

    func testSuccessfulNoContentDayUpdateUpdatesLocalStateAndEndsSaving() async throws {
        let day: TripDay = try decodeFixture("itinerary-day")
        let viewModel = ItineraryViewModel(tripId: "trip-1", days: [day], api: ItineraryAPIStub())

        await viewModel.updateDay(day, title: "Museum day", date: "2026-04-02")

        XCTAssertEqual(viewModel.days[0].title, "Museum day")
        XCTAssertEqual(viewModel.days[0].date, "2026-04-02")
        XCTAssertFalse(viewModel.isUpdatingDay)
        XCTAssertNil(viewModel.error)
    }

    func testFailedDayUpdatePreservesLocalStateAndEndsSaving() async throws {
        let day: TripDay = try decodeFixture("itinerary-day")
        let api = ItineraryAPIStub(updateDayResult: .failure(APIError.serverError(503)))
        let viewModel = ItineraryViewModel(tripId: "trip-1", days: [day], api: api)

        await viewModel.updateDay(day, title: "Not saved", date: "2026-04-03")

        XCTAssertEqual(viewModel.days[0].title, day.title)
        XCTAssertEqual(viewModel.days[0].date, day.date)
        XCTAssertFalse(viewModel.isUpdatingDay)
        XCTAssertNotNil(viewModel.error)
    }

    func testAddDayLoadingStateEndsAfterSuccessAndFailure() async throws {
        let day: TripDay = try decodeFixture("itinerary-day")
        let successful = ItineraryViewModel(
            tripId: "trip-1",
            days: [],
            api: ItineraryAPIStub(createDayResult: .success(day))
        )
        await successful.addDay()
        XCTAssertFalse(successful.isAddingDay)
        XCTAssertEqual(successful.days.count, 1)

        let failed = ItineraryViewModel(
            tripId: "trip-1",
            days: [],
            api: ItineraryAPIStub(createDayResult: .failure(APIError.serverError(500)))
        )
        await failed.addDay()
        XCTAssertFalse(failed.isAddingDay)
        XCTAssertTrue(failed.days.isEmpty)
        XCTAssertNotNil(failed.error)
    }

    func testItemEditorSaveAndDeleteStatesAreMutuallyExclusive() {
        var state = ItemEditorMutationState.idle

        XCTAssertTrue(state.begin(.saving))
        XCTAssertFalse(state.begin(.deleting))
        XCTAssertEqual(state, .saving)

        state.finish()
        XCTAssertTrue(state.begin(.deleting))
        XCTAssertFalse(state.begin(.saving))
        XCTAssertEqual(state, .deleting)
    }

    private func decodeFixture<T: Decodable>(_ name: String) throws -> T {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try JSONDecoder.bpDecoder.decode(T.self, from: Data(contentsOf: url))
    }
}

@MainActor
private final class DelayedItineraryAPI: ItineraryAPIProviding {
    private(set) var createDayCallCount = 0
    private(set) var createItemCallCount = 0
    private var dayContinuations: [CheckedContinuation<TripDay, Error>] = []
    private var itemContinuations: [CheckedContinuation<TripDayItem, Error>] = []
    private var updateDayContinuation: CheckedContinuation<Void, Error>?

    func createDay(tripId: String, body: CreateDayRequest) async throws -> TripDay {
        createDayCallCount += 1
        return try await withCheckedThrowingContinuation { dayContinuations.append($0) }
    }

    func updateDay(tripId: String, dayId: String, body: UpdateDayRequest) async throws {
        try await withCheckedThrowingContinuation { updateDayContinuation = $0 }
    }

    func createDayItem(tripId: String, dayId: String, body: CreateDayItemRequest) async throws -> TripDayItem {
        createItemCallCount += 1
        return try await withCheckedThrowingContinuation { itemContinuations.append($0) }
    }

    func waitForDayRequestCount(_ count: Int) async {
        while createDayCallCount < count { await Task.yield() }
    }

    func waitForItemRequestCount(_ count: Int) async {
        while createItemCallCount < count { await Task.yield() }
    }

    func waitForUpdateDayRequest() async {
        while updateDayContinuation == nil { await Task.yield() }
    }

    func allowScheduling() async {
        for _ in 0..<10 { await Task.yield() }
    }

    func completeDayRequests(with result: Result<TripDay, Error>) {
        let continuations = dayContinuations
        dayContinuations.removeAll()
        continuations.forEach { $0.resume(with: result) }
    }

    func completeItemRequests(with result: Result<TripDayItem, Error>) {
        let continuations = itemContinuations
        itemContinuations.removeAll()
        continuations.forEach { $0.resume(with: result) }
    }

    func completeDayUpdate(with result: Result<Void, Error>) {
        updateDayContinuation?.resume(with: result)
        updateDayContinuation = nil
    }
}

@MainActor
private final class ItineraryAPIStub: ItineraryAPIProviding {
    let createDayResult: Result<TripDay, Error>
    let updateDayResult: Result<Void, Error>
    let createItemResult: Result<TripDayItem, Error>

    init(
        createDayResult: Result<TripDay, Error> = .failure(APIError.serverError(500)),
        updateDayResult: Result<Void, Error> = .success(()),
        createItemResult: Result<TripDayItem, Error> = .failure(APIError.serverError(500))
    ) {
        self.createDayResult = createDayResult
        self.updateDayResult = updateDayResult
        self.createItemResult = createItemResult
    }

    func createDay(tripId: String, body: CreateDayRequest) async throws -> TripDay {
        try createDayResult.get()
    }

    func updateDay(tripId: String, dayId: String, body: UpdateDayRequest) async throws {
        try updateDayResult.get()
    }

    func createDayItem(tripId: String, dayId: String, body: CreateDayItemRequest) async throws -> TripDayItem {
        try createItemResult.get()
    }
}
