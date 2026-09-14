import XCTest
import PDFKit
@testable import BoardPostal

@MainActor
final class MapAndPDFStabilizationTests: XCTestCase {
    func testWorldMapUsesStoredCoordinatesAndStablePlaceIdentity() async throws {
        let trip = makeMapTrip()
        let valid = makeMapPlace(id: "place-a", latitude: 52.2297, longitude: 21.0122)
        let missing = makeMapPlace(id: "place-b", latitude: nil, longitude: nil)
        let api = WorldMapAPIStub(trips: [trip], places: [trip.id: [valid, missing]])
        let viewModel = WorldMapViewModel(api: api)

        await viewModel.loadTrips()

        XCTAssertEqual(viewModel.annotations.count, 1)
        let annotation = try XCTUnwrap(viewModel.annotations.first)
        XCTAssertEqual(annotation.id, "trip-map:place-a")
        XCTAssertEqual(annotation.coordinate.latitude, 52.2297, accuracy: 0.000_001)
        XCTAssertEqual(annotation.coordinate.longitude, 21.0122, accuracy: 0.000_001)
    }

    func testWorldMapPinSelectionDismissalAndReopening() async throws {
        let trip = makeMapTrip()
        let place = makeMapPlace(id: "place-a", latitude: 52.2297, longitude: 21.0122)
        let viewModel = WorldMapViewModel(api: WorldMapAPIStub(trips: [trip], places: [trip.id: [place]]))
        await viewModel.loadTrips()
        let annotation = try XCTUnwrap(viewModel.annotations.first)

        viewModel.select(annotation)
        XCTAssertEqual(viewModel.selectedTrip?.id, trip.id)
        viewModel.dismissSelection()
        XCTAssertNil(viewModel.selectedTrip)
        viewModel.select(annotation)
        XCTAssertEqual(viewModel.selectedTrip?.id, trip.id)
    }

    func testNavigationRejectsMissingAndInvalidCoordinates() {
        XCTAssertNil(PlaceNavigationURLs.coordinate(for: makeMapPlace(id: "missing", latitude: nil, longitude: nil)))
        XCTAssertNil(PlaceNavigationURLs.coordinate(for: makeMapPlace(id: "invalid", latitude: 100, longitude: 20)))
        XCTAssertNil(PlaceNavigationURLs.googleMaps(for: makeMapPlace(id: "missing", latitude: nil, longitude: nil)))
    }

    func testGoogleMapsUniversalURLIsEncodedAndBrowserCapable() throws {
        let place = makeMapPlace(
            id: "encoded",
            name: "Muzeum & Old Town",
            latitude: 52.2297,
            longitude: 21.0122
        )
        let url = try XCTUnwrap(PlaceNavigationURLs.googleMaps(for: place))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(components.host, "www.google.com")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "api" })?.value, "1")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "destination" })?.value, "52.2297,21.0122")
    }

    func testNavigationOpeningIsInjectableWithoutLaunchingApps() {
        let opener = PlaceNavigationOpenerSpy()
        let navigation = PlaceNavigationController(opener: opener)
        let place = makeMapPlace(id: "place", latitude: 52.2297, longitude: 21.0122)
        let missing = makeMapPlace(id: "missing", latitude: nil, longitude: nil)

        navigation.openAppleMaps(for: place)
        navigation.openGoogleMaps(for: place)
        navigation.openAppleMaps(for: missing)
        navigation.openGoogleMaps(for: missing)

        XCTAssertEqual(opener.applePlaceIDs, [place.id])
        XCTAssertEqual(opener.googlePlaceIDs, [place.id])
    }

    func testPDFIsValidAndContainsPopulatedSections() throws {
        let data = PDFGenerator().generate(
            trip: makePDFTrip(title: "Warsaw Field Notes", description: "A weekend travel story."),
            entries: [makeEntry(index: 1, content: "Journal content from the old town.")],
            days: [makeDay()],
            places: [makeMapPlace(id: "place", name: "Royal Castle", latitude: 52.2478, longitude: 21.0142)]
        )
        let document = try XCTUnwrap(PDFDocument(data: data))
        let text = document.string ?? ""

        XCTAssertGreaterThan(data.count, 1_000)
        XCTAssertGreaterThanOrEqual(document.pageCount, 1)
        XCTAssertTrue(text.contains("Warsaw Field Notes"))
        XCTAssertTrue(text.contains("TRIP OVERVIEW"))
        XCTAssertTrue(text.contains("ITINERARY"))
        XCTAssertTrue(text.contains("JOURNAL"))
        XCTAssertTrue(text.contains("PLACES"))
        XCTAssertTrue(text.contains("Royal Castle"))
        XCTAssertTrue(text.contains("Journal content from the old town."))
    }

    func testLongPDFPaginatesWithoutClippingFinalContent() throws {
        let entries = (0..<90).map {
            makeEntry(index: $0, content: "Entry body \($0) with enough deterministic words to exercise page flow and pagination.")
        }
        let data = PDFGenerator().generate(
            trip: makePDFTrip(title: "Long Journey", description: nil),
            entries: entries,
            days: [],
            places: []
        )
        let document = try XCTUnwrap(PDFDocument(data: data))

        XCTAssertGreaterThan(document.pageCount, 1)
        XCTAssertTrue((document.string ?? "").contains("Entry 89"))
    }

    func testPDFHandlesEmptyOptionalSections() throws {
        let data = PDFGenerator().generate(
            trip: makePDFTrip(title: "Minimal Trip", description: nil),
            entries: [],
            days: [],
            places: []
        )
        let document = try XCTUnwrap(PDFDocument(data: data))

        XCTAssertEqual(document.pageCount, 1)
        XCTAssertTrue((document.string ?? "").contains("Minimal Trip"))
    }

    func testRepeatedExportsContainCurrentContent() throws {
        let generator = PDFGenerator()
        let first = generator.generate(trip: makePDFTrip(title: "First Export", description: nil), entries: [], days: [], places: [])
        let second = generator.generate(trip: makePDFTrip(title: "Current Export", description: nil), entries: [], days: [], places: [])

        XCTAssertTrue(try XCTUnwrap(PDFDocument(data: first)?.string).contains("First Export"))
        let currentText = try XCTUnwrap(PDFDocument(data: second)?.string)
        XCTAssertTrue(currentText.contains("Current Export"))
        XCTAssertFalse(currentText.contains("First Export"))
    }
}

