import XCTest
@testable import BoardPostal

@MainActor
final class SubmissionContractTests: XCTestCase {
    func testBackendEligibilityErrorIsPreserved() async throws {
        let api = makeAPI(status: 400, json: #"{"error":"Trip must have at least 3 entries."}"#)

        do {
            let _: TripSubmission = try await api.request(
                .submitTrip(tripId: "10000000-0000-0000-0000-000000000001"),
                method: .post,
                body: SubmitTripRequest(message: nil)
            )
            XCTFail("Expected the eligibility failure")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Trip must have at least 3 entries.")
        }
    }

    func testSuccessfulSubmissionResponseMatchesBackendContract() async throws {
        let api = makeAPI(
            status: 200,
            json: #"{"submissionId":"70000000-0000-0000-0000-000000000001","status":"pending"}"#
        )

        let response: SubmitTripResponse = try await api.request(
            .submitTrip(tripId: "10000000-0000-0000-0000-000000000001"),
            method: .post,
            body: SubmitTripRequest(message: "Please review")
        )

        XCTAssertEqual(response.submissionId, "70000000-0000-0000-0000-000000000001")
        XCTAssertEqual(response.status, "pending")
    }

    func testSubmissionStatePreventsReentryAndBecomesPending() async {
        let api = DelayedSubmissionAPI()
        let viewModel = TripDetailViewModel(trip: makeTrip(), submissionAPI: api)
        viewModel.entries = (1...3).map(makeEntry)
        viewModel.places = [makePlace()]

        XCTAssertNil(viewModel.submissionEligibilityError)

        let first = Task { await viewModel.submitForPublication(message: "Please review") }
        await api.waitForRequest()
        let second = await viewModel.submitForPublication(message: "Duplicate")

        XCTAssertEqual(api.callCount, 1)
        XCTAssertTrue(viewModel.isSubmitting)
        XCTAssertEqual(second, "A submission is already in progress.")

        api.complete(.success(SubmitTripResponse(
            submissionId: "70000000-0000-0000-0000-000000000001",
            status: "pending"
        )))
        let firstResult = await first.value
        XCTAssertNil(firstResult)
        XCTAssertFalse(viewModel.isSubmitting)
        XCTAssertEqual(viewModel.submission?.status, "pending")
        XCTAssertEqual(viewModel.submission?.message, "Please review")
    }

    func testSubmissionFailurePreservesMessageForFormAndEndsLoading() async {
        let api = SubmissionAPIStub(result: .failure(
            APIError.badRequest("Trip must have at least 3 entries.")
        ))
        let viewModel = TripDetailViewModel(trip: makeTrip(), submissionAPI: api)

        let message = "Keep this message"
        let error = await viewModel.submitForPublication(message: message)

        XCTAssertEqual(error, "Trip must have at least 3 entries.")
        XCTAssertNil(viewModel.submission)
        XCTAssertFalse(viewModel.isSubmitting)
        XCTAssertEqual(api.receivedMessages, [message])
    }

    func testOptionalMessageMayBeOmitted() async {
        let api = SubmissionAPIStub(result: .success(SubmitTripResponse(
            submissionId: "70000000-0000-0000-0000-000000000001",
            status: "pending"
        )))
        let viewModel = TripDetailViewModel(trip: makeTrip(), submissionAPI: api)

        let result = await viewModel.submitForPublication(message: nil)
        XCTAssertNil(result)
        XCTAssertEqual(api.receivedMessages.count, 1)
        XCTAssertNil(api.receivedMessages[0])
    }

    func testPrivateAndDraftTripsExposeEstablishedEligibilityRules() {
        let privateTrip = TripDetailViewModel(
            trip: makeTrip(visibility: "private"),
            submissionAPI: SubmissionAPIStub(result: .failure(APIError.serverError(500)))
        )
        let draftTrip = TripDetailViewModel(
            trip: makeTrip(isDraft: true),
            submissionAPI: SubmissionAPIStub(result: .failure(APIError.serverError(500)))
        )

        XCTAssertEqual(privateTrip.submissionEligibilityError, "Trip must be public to submit.")
        XCTAssertEqual(draftTrip.submissionEligibilityError, "Trip must be published to submit.")
    }

    func testPendingDuplicateConflictMessageIsPreserved() async {
        let api = makeAPI(status: 409, json: #"{"error":"Already submitted and pending review."}"#)

        do {
            let _: SubmitTripResponse = try await api.submitTrip(tripId: "trip-1", message: nil)
            XCTFail("Expected pending conflict")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Already submitted and pending review.")
        }
    }

    func testSubmissionValidationPrefersFieldMessageOverGenericTitle() async {
        let api = makeAPI(
            status: 400,
            json: #"{"title":"One or more validation errors occurred.","errors":{"Message":["The length of 'Message' must be 500 characters or fewer."]}}"#
        )

        do {
            let _: SubmitTripResponse = try await api.submitTrip(tripId: "trip-1", message: String(repeating: "x", count: 501))
            XCTFail("Expected message validation failure")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "The length of 'Message' must be 500 characters or fewer."
            )
        }
    }

    private func makeAPI(status: Int, json: String) -> APIClient {
        SubmissionURLProtocolStub.response = (status, Data(json.utf8))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SubmissionURLProtocolStub.self]
        return APIClient(session: URLSession(configuration: configuration))
    }

