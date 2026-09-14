import XCTest
import UIKit
@testable import BoardPostal

@MainActor
final class TestFlightBuild3StabilizationTests: XCTestCase {
    func testCreateAlwaysSendsCanonicalPrivateAndPreventsDuplicateSubmission() async throws {
        let api = DelayedCreateTripAPI()
        let viewModel = CreateTripViewModel(api: api)
        viewModel.title = "Warsaw"
        viewModel.destinations = [DraftDestination(city: "Warsaw", country: "Poland")]

        let first = Task { await viewModel.save() }
        await api.waitForCreate()
        let second = Task { await viewModel.save() }
        await second.value

        XCTAssertEqual(api.createCallCount, 1)
        XCTAssertTrue(viewModel.isSaving)
        XCTAssertEqual(try encodedVisibility(api.receivedBody), "private")
        api.completeCreate(.success(makeTrip()))
        await first.value
        XCTAssertFalse(viewModel.isSaving)
        XCTAssertEqual(viewModel.createdTripId, "trip-1")
    }

    func testCreateFailurePreservesFormAndChangingStepClearsStaleError() async {
        let api = CreateTripAPIStub(result: .failure(APIError.badRequest("Create failed")))
        let viewModel = CreateTripViewModel(api: api)
        viewModel.title = "Keep me"
        viewModel.destinations = [DraftDestination(city: "Warsaw", country: "Poland")]

        await viewModel.save()
        XCTAssertEqual(viewModel.saveError, "Create failed")
        XCTAssertEqual(viewModel.title, "Keep me")
        XCTAssertNil(viewModel.createdTripId)
        viewModel.nextStep()
        XCTAssertNil(viewModel.saveError)
    }

    func testSavedSelectionAndUnsaveAffectOnlyIntendedTrip() {
        let first = makeCard(id: "saved-1")
        let second = makeCard(id: "saved-2")
        let viewModel = ProfileViewModel()
        viewModel.savedTrips = [first, second]
        viewModel.savedTripsTotal = 2

        viewModel.applySavedState(false, tripId: "saved-1")
        XCTAssertNil(viewModel.selectedSavedTrip)
        XCTAssertEqual(viewModel.savedTrips.map(\.id), ["saved-2"])

        viewModel.selectSavedTrip(second)
        XCTAssertEqual(viewModel.selectedSavedTrip?.id, "saved-2")
        XCTAssertEqual(viewModel.savedTripsTotal, 1)
    }

    func testPlacesAndMapShareDeterministicPlaceSelectionAndDismissal() {
        let selection = PlaceDetailSelection()
        let place = makePlace(latitude: 52.2297, longitude: 21.0122)
        selection.select(place)
        XCTAssertEqual(selection.selectedPlace?.id, place.id)
        selection.dismiss()
        XCTAssertNil(selection.selectedPlace)
    }

    func testPhotoPickerPresentationAndCancellationAreExplicitAndErrorFree() {
        let state = TripPhotoSelectionState()
        state.openPicker()
        XCTAssertTrue(state.isPickerPresented)
        XCTAssertNil(state.error)
        state.pickerDismissed()
        XCTAssertFalse(state.isPickerPresented)
        XCTAssertNil(state.error)
    }

    func testPhotoLoadingFailurePreservesRetryableSelection() {
        let state = TripPhotoSelectionState()
        state.appendLoaded([UIImage(systemName: "photo")!])

        state.reportLoadingFailure()

        XCTAssertEqual(state.selectedImages.count, 1)
        XCTAssertEqual(state.error, "Couldn't load one of the selected photos. Try selecting it again.")
    }

    private func encodedVisibility(_ body: CreateTripRequest?) throws -> String? {
        let body = try XCTUnwrap(body)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        return object["visibility"] as? String
    }
}

@MainActor
private class CreateTripAPIStub: CreateTripAPIProviding {
    let result: Result<Trip, Error>
    fileprivate(set) var createCallCount = 0
    fileprivate(set) var receivedBody: CreateTripRequest?

    init(result: Result<Trip, Error>) { self.result = result }

    func createTrip(body: CreateTripRequest) async throws -> Trip {
        createCallCount += 1
        receivedBody = body
        return try result.get()
    }

    func updateCreatedTrip(id: String, body: UpdateTripRequest) async throws -> Trip { makeTrip() }
    func addDestination(tripId: String, body: AddDestinationRequest) async throws -> TripDestination {
        TripDestination(id: "destination-1", country: body.country, city: body.city, orderIndex: body.orderIndex)
    }
}

@MainActor
private final class DelayedCreateTripAPI: CreateTripAPIStub {
    private var continuation: CheckedContinuation<Trip, Error>?

    init() { super.init(result: .success(makeTrip())) }

    override func createTrip(body: CreateTripRequest) async throws -> Trip {
        createCallCount += 1
        receivedBody = body
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitForCreate() async {
        while createCallCount == 0 { await Task.yield() }
    }

    func completeCreate(_ result: Result<Trip, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}

@MainActor
private func makeTrip() -> Trip {
    Trip(id: "trip-1", title: "Warsaw", description: nil, coverPhotoUrl: nil,
         plannedStartDate: nil, plannedEndDate: nil, actualStartDate: nil,
         actualEndDate: nil, visibility: "private", country: "Poland", city: "Warsaw",
         isDraft: true, isPlanning: true, createdAt: Date(timeIntervalSince1970: 0),
         ownerId: "owner-1", entryCount: 0, dayCount: 0, destinations: [])
}

@MainActor
private func makeCard(id: String) -> PublicTripCard {
    PublicTripCard(id: id, title: id, coverPhotoUrl: nil,
                   createdAt: Date(timeIntervalSince1970: 0), destinations: [],
                   entryCount: 1, placeCount: 1,
                   owner: TripCardOwner(id: "owner-1", fullName: "Owner", avatarUrl: nil, avatarId: nil),
                   isFollowingAuthor: false, isSaved: true)
}

@MainActor
private func makePlace(latitude: Double?, longitude: Double?) -> TripPlace {
    TripPlace(id: "place-1", tripId: "trip-1", placeId: "canonical-place-1",
              placeName: "Old Town", category: "landmark", latitude: latitude,
              longitude: longitude, notes: nil, orderIndex: 0, imageUrl: nil)
}
