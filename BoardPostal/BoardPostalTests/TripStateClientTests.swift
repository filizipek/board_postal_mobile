import XCTest
@testable import BoardPostal

@MainActor
final class TripStateClientTests: XCTestCase {
    func testDecodesLifecycleAndVisibilityIndependently() throws {
        let trip = try JSONDecoder.bpDecoder.decode(Trip.self, from: Data(tripJSON.utf8))

        XCTAssertTrue(trip.isDraft)
        XCTAssertEqual(trip.visibility, "private")
    }

    func testPublishSuccessUpdatesLocalStateAfterResponse() async {
        let original = makeTrip(isDraft: true, visibility: "private")
        let api = TripSettingsAPIStub(result: .success(makeTrip(isDraft: false, visibility: "private")))
        var callback: Trip?
        let viewModel = EditTripViewModel(trip: original, api: api) { callback = $0 }

        await viewModel.changeState(.publishing)

        XCTAssertFalse(viewModel.isDraft)
        XCTAssertEqual(viewModel.visibility, "private")
        XCTAssertFalse(callback?.isDraft ?? true)
        XCTAssertNil(viewModel.saveError)
    }

    func testVisibilitySuccessUpdatesLocalStateAfterResponse() async {
        let original = makeTrip(isDraft: false, visibility: "private")
        let api = TripSettingsAPIStub(result: .success(makeTrip(isDraft: false, visibility: "public")))
        var callback: Trip?
        let viewModel = EditTripViewModel(trip: original, api: api) { callback = $0 }

        await viewModel.changeState(.makingPublic)

        XCTAssertEqual(viewModel.visibility, "public")
        XCTAssertEqual(callback?.visibility, "public")
        XCTAssertNil(viewModel.saveError)
    }

    func testPublishFailurePreservesDraftAndDisplaysSpecificValidationMessage() async {
        let original = makeTrip(isDraft: true, visibility: "private")
        let message = "Trip cannot be published until required fields are complete."
        let api = TripSettingsAPIStub(result: .failure(APIError.badRequest(message)))
        var callbackCount = 0
        let viewModel = EditTripViewModel(trip: original, api: api) { _ in callbackCount += 1 }

        await viewModel.changeState(.publishing)

        XCTAssertTrue(viewModel.isDraft)
        XCTAssertEqual(viewModel.visibility, "private")
        XCTAssertEqual(viewModel.saveError, message)
        XCTAssertEqual(callbackCount, 0)
        XCTAssertNil(viewModel.activeTransition)
    }

    func testFailedVisibilityTransitionPreservesDisplayedStateAndSpecificConflict() async {
        let original = makeTrip(isDraft: false, visibility: "public")
        let api = TripSettingsAPIStub(result: .failure(APIError.conflict(
            "Cannot make this trip private while its Explore submission is pending. Explore withdrawal or removal must be resolved first."
        )))
        let viewModel = EditTripViewModel(trip: original, api: api) { _ in }

        await viewModel.changeState(.makingPrivate)

        XCTAssertFalse(viewModel.isDraft)
        XCTAssertEqual(viewModel.visibility, "public")
        XCTAssertEqual(
            viewModel.saveError,
            "Cannot make this trip private while its Explore submission is pending. Explore withdrawal or removal must be resolved first."
        )
        XCTAssertNil(viewModel.activeTransition)
    }

    func testDuplicateTransitionTapStartsOneRequestAndCleansLoading() async {
        let original = makeTrip(isDraft: true, visibility: "private")
        let api = DelayedTripSettingsAPI()
        let viewModel = EditTripViewModel(trip: original, api: api) { _ in }

        let first = Task { await viewModel.changeState(.publishing) }
        await api.waitForRequest()
        let second = Task { await viewModel.changeState(.publishing) }
        await Task.yield()

        XCTAssertEqual(api.callCount, 1)
        XCTAssertEqual(viewModel.activeTransition, .publishing)

        api.complete(.success(makeTrip(isDraft: false, visibility: "private")))
        await first.value
        await second.value
        XCTAssertEqual(api.callCount, 1)
        XCTAssertNil(viewModel.activeTransition)
    }

    func testTimeoutPreservesStateAndEndsLoading() async {
        let original = makeTrip(isDraft: false, visibility: "private")
        let api = TripSettingsAPIStub(result: .failure(URLError(.timedOut)))
        let viewModel = EditTripViewModel(trip: original, api: api) { _ in }

        await viewModel.changeState(.makingPublic)

        XCTAssertEqual(viewModel.visibility, "private")
        XCTAssertFalse(viewModel.isDraft)
        XCTAssertNil(viewModel.activeTransition)
        XCTAssertNotNil(viewModel.saveError)
    }

    func testExploreEligibilityReportsLifecycleBeforeSubmission() {
        let draft = TripDetailViewModel(trip: makeTrip(isDraft: true, visibility: "private"))
        XCTAssertEqual(draft.submissionEligibilityError, "Trip must be public to submit.")

        let privatePublished = TripDetailViewModel(
            trip: makeTrip(isDraft: false, visibility: "private")
        )
        XCTAssertEqual(privatePublished.submissionEligibilityError, "Trip must be public to submit.")

        let publicPublished = TripDetailViewModel(
            trip: makeTrip(isDraft: false, visibility: "public")
        )
        XCTAssertNil(publicPublished.submissionEligibilityError)
    }

    private var tripJSON: String {
        #"{"id":"trip-1","title":"Draft","description":null,"coverPhotoUrl":null,"plannedStartDate":null,"plannedEndDate":null,"actualStartDate":null,"actualEndDate":null,"visibility":"private","country":null,"city":null,"isDraft":true,"isPlanning":false,"createdAt":"2026-01-15T12:00:00Z","ownerId":"owner-1","entryCount":0,"dayCount":0,"destinations":[]}"#
    }
}

@MainActor
private final class TripSettingsAPIStub: TripSettingsAPIProviding {
    let result: Result<Trip, Error>
    private(set) var callCount = 0

    init(result: Result<Trip, Error>) { self.result = result }

    func updateTrip(id: String, body: UpdateTripRequest) async throws -> Trip {
        callCount += 1
        return try result.get()
    }
}

@MainActor
private final class DelayedTripSettingsAPI: TripSettingsAPIProviding {
    private(set) var callCount = 0
    private var continuation: CheckedContinuation<Trip, Error>?

    func updateTrip(id: String, body: UpdateTripRequest) async throws -> Trip {
        callCount += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitForRequest() async {
        while callCount == 0 { await Task.yield() }
    }

    func complete(_ result: Result<Trip, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}

@MainActor
private func makeTrip(isDraft: Bool, visibility: String) -> Trip {
    Trip(
        id: "trip-1",
        title: "Trip",
        description: nil,
        coverPhotoUrl: nil,
        plannedStartDate: nil,
        plannedEndDate: nil,
        actualStartDate: nil,
        actualEndDate: nil,
        visibility: visibility,
        country: nil,
        city: nil,
        isDraft: isDraft,
        isPlanning: false,
        createdAt: Date(timeIntervalSince1970: 0),
        ownerId: "owner-1",
        entryCount: 3,
        dayCount: 1,
        destinations: []
    )
}