    private func makeTrip(
        visibility: String = "public",
        isDraft: Bool = false
    ) -> Trip {
        Trip(
            id: "10000000-0000-0000-0000-000000000001",
            title: "Eligible trip",
            description: nil,
            coverPhotoUrl: nil,
            plannedStartDate: nil,
            plannedEndDate: nil,
            actualStartDate: nil,
            actualEndDate: nil,
            visibility: visibility,
            country: "Türkiye",
            city: "Istanbul",
            isDraft: isDraft,
            isPlanning: false,
            createdAt: Date(timeIntervalSince1970: 0),
            ownerId: "20000000-0000-0000-0000-000000000001",
            entryCount: 3,
            dayCount: 1,
            destinations: []
        )
    }

    private func makeEntry(_ number: Int) -> TripEntry {
        TripEntry(
            id: "entry-\(number)",
            tripId: "10000000-0000-0000-0000-000000000001",
            title: "Entry \(number)",
            content: "Test",
            entryDate: "2026-04-0\(number)",
            placeName: nil,
            orderIndex: number - 1,
            visibility: "public",
            isDraft: false,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: nil
        )
    }

    private func makePlace() -> TripPlace {
        TripPlace(
            id: "60000000-0000-0000-0000-000000000001",
            tripId: "10000000-0000-0000-0000-000000000001",
            placeId: "50000000-0000-0000-0000-000000000001",
            placeName: "Galata Tower",
            category: "landmark",
            latitude: 41.0256,
            longitude: 28.9741,
            notes: nil,
            orderIndex: 0,
            imageUrl: nil
        )
    }
}

@MainActor
private final class SubmissionAPIStub: SubmissionAPIProviding {
    let result: Result<SubmitTripResponse, Error>
    private(set) var receivedMessages: [String?] = []

    init(result: Result<SubmitTripResponse, Error>) {
        self.result = result
    }

    func submitTrip(tripId: String, message: String?) async throws -> SubmitTripResponse {
        receivedMessages.append(message)
        return try result.get()
    }
}

@MainActor
private final class DelayedSubmissionAPI: SubmissionAPIProviding {
    private(set) var callCount = 0
    private var continuation: CheckedContinuation<SubmitTripResponse, Error>?

    func submitTrip(tripId: String, message: String?) async throws -> SubmitTripResponse {
        callCount += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitForRequest() async {
        while callCount == 0 { await Task.yield() }
    }

    func complete(_ result: Result<SubmitTripResponse, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}

private final class SubmissionURLProtocolStub: URLProtocol {
    static var response = (status: 500, data: Data())

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let value = Self.response
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: value.status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: value.data)
        client?.urlProtocolDidFinishLoading(self)
    }
}
