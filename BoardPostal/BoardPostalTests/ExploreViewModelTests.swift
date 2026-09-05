import XCTest
@testable import BoardPostal

@MainActor
final class ExploreViewModelTests: XCTestCase {
    func testMatchingSearchResultIsRetainedInState() async throws {
        let page: PaginatedResponse<PublicTripCard> = try decodeFixture("explore-page-multiple")
        let viewModel = ExploreViewModel(api: ExploreStub(publicTrips: .success(page)))
        viewModel.searchQuery = "zermatt"

        await viewModel.search()

        XCTAssertEqual(viewModel.searchResults.map(\.title), ["Alpine Weekend"])
        XCTAssertNil(viewModel.searchError)
        XCTAssertFalse(viewModel.isSearching)
    }

    func testNoResultsIsSuccessfulAndDistinctFromFailure() async throws {
        let page: PaginatedResponse<PublicTripCard> = try decodeFixture("explore-page-empty")
        let viewModel = ExploreViewModel(api: ExploreStub(publicTrips: .success(page)))
        viewModel.searchQuery = "missing"

        await viewModel.search()

        XCTAssertTrue(viewModel.searchResults.isEmpty)
        XCTAssertNil(viewModel.searchError)
        XCTAssertFalse(viewModel.isSearching)
    }

    func testMalformedResponseIsAnErrorRatherThanEmptySuccess() async {
        let viewModel = ExploreViewModel(api: ExploreStub(
            publicTrips: .failure(APIError.decodingError("Malformed test response"))))
        viewModel.searchQuery = "istanbul"

        await viewModel.search()

        XCTAssertTrue(viewModel.searchResults.isEmpty)
        XCTAssertNotNil(viewModel.searchError)
        XCTAssertFalse(viewModel.isSearching)
    }

    func testServerFailureIsAnErrorRatherThanEmptySuccess() async {
        let viewModel = ExploreViewModel(api: ExploreStub(
            publicTrips: .failure(APIError.serverError(503))))
        viewModel.searchQuery = "istanbul"

        await viewModel.search()

        XCTAssertTrue(viewModel.searchResults.isEmpty)
        XCTAssertEqual(viewModel.searchError, APIError.serverError(503).localizedDescription)
        XCTAssertFalse(viewModel.isSearching)
    }

    func testFeedLoadingEndsAfterSuccess() async throws {
        let page: PaginatedResponse<PublicTripCard> = try decodeFixture("explore-page-one")
        let viewModel = ExploreViewModel(api: ExploreStub(publicTrips: .success(page)))

        await viewModel.loadFeed()

        XCTAssertEqual(viewModel.recentTrips.count, 1)
        XCTAssertNil(viewModel.error)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testFeedLoadingEndsAfterFailure() async {
        let viewModel = ExploreViewModel(api: ExploreStub(
            publicTrips: .failure(APIError.serverError(500))))

        await viewModel.loadFeed()

        XCTAssertNotNil(viewModel.error)
        XCTAssertFalse(viewModel.isLoading)
    }

    private func decodeFixture<T: Decodable>(_ name: String) throws -> T {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try JSONDecoder.bpDecoder.decode(T.self, from: Data(contentsOf: url))
    }
}

@MainActor
private struct ExploreStub: ExploreProviding {
    let featuredTrips: Result<[FeaturedTrip], Error>
    let publicTrips: Result<PaginatedResponse<PublicTripCard>, Error>

    init(
        featuredTrips: Result<[FeaturedTrip], Error> = .success([]),
        publicTrips: Result<PaginatedResponse<PublicTripCard>, Error>
    ) {
        self.featuredTrips = featuredTrips
        self.publicTrips = publicTrips
    }

    func fetchFeaturedTrips() async throws -> [FeaturedTrip] {
        try featuredTrips.get()
    }

    func fetchPublicTrips() async throws -> PaginatedResponse<PublicTripCard> {
        try publicTrips.get()
    }
}
