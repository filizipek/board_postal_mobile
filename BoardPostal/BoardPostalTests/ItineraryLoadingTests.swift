import XCTest
@testable import BoardPostal

@MainActor
final class ItineraryLoadingTests: XCTestCase {
    func testFailureShowsFailedStateInsteadOfSuccessfulEmptyState() async {
        let loader = SequencedDaysLoader(results: [
            .failure(APIError.decodingError("sanitized diagnostic"))
        ])
        let viewModel = TripDetailViewModel(
            trip: makeLoadingTrip(),
            submissionAPI: LoadingSubmissionStub(),
            itineraryAPI: loader
        )

        await viewModel.loadItinerary()

        XCTAssertEqual(viewModel.itineraryLoadState, .failed)
        XCTAssertTrue(viewModel.days.isEmpty)
    }

    func testRetryAfterFailureLoadsDaysWithoutRecreatingViewModel() async throws {
        let expected: [TripDay] = try decodeLoadingFixture("itinerary-production-two-days")
        let loader = SequencedDaysLoader(results: [
            .failure(URLError(.timedOut)),
            .success(expected)
        ])
        let viewModel = TripDetailViewModel(
            trip: makeLoadingTrip(),
            submissionAPI: LoadingSubmissionStub(),
            itineraryAPI: loader
        )

        await viewModel.loadItinerary()
        XCTAssertEqual(viewModel.itineraryLoadState, .failed)
        XCTAssertEqual(viewModel.itineraryLoadRevision, 0)

        await viewModel.loadItinerary()

        XCTAssertEqual(viewModel.itineraryLoadState, .loaded)
        XCTAssertEqual(viewModel.days.map(\.id), expected.map(\.id))
        XCTAssertEqual(viewModel.itineraryLoadRevision, 1)
        XCTAssertEqual(loader.callCount, 2)
    }

    func testSuccessfulEmptyResponseUsesLoadedState() async {
        let loader = SequencedDaysLoader(results: [.success([])])
        let viewModel = TripDetailViewModel(
            trip: makeLoadingTrip(),
            submissionAPI: LoadingSubmissionStub(),
            itineraryAPI: loader
        )

        await viewModel.loadItinerary()

        XCTAssertEqual(viewModel.itineraryLoadState, .loaded)
        XCTAssertTrue(viewModel.days.isEmpty)
    }
}

@MainActor
private final class SequencedDaysLoader: ItineraryDaysLoading {
    private var results: [Result<[TripDay], Error>]
    private(set) var callCount = 0

    init(results: [Result<[TripDay], Error>]) {
        self.results = results
    }

    func loadDays(tripId: String) async throws -> [TripDay] {
        callCount += 1
        return try results.removeFirst().get()
    }
}

@MainActor
private struct LoadingSubmissionStub: SubmissionAPIProviding {
    func submitTrip(tripId: String, message: String?) async throws -> SubmitTripResponse {
        throw APIError.serverError(500)
    }
}

@MainActor
private func makeLoadingTrip() -> Trip {
    Trip(
        id: "trip-1",
        title: "Fixture trip",
        description: nil,
        coverPhotoUrl: nil,
        plannedStartDate: nil,
        plannedEndDate: nil,
        actualStartDate: nil,
        actualEndDate: nil,
        visibility: "private",
        country: nil,
        city: nil,
        isDraft: true,
        isPlanning: true,
        createdAt: Date(timeIntervalSince1970: 0),
        ownerId: "owner-1",
        entryCount: 1,
        dayCount: 2,
        destinations: []
    )
}

private func decodeLoadingFixture<T: Decodable>(_ name: String) throws -> T {
    let url = try XCTUnwrap(Bundle(for: ItineraryLoadingTests.self).url(forResource: name, withExtension: "json"))
    return try JSONDecoder.bpDecoder.decode(T.self, from: Data(contentsOf: url))
}
