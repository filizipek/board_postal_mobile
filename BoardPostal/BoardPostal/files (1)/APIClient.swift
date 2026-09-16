import Foundation
import OSLog

enum DecodingDiagnostics {
    static func sanitizedDescription<T>(for error: Error, model: T.Type) -> String {
        let modelName = String(reflecting: model)
        guard let decodingError = error as? DecodingError else {
            return "Model: \(modelName). Error: non-Codable decoding failure."
        }

        let kind: String
        let path: [CodingKey]
        switch decodingError {
        case .keyNotFound(let key, let context):
            kind = "missing key \(key.stringValue)"
            path = context.codingPath + [key]
        case .valueNotFound(let type, let context):
            kind = "missing/null value for \(String(reflecting: type))"
            path = context.codingPath
        case .typeMismatch(let type, let context):
            kind = "type mismatch for \(String(reflecting: type))"
            path = context.codingPath
        case .dataCorrupted(let context):
            kind = "corrupt value"
            path = context.codingPath
        @unknown default:
            kind = "unknown Codable failure"
            path = []
        }
        return "Model: \(modelName). Path: \(codingPath(path)). Error: \(kind)."
    }

    private static func codingPath(_ keys: [CodingKey]) -> String {
        guard !keys.isEmpty else { return "<root>" }
        return keys.reduce(into: "") { result, key in
            if let index = key.intValue {
                result += "[\(index)]"
            } else {
                result += result.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
    }
}

// MARK: - APIClient
// URLSession-based HTTP client that mirrors the Axios JWT interceptor behaviour:
// - Attaches Bearer token to every request automatically
// - On 401: refreshes token once, retries the original request
// - On refresh failure: broadcasts logout notification

final class APIClient {
    static let shared = APIClient()
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    private let keychain = KeychainService.shared
    private var isRefreshing = false
    private var pendingRequests: [CheckedContinuation<Void, Error>] = []

    // MARK: - Core request method
    func request<T: Decodable>(
        _ endpoint: APIEndpoint,
        method: HTTPMethod = .get,
        body: Encodable? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        let data = try await performRequest(endpoint, method: method, body: body, requiresAuth: requiresAuth)
        return try decode(T.self, from: data)
    }

    // Void response variant (for DELETE etc.)
    func requestVoid(
        _ endpoint: APIEndpoint,
        method: HTTPMethod = .delete,
        body: Encodable? = nil,
        requiresAuth: Bool = true
    ) async throws {
        _ = try await performRequest(endpoint, method: method, body: body, requiresAuth: requiresAuth)
    }

    // MARK: - Internal request performer
    private func performRequest(
        _ endpoint: APIEndpoint,
        method: HTTPMethod,
        body: Encodable?,
        requiresAuth: Bool,
        isRetry: Bool = false
    ) async throws -> Data {
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        // Attach JWT
        if requiresAuth, let token = keychain.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Encode body
        if let body {
            request.httpBody = try JSONEncoder.bpEncoder.encode(body)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return data

        case 401 where requiresAuth && !isRetry:
            // Token expired — refresh and retry
            try await refreshTokens()
            return try await performRequest(
                endpoint, method: method, body: body,
                requiresAuth: requiresAuth, isRetry: true
            )

        case 401 where requiresAuth:
            // Refresh also failed — force logout
            await triggerLogout()
            throw APIError.unauthorized

        case 401:
            // Wrong credentials on login/register — just report it
            let message = parseErrorMessage(from: data) ?? "Invalid email or password."
            throw APIError.badRequest(message)

        case 400:
            let message = parseErrorMessage(from: data) ?? "Invalid request."
            throw APIError.badRequest(message)

        case 403:
            throw APIError.forbidden

        case 404:
            throw APIError.notFound

        case 409:
            let message = parseErrorMessage(from: data) ?? "Conflict."
            throw APIError.conflict(message)

        case 422:
            let message = parseErrorMessage(from: data) ?? "Validation failed."
            throw APIError.validationError(message)

        case 500...599:
            throw APIError.serverError(httpResponse.statusCode)

        default:
            throw APIError.unknown(httpResponse.statusCode)
        }
    }

    // MARK: - Token refresh (single-flight)
    private func refreshTokens() async throws {
        if isRefreshing {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                pendingRequests.append(continuation)
            }
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        guard let refreshToken = keychain.refreshToken else {
            await triggerLogout()
            resumePendingRequests(with: .failure(APIError.unauthorized))
            throw APIError.unauthorized
        }

        do {
            let body = RefreshRequest(refreshToken: refreshToken)
            var request = URLRequest(url: APIEndpoint.refresh.url)
            request.httpMethod = HTTPMethod.post.rawValue
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder.bpEncoder.encode(body)

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                await triggerLogout()
                resumePendingRequests(with: .failure(APIError.unauthorized))
                throw APIError.unauthorized
            }

            let tokens = try decode(AuthTokensResponse.self, from: data)
            keychain.saveTokens(
                access: tokens.accessToken,
                refresh: tokens.refreshToken,
                userId: tokens.userId ?? keychain.userId ?? "",
                email: tokens.email ?? keychain.email ?? ""
            )
            resumePendingRequests(with: .success(()))
        } catch {
            resumePendingRequests(with: .failure(error))
            throw error
        }
    }

    private func resumePendingRequests(with result: Result<Void, Error>) {
        let waiters = pendingRequests
        pendingRequests.removeAll()
        for continuation in waiters {
            continuation.resume(with: result)
        }
    }

    // MARK: - Logout broadcast
    @MainActor
    private func triggerLogout() {
        keychain.clearAll()
        NotificationCenter.default.post(name: .bpForceLogout, object: nil)
    }

    // MARK: - Decode helper
    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder.bpDecoder.decode(type, from: data)
        } catch {
            let diagnostic = DecodingDiagnostics.sanitizedDescription(for: error, model: type)
            Logger(subsystem: "com.boardpostal.ios", category: "decoding")
                .error("\(diagnostic, privacy: .public)")
            throw APIError.decodingError(diagnostic)
        }
    }

    // MARK: - Error message parser
    private func parseErrorMessage(from data: Data) -> String? {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            if let errors = json["errors"] as? [String: [String]] {
                let messages = errors.keys.sorted().flatMap { errors[$0] ?? [] }
                if !messages.isEmpty {
                    return messages.joined(separator: "\n")
                }
            }
            return json["error"] as? String
                ?? json["message"] as? String
                ?? json["title"] as? String
        } catch {
            return nil
        }
    }
}

