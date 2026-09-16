import XCTest
@testable import BoardPostal

@MainActor
final class ItineraryViewModelTests: XCTestCase {
    func testInvalidItemInputsNeverReachAPI() async throws {
        let day: TripDay = try decodeFixture("itinerary-day")
        let api = ItineraryAPIStub()
        let vm = ItineraryViewModel(tripId: "trip-1", days: [day], api: api)
        for time in ["9:00", "09.30", "24:00", "23:60", "text"] {
            let error = await vm.addItem(to: day, type: "note", title: "Note", notes: nil, time: time)
            XCTAssertNotNil(error)
            XCTAssertNil(api.lastCreateItemBody)
        }
        for input in [(String(repeating: "x", count: 121), nil as String?), ("Note", String(repeating: "x", count: 501))] {
            let error = await vm.addItem(to: day, type: "note", title: input.0, notes: input.1, time: nil)
            XCTAssertNotNil(error)
            XCTAssertNil(api.lastCreateItemBody)
        }
    }

    func testWhitespaceOptionalInputsAreOmitted() async throws {
        let day: TripDay = try decodeFixture("itinerary-day")
        let created: TripDayItem = try decodeFixture("itinerary-created-item-partial")
        let api = ItineraryAPIStub(createItemResult: .success(created))
        let vm = ItineraryViewModel(tripId: "trip-1", days: [day], api: api)
        _ = await vm.addItem(to: day, type: "note", title: "Note", notes: " \n ", time: " \n ")
        XCTAssertNil(api.lastCreateItemBody?.notes)
        XCTAssertNil(api.lastCreateItemBody?.time)
    }

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
        _ = await update.value