@MainActor
private final class WorldMapAPIStub: WorldMapAPIProviding {
    let trips: [Trip]
    let places: [String: [TripPlace]]

    init(trips: [Trip], places: [String: [TripPlace]]) {
        self.trips = trips
        self.places = places
    }

    func worldMapTrips() async throws -> [Trip] { trips }
    func worldMapPlaces(tripId: String) async throws -> [TripPlace] { places[tripId] ?? [] }
}

@MainActor
private final class PlaceNavigationOpenerSpy: PlaceNavigationOpening {
    var applePlaceIDs: [String] = []
    var googlePlaceIDs: [String] = []

    func openAppleMaps(for place: TripPlace) { applePlaceIDs.append(place.id) }
    func openGoogleMaps(for place: TripPlace) { googlePlaceIDs.append(place.id) }
}

@MainActor
private func makeMapTrip() -> Trip {
    Trip(
        id: "trip-map", title: "Warsaw", description: nil, coverPhotoUrl: nil,
        plannedStartDate: "2026-09-20", plannedEndDate: "2026-09-22",
        actualStartDate: nil, actualEndDate: nil, visibility: "private",
        country: "Poland", city: "Warsaw", isDraft: false, isPlanning: true,
        createdAt: Date(timeIntervalSince1970: 0), ownerId: "owner", entryCount: 1,
        dayCount: 1, destinations: [
            TripDestination(id: "destination", country: "Poland", city: "Warsaw", orderIndex: 0)
        ]
    )
}

@MainActor
private func makePDFTrip(title: String, description: String?) -> Trip {
    let trip = makeMapTrip()
    return Trip(
        id: trip.id, title: title, description: description, coverPhotoUrl: nil,
        plannedStartDate: trip.plannedStartDate, plannedEndDate: trip.plannedEndDate,
        actualStartDate: nil, actualEndDate: nil, visibility: trip.visibility,
        country: trip.country, city: trip.city, isDraft: trip.isDraft,
        isPlanning: trip.isPlanning, createdAt: trip.createdAt, ownerId: trip.ownerId,
        entryCount: trip.entryCount, dayCount: trip.dayCount, destinations: trip.destinations
    )
}

@MainActor
private func makeMapPlace(
    id: String,
    name: String = "Old Town",
    latitude: Double?,
    longitude: Double?
) -> TripPlace {
    TripPlace(
        id: id, tripId: "trip-map", placeId: "stored-\(id)", placeName: name,
        category: "landmark", latitude: latitude, longitude: longitude,
        notes: "Saved place", orderIndex: 0, imageUrl: nil
    )
}

@MainActor
private func makeDay() -> TripDay {
    TripDay(
        id: "day", tripId: "trip-map", dayNumber: 1, title: "Old Town",
        date: "2026-09-20", orderIndex: 0, items: [
            TripDayItem(
                id: "item", tripDayId: "day", type: "place", title: "Royal Castle",
                notes: "Morning visit", time: "09:00", orderIndex: 0, placeId: "place"
            )
        ]
    )
}

@MainActor
private func makeEntry(index: Int, content: String) -> TripEntry {
    TripEntry(
        id: "entry-\(index)", tripId: "trip-map", title: "Entry \(index)",
        content: content, entryDate: "2026-09-20", placeName: "Old Town",
        orderIndex: index, visibility: "private", isDraft: false,
        createdAt: Date(timeIntervalSince1970: TimeInterval(index)), updatedAt: nil
    )
}