// MARK: - Trip Entry helpers
extension APIClient {
    func updateTrip(id: String, body: UpdateTripRequest) async throws -> Trip {
        try await request(.trip(id: id), method: .put, body: body)
    }

    func submitTrip(tripId: String, message: String?) async throws -> SubmitTripResponse {
        try await request(
            .submitTrip(tripId: tripId),
            method: .post,
            body: SubmitTripRequest(message: message)
        )
    }

    func createDay(tripId: String, body: CreateDayRequest) async throws -> TripDay {
        try await request(.days(tripId: tripId), method: .post, body: body)
    }

    func updateDay(tripId: String, dayId: String, body: UpdateDayRequest) async throws {
        try await requestVoid(.day(tripId: tripId, dayId: dayId), method: .put, body: body)
    }

    func createDayItem(
        tripId: String,
        dayId: String,
        body: CreateDayItemRequest
    ) async throws -> TripDayItem {
        // The creation projection omits notes/placeId. Distinguish omission from
        // explicit null so returned server values always remain authoritative.
        struct Response: Decodable {
            let item: TripDayItem
            let hasNotes: Bool
            let hasPlaceId: Bool
            enum CodingKeys: String, CodingKey { case notes, placeId }
            init(from decoder: Decoder) throws {
                item = try TripDayItem(from: decoder)
                let container = try decoder.container(keyedBy: CodingKeys.self)
                hasNotes = container.contains(.notes)
                hasPlaceId = container.contains(.placeId)
            }
        }
        let response: Response = try await request(
            .dayItems(tripId: tripId, dayId: dayId), method: .post, body: body)
        let item = response.item
        return TripDayItem(
            id: item.id, tripDayId: item.tripDayId, type: item.type,
            title: item.title,
            notes: response.hasNotes ? item.notes : body.notes,
            time: item.time, orderIndex: item.orderIndex,
            placeId: response.hasPlaceId ? item.placeId : body.placeId)
    }