        XCTAssertEqual(viewModel.days[0].items.map(\.id), (day.items + [newerItem]).map(\.id))
    }

    func testDayUpdatePreventsOverlappingItemCreation() async throws {
        let day: TripDay = try decodeFixture("itinerary-day")
        let api = DelayedItineraryAPI()
        let viewModel = ItineraryViewModel(tripId: "trip-1", days: [day], api: api)

        let update = Task { await viewModel.updateDay(day, title: "Updated", date: nil) }
        await api.waitForUpdateDayRequest()
        let add = Task { await viewModel.addItem(
            to: day,
            type: "note",
            title: "Must not overlap",
            notes: nil,
            time: nil
        ) }
        await api.allowScheduling()

        XCTAssertEqual(api.createItemCallCount, 0)
        if api.createItemCallCount > 0 {
            let created: TripDayItem = try decodeFixture("itinerary-created-item-partial")
            api.completeItemRequests(with: .success(created))
        }
        let addResult = await add.value
        XCTAssertNotNil(addResult)
        api.completeDayUpdate(with: .success(()))
        _ = await update.value
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
        XCTAssertEqual(api.lastCreateItemBody?.type, "place")
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
            title: "Rejected by server",
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

    func testDoubleDeleteDayIssuesOneRequestAndRemovesOnce() async throws {
        let day: TripDay = try decodeFixture("itinerary-day")
        let api = DelayedItineraryAPI()
        let viewModel = ItineraryViewModel(tripId: "trip-1", days: [day], api: api)

        let first = Task { await viewModel.deleteDay(id: day.id) }
        await api.waitForDeleteDayRequest()
        let second = await viewModel.deleteDay(id: day.id)

        XCTAssertEqual(api.deleteDayCallCount, 1)
        XCTAssertNotNil(second)
        api.completeDayDelete(with: .success(()))
        let firstResult = await first.value
        XCTAssertNil(firstResult)
        XCTAssertTrue(viewModel.days.isEmpty)
    }

    func testDoubleDeleteItemIssuesOneRequestAndRemovesOnlyMatchingItem() async throws {
        let day: TripDay = try decodeFixture("itinerary-day")
        let api = DelayedItineraryAPI()
        let viewModel = ItineraryViewModel(tripId: "trip-1", days: [day], api: api)
        let itemId = try XCTUnwrap(day.items.first?.id)

        let first = Task { await viewModel.deleteItem(dayId: day.id, itemId: itemId) }
        await api.waitForDeleteItemRequest()
        let second = await viewModel.deleteItem(dayId: day.id, itemId: itemId)

        XCTAssertEqual(api.deleteItemCallCount, 1)
        XCTAssertNotNil(second)
        api.completeItemDelete(with: .success(()))
        let firstResult = await first.value
        XCTAssertNil(firstResult)
        XCTAssertFalse(viewModel.days[0].items.contains { $0.id == itemId })
        XCTAssertEqual(viewModel.days[0].items.count, day.items.count - 1)
    }

    func testFailedDeleteAndReorderPreserveExactState() async throws {
        let day: TripDay = try decodeFixture("itinerary-day")
        let api = ItineraryAPIStub(
            deleteItemResult: .failure(APIError.serverError(503)),
            reorderItemResult: .failure(APIError.serverError(503))
        )
        let viewModel = ItineraryViewModel(tripId: "trip-1", days: [day], api: api)
        let originalItems = itemSnapshot(day.items)
        let originalIds = day.items.map(\.id)
        let itemId = try XCTUnwrap(originalIds.first)

        let deleteError = await viewModel.deleteItem(dayId: day.id, itemId: itemId)
        XCTAssertNotNil(deleteError)
        XCTAssertEqual(itemSnapshot(viewModel.days[0].items), originalItems)
        let reorderError = await viewModel.reorderItems(
            dayId: day.id, orderedIds: Array(originalIds.reversed()))
        XCTAssertNotNil(reorderError)
        XCTAssertEqual(itemSnapshot(viewModel.days[0].items), originalItems)
        XCTAssertNil(viewModel.activeMutation)
    }

    func testUnknownItemIDIsForwardedForBackendAuthority() async throws {
        let day: TripDay = try decodeFixture("itinerary-day")
        let api = ItineraryAPIStub()
        let viewModel = ItineraryViewModel(tripId: "trip-1", days: [day], api: api)
        let itemId = try XCTUnwrap(day.items.first?.id)
        let requested = ["40000000-0000-0000-0000-000000000999", itemId]

        let error = await viewModel.reorderItems(
            dayId: day.id, orderedIds: requested)

        XCTAssertNil(error)
        XCTAssertEqual(api.reorderItemCallCount, 1)
        XCTAssertEqual(api.lastReorderItemIds, requested)
        XCTAssertEqual(viewModel.days[0].items.first { $0.id == itemId }?.orderIndex, 1)
    }

    func testCancellationClearsMutationAndAllowsRetry() async throws {
        let day: TripDay = try decodeFixture("itinerary-day")
        let api = ItineraryAPIStub(
            updateDayResult: .failure(CancellationError())
        )
        let viewModel = ItineraryViewModel(tripId: "trip-1", days: [day], api: api)

        let cancellationError = await viewModel.updateDay(
            day, title: "Cancelled", date: nil)
        XCTAssertNotNil(cancellationError)
        XCTAssertNil(viewModel.activeMutation)
        XCTAssertEqual(viewModel.days[0].title, day.title)
    }

    func testSuccessfulItemUpdateReplacesOnlyMatchingCurrentItem() async throws {
        let day: TripDay = try decodeFixture("itinerary-day")
        let item = try XCTUnwrap(day.items.first)
        let updated = TripDayItem(
            id: item.id, tripDayId: item.tripDayId, type: item.type,
            title: "Updated item", notes: item.notes, time: item.time,
            orderIndex: item.orderIndex, placeId: item.placeId
        )
        let api = ItineraryAPIStub(updateItemResult: .success(updated))
        let viewModel = ItineraryViewModel(tripId: "trip-1", days: [day], api: api)
        let untouchedIds = Array(day.items.dropFirst().map(\.id))

        let result = await viewModel.updateItem(
            dayId: day.id, itemId: item.id, title: "Updated item",
            notes: item.notes, time: item.time)

        XCTAssertNil(result)
        XCTAssertEqual(viewModel.days[0].items.first?.title, "Updated item")
        XCTAssertEqual(Array(viewModel.days[0].items.dropFirst().map(\.id)), untouchedIds)
    }

    func testFailedItemUpdatePreservesEntirePreviousItem() async throws {
        let day: TripDay = try decodeFixture("itinerary-day")
        let item = try XCTUnwrap(day.items.first)
        let api = ItineraryAPIStub(
            updateItemResult: .failure(APIError.serverError(503)))
        let viewModel = ItineraryViewModel(tripId: "trip-1", days: [day], api: api)
        let original = itemSnapshot(day.items)

        let error = await viewModel.updateItem(
            dayId: day.id, itemId: item.id, title: "Not saved",
            notes: "Not saved", time: "12:00")

        XCTAssertNotNil(error)
        XCTAssertEqual(itemSnapshot(viewModel.days[0].items), original)
        XCTAssertNil(viewModel.activeMutation)
    }

    func testReorderCannotOverlapDayUpdate() async throws {
        let day: TripDay = try decodeFixture("itinerary-day")
        let api = DelayedItineraryAPI()
        let viewModel = ItineraryViewModel(tripId: "trip-1", days: [day], api: api)

        let update = Task { await viewModel.updateDay(day, title: "Updating", date: nil) }
        await api.waitForUpdateDayRequest()
        let reorderError = await viewModel.reorderItems(
            dayId: day.id, orderedIds: day.items.map(\.id))

        XCTAssertNotNil(reorderError)
        XCTAssertEqual(api.reorderItemCallCount, 0)
        api.completeDayUpdate(with: .success(()))
        _ = await update.value
    }

    func testSuccessfulDayReorderUpdatesPersistedIndexesAndVisibleOrder() async throws {
        let fixture: [TripDay] = try decodeFixture("itinerary-production-two-days")
        let api = ItineraryAPIStub()
        let viewModel = ItineraryViewModel(tripId: "trip-1", days: fixture, api: api)
        let requested = fixture.map(\.id).reversed()

        let error = await viewModel.reorderDays(Array(requested))

        XCTAssertNil(error)
        XCTAssertEqual(api.reorderDayCallCount, 1)
        XCTAssertEqual(viewModel.sortedDays.map(\.id), Array(requested))
        XCTAssertEqual(viewModel.sortedDays.map(\.orderIndex), [0, 1])
        XCTAssertEqual(viewModel.sortedDays.map(\.dayNumber), [2, 1])
    }

    func testSuccessfulPartialItemReorderPreservesUnlistedIndexes() async throws {
        let day: TripDay = try decodeFixture("itinerary-day")
        let allItems: [TripDayItem] = try decodeFixture("itinerary-items")
        let populatedDay = TripDay(
            id: day.id, tripId: day.tripId, dayNumber: day.dayNumber,
            title: day.title, date: day.date, orderIndex: day.orderIndex,
            items: allItems)
        let api = ItineraryAPIStub()
        let viewModel = ItineraryViewModel(
            tripId: "trip-1", days: [populatedDay], api: api)
        let requested = [allItems[3].id, allItems[1].id]

        let error = await viewModel.reorderItems(
            dayId: day.id, orderedIds: requested)

        XCTAssertNil(error)
        XCTAssertEqual(api.reorderItemCallCount, 1)
        XCTAssertEqual(api.lastReorderItemIds, requested)
        XCTAssertEqual(viewModel.days[0].items.first { $0.id == allItems[3].id }?.orderIndex, 0)
        XCTAssertEqual(viewModel.days[0].items.first { $0.id == allItems[1].id }?.orderIndex, 1)
        XCTAssertEqual(viewModel.days[0].items.first { $0.id == allItems[0].id }?.orderIndex, 0)
        XCTAssertEqual(viewModel.days[0].items.first { $0.id == allItems[2].id }?.orderIndex, 2)
        XCTAssertEqual(visibleItemIds(viewModel.days[0]), [allItems[0].id, allItems[3].id, allItems[1].id, allItems[2].id])
    }

    func testDuplicateItemIDsUseLastBackendPosition() async throws {
        let day: TripDay = try decodeFixture("itinerary-day")
        let allItems: [TripDayItem] = try decodeFixture("itinerary-items")
        let populatedDay = TripDay(
            id: day.id, tripId: day.tripId, dayNumber: day.dayNumber,
            title: day.title, date: day.date, orderIndex: day.orderIndex,
            items: allItems)
        let api = ItineraryAPIStub()
        let viewModel = ItineraryViewModel(
            tripId: "trip-1", days: [populatedDay], api: api)
        let requested = [allItems[3].id, allItems[1].id, allItems[3].id]

        let error = await viewModel.reorderItems(
            dayId: day.id, orderedIds: requested)

        XCTAssertNil(error)
        XCTAssertEqual(api.reorderItemCallCount, 1)
        XCTAssertEqual(api.lastReorderItemIds, requested)
        XCTAssertEqual(viewModel.days[0].items.first { $0.id == allItems[3].id }?.orderIndex, 2)
        XCTAssertEqual(viewModel.days[0].items.first { $0.id == allItems[1].id }?.orderIndex, 1)
    }

    func testEmptyReorderIsRejectedBeforeRequest() async throws {
        let day: TripDay = try decodeFixture("itinerary-day")
        let api = ItineraryAPIStub()
        let viewModel = ItineraryViewModel(tripId: "trip-1", days: [day], api: api)

        let dayError = await viewModel.reorderDays([])
        let itemError = await viewModel.reorderItems(
            dayId: day.id, orderedIds: [])
        XCTAssertNotNil(dayError)
        XCTAssertNotNil(itemError)
        XCTAssertEqual(api.reorderDayCallCount, 0)
        XCTAssertEqual(api.reorderItemCallCount, 0)
    }

    func testDuplicateDayIDsUseLastBackendPosition() async throws {
        let fixture: [TripDay] = try decodeFixture("itinerary-production-two-days")
        let api = ItineraryAPIStub()
        let viewModel = ItineraryViewModel(tripId: "trip-1", days: fixture, api: api)
        let repeatedId = fixture[1].id

        let error = await viewModel.reorderDays([repeatedId, repeatedId])

        XCTAssertNil(error)
        XCTAssertEqual(api.reorderDayCallCount, 1)
        XCTAssertEqual(api.lastReorderDayIds, [repeatedId, repeatedId])
        XCTAssertEqual(viewModel.days.first { $0.id == repeatedId }?.orderIndex, 1)
        XCTAssertEqual(viewModel.days.first { $0.id == fixture[0].id }?.orderIndex, 0)
    }

    func testFailedDayReorderPreservesExactState() async throws {
        let fixture: [TripDay] = try decodeFixture("itinerary-production-two-days")
        let api = ItineraryAPIStub(
            reorderDayResult: .failure(APIError.serverError(503)))
        let viewModel = ItineraryViewModel(tripId: "trip-1", days: fixture, api: api)
        let original = viewModel.days.map { ($0.id, $0.dayNumber, $0.orderIndex) }

        let error = await viewModel.reorderDays(Array(fixture.map(\.id).reversed()))

        XCTAssertNotNil(error)
        XCTAssertEqual(
            viewModel.days.map { "\($0.id)|\($0.dayNumber)|\($0.orderIndex)" },
            original.map { "\($0.0)|\($0.1)|\($0.2)" })
        XCTAssertNil(viewModel.activeMutation)
    }

    private func visibleItemIds(_ day: TripDay) -> [String] {
        day.items.enumerated().sorted {
            if $0.element.orderIndex != $1.element.orderIndex {
                return $0.element.orderIndex < $1.element.orderIndex
            }
            return $0.offset < $1.offset
        }.map(\.element.id)
    }

    private func itemSnapshot(_ items: [TripDayItem]) -> [String] {
        items.map {
            [$0.id, $0.tripDayId, $0.type, $0.title, $0.notes, $0.time,
             String($0.orderIndex), $0.placeId]
                .map { $0 ?? "<nil>" }
                .joined(separator: "|")
        }
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
    private var deleteDayContinuation: CheckedContinuation<Void, Error>?
    private var deleteItemContinuation: CheckedContinuation<Void, Error>?
    private(set) var deleteDayCallCount = 0
    private(set) var deleteItemCallCount = 0
    private(set) var reorderItemCallCount = 0
    private(set) var reorderDayCallCount = 0

    func updateDayItem(tripId: String, dayId: String, item: TripDayItem, title: String, notes: String?, time: String?) async throws -> TripDayItem { item }
    func deleteDay(tripId: String, dayId: String) async throws {
        deleteDayCallCount += 1
        try await withCheckedThrowingContinuation { deleteDayContinuation = $0 }
    }
    func deleteDayItem(tripId: String, dayId: String, itemId: String) async throws {
        deleteItemCallCount += 1
        try await withCheckedThrowingContinuation { deleteItemContinuation = $0 }
    }
    func reorderDays(tripId: String, orderedIds: [String]) async throws {
        reorderDayCallCount += 1
    }
    func reorderDayItems(tripId: String, dayId: String, orderedIds: [String]) async throws {
        reorderItemCallCount += 1
    }

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

    func waitForDeleteDayRequest() async {
        while deleteDayContinuation == nil { await Task.yield() }
    }

    func waitForDeleteItemRequest() async {
        while deleteItemContinuation == nil { await Task.yield() }
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

    func completeDayDelete(with result: Result<Void, Error>) {
        deleteDayContinuation?.resume(with: result)
        deleteDayContinuation = nil
    }

    func completeItemDelete(with result: Result<Void, Error>) {
        deleteItemContinuation?.resume(with: result)
        deleteItemContinuation = nil
    }
}

@MainActor
private final class ItineraryAPIStub: ItineraryAPIProviding {
    let createDayResult: Result<TripDay, Error>
    let updateDayResult: Result<Void, Error>
    let createItemResult: Result<TripDayItem, Error>
    let deleteItemResult: Result<Void, Error>
    let reorderItemResult: Result<Void, Error>
    let updateItemResult: Result<TripDayItem, Error>?
    let reorderDayResult: Result<Void, Error>
    private(set) var reorderDayCallCount = 0
    private(set) var reorderItemCallCount = 0
    private(set) var lastReorderDayIds: [String]?
    private(set) var lastReorderItemIds: [String]?
    private(set) var lastCreateItemBody: CreateDayItemRequest?

    init(
        createDayResult: Result<TripDay, Error> = .failure(APIError.serverError(500)),
        updateDayResult: Result<Void, Error> = .success(()),
        createItemResult: Result<TripDayItem, Error> = .failure(APIError.serverError(500)),
        deleteItemResult: Result<Void, Error> = .success(()),
        reorderItemResult: Result<Void, Error> = .success(()),
        updateItemResult: Result<TripDayItem, Error>? = nil,
        reorderDayResult: Result<Void, Error> = .success(())
    ) {
        self.createDayResult = createDayResult
        self.updateDayResult = updateDayResult
        self.createItemResult = createItemResult
        self.deleteItemResult = deleteItemResult
        self.reorderItemResult = reorderItemResult
        self.updateItemResult = updateItemResult
        self.reorderDayResult = reorderDayResult
    }

    func createDay(tripId: String, body: CreateDayRequest) async throws -> TripDay {
        try createDayResult.get()
    }

    func updateDay(tripId: String, dayId: String, body: UpdateDayRequest) async throws {
        try updateDayResult.get()
    }

    func createDayItem(tripId: String, dayId: String, body: CreateDayItemRequest) async throws -> TripDayItem {
        lastCreateItemBody = body
        return try createItemResult.get()
    }

    func updateDayItem(tripId: String, dayId: String, item: TripDayItem, title: String, notes: String?, time: String?) async throws -> TripDayItem {
        try updateItemResult?.get() ?? item
    }
    func deleteDay(tripId: String, dayId: String) async throws {}
    func deleteDayItem(tripId: String, dayId: String, itemId: String) async throws { try deleteItemResult.get() }
    func reorderDays(tripId: String, orderedIds: [String]) async throws {
        reorderDayCallCount += 1
        lastReorderDayIds = orderedIds
        try reorderDayResult.get()
    }
    func reorderDayItems(tripId: String, dayId: String, orderedIds: [String]) async throws {
        reorderItemCallCount += 1
        lastReorderItemIds = orderedIds
        try reorderItemResult.get()
    }
}
