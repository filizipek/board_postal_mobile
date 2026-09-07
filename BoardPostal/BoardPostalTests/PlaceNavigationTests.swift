import XCTest
@testable import BoardPostal

@MainActor
final class PlaceNavigationTests: XCTestCase {
    func testCoordinateNavigationURLsAreDeterministicAndEncoded() throws {
        let place = makePlace(name: "Galata Tower & Square", latitude: 41.0256, longitude: 28.9741)

        let apple = try XCTUnwrap(PlaceNavigationURLs.appleMaps(for: place))
        let google = try XCTUnwrap(PlaceNavigationURLs.googleMaps(for: place))
        let appleComponents = try XCTUnwrap(URLComponents(url: apple, resolvingAgainstBaseURL: false))
        let googleComponents = try XCTUnwrap(URLComponents(url: google, resolvingAgainstBaseURL: false))

        XCTAssertEqual(appleComponents.host, "maps.apple.com")
        XCTAssertEqual(appleComponents.queryValue(named: "daddr"), "41.0256,28.9741")
        XCTAssertEqual(appleComponents.queryValue(named: "q"), "Galata Tower & Square")
        XCTAssertEqual(googleComponents.host, "www.google.com")
        XCTAssertEqual(googleComponents.queryValue(named: "api"), "1")
        XCTAssertEqual(googleComponents.queryValue(named: "destination"), "41.0256,28.9741")
    }

    func testMissingCoordinatesDoNotProduceImpreciseNavigationURLs() {
        let place = makePlace(name: "Unknown place", latitude: nil, longitude: nil)

        XCTAssertNil(PlaceNavigationURLs.appleMaps(for: place))
        XCTAssertNil(PlaceNavigationURLs.googleMaps(for: place))
    }

    private func makePlace(name: String, latitude: Double?, longitude: Double?) -> TripPlace {
        TripPlace(
            id: "60000000-0000-0000-0000-000000000001",
            tripId: "10000000-0000-0000-0000-000000000001",
            placeId: "50000000-0000-0000-0000-000000000001",
            placeName: name,
            category: "landmark",
            latitude: latitude,
            longitude: longitude,
            notes: nil,
            orderIndex: 0,
            imageUrl: nil
        )
    }
}

private extension URLComponents {
    func queryValue(named name: String) -> String? {
        queryItems?.first(where: { $0.name == name })?.value
    }
}