    func deleteDay(tripId: String, dayId: String) async throws {
        try await requestVoid(.day(tripId: tripId, dayId: dayId), method: .delete)
    }

    func deleteDayItem(tripId: String, dayId: String, itemId: String) async throws {
        try await requestVoid(
            .dayItem(tripId: tripId, dayId: dayId, itemId: itemId),
            method: .delete
        )
    }

    func reorderDays(tripId: String, orderedIds: [String]) async throws {
        try await requestVoid(
            .reorderDays(tripId: tripId),
            method: .put,
            body: ReorderRequest(orderedIds: orderedIds)
        )
    }

    func reorderDayItems(tripId: String, dayId: String, orderedIds: [String]) async throws {
        try await requestVoid(
            .reorderDayItems(tripId: tripId, dayId: dayId),
            method: .put,
            body: ReorderRequest(orderedIds: orderedIds)
        )
    }

    func updateEntry(
        tripId: String,
        entryId: String,
        title: String?,
        content: String
    ) async throws -> TripEntry {
        struct Body: Encodable {
            let title: String?
            let content: String
        }
        return try await request(
            .entry(tripId: tripId, entryId: entryId),
            method: .put,
            body: Body(title: title, content: content)
        )
    }

    func deleteEntry(tripId: String, entryId: String) async throws {
        try await requestVoid(
            .entry(tripId: tripId, entryId: entryId),
            method: .delete
        )
    }

    func updateDayItem(
        tripId: String,
        dayId: String,
        item: TripDayItem,
        title: String,
        notes: String?,
        time: String?
    ) async throws -> TripDayItem {
        struct Body: Encodable {
            let title: String
            let notes: String?
            let time: String?
        }
        try await requestVoid(
            .dayItem(tripId: tripId, dayId: dayId, itemId: item.id),
            method: .put,
            body: Body(title: title, notes: notes, time: time)
        )
        return TripDayItem(
            id: item.id,
            tripDayId: item.tripDayId,
            type: item.type,
            title: title,
            notes: notes,
            time: time,
            orderIndex: item.orderIndex,
            placeId: item.placeId
        )
    }
}

// MARK: - HTTP Method
enum HTTPMethod: String {
    case get    = "GET"
    case post   = "POST"
    case put    = "PUT"
    case patch  = "PATCH"
    case delete = "DELETE"
}

// MARK: - API Errors
enum APIError: LocalizedError {
    case invalidResponse
    case unauthorized
    case forbidden
    case notFound
    case badRequest(String)
    case conflict(String)
    case validationError(String)
    case serverError(Int)
    case decodingError(String)
    case unknown(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:      return "Invalid server response."
        case .unauthorized:         return "Your session has expired. Please log in again."
        case .forbidden:            return "You don't have permission to do this."
        case .notFound:             return "Not found."
        case .badRequest(let msg):  return msg
        case .conflict(let msg):    return msg
        case .validationError(let msg): return msg
        case .serverError(let code): return "Server error (\(code)). Please try again."
        case .decodingError:          return "We couldn't load this data. Please try again."
        case .unknown(let code):    return "Unexpected error (\(code))."
        }
    }
}

// MARK: - Shared JSON coders
extension JSONEncoder {
    static let bpEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let bpDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            let isoFull = ISO8601DateFormatter()
            isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFull.date(from: str) { return date }
            let isoBasic = ISO8601DateFormatter()
            isoBasic.formatOptions = [.withInternetDateTime]
            if let date = isoBasic.date(from: str) { return date }
            let dateOnly = DateFormatter()
            dateOnly.dateFormat = "yyyy-MM-dd"
            if let date = dateOnly.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(str)"
            )
        }
        return decoder
    }()
}

// MARK: - Notification names
extension Notification.Name {
    static let bpForceLogout = Notification.Name("bp.force.logout")
    static let bpTripUpdated = Notification.Name("bp.trip.updated")
}

// MARK: - Internal DTOs for auth
private struct RefreshRequest: Encodable {
    let refreshToken: String
}

private struct AuthTokensResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let userId: String?
    let email: String?
}
