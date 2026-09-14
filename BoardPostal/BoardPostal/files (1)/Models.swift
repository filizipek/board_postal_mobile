import Foundation

// MARK: - board_postal Domain Models
// Codable structs mirroring .NET backend DTOs.
// Snake_case ↔ camelCase conversion handled by JSONDecoder.bpDecoder.

// MARK: - User & Auth

struct User: Codable, Identifiable {
    let id: String
    let email: String
    let isAdmin: Bool
    let profile: UserProfile?
}

struct UserProfile: Codable {
    let fullName: String?
    let bio: String?
    let profilePhoto: String?
    let username: String?
}

struct AuthResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: String?
    let userId: String
    let email: String
    // var (not let) so AuthStore can update it in place when the user
    // picks a new avatar — see AuthStore.updateAvatarId.
    var avatarId: String? = nil
}

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

struct RegisterRequest: Encodable {
    let email: String
    let password: String
    let fullName: String
}

// MARK: - Trip

struct Trip: Codable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let coverPhotoUrl: String?
    var coverPhotoAttribution: String? = nil
    var coverPhotoAttributionUrl: String? = nil
    let plannedStartDate: String?
    let plannedEndDate: String?
    let actualStartDate: String?
    let actualEndDate: String?
    let visibility: String
    let country: String?
    let city: String?
    let isDraft: Bool
    let isPlanning: Bool
    let createdAt: Date
    let ownerId: String
    let entryCount: Int
    let dayCount: Int
    let destinations: [TripDestination]

    var coverURL: URL? {
        guard let str = coverPhotoUrl else { return nil }
        return URL(string: str)
    }

    var destinationSummary: String {
        if !destinations.isEmpty {
            if destinations.count == 1 {
                return "\(destinations[0].city), \(destinations[0].country)"
            }
            return "\(destinations[0].city) + \(destinations.count - 1) more"
        }
        if let city = city, let country = country {
            return "\(city), \(country)"
        }
        return "Unknown destination"
    }

    var primaryDestination: TripDestination? {
        destinations.first
    }
}

struct TripDestination: Codable, Identifiable {
    let id: String
    let country: String
    let city: String
    let orderIndex: Int
}

struct CreateTripRequest: Encodable {
    let title: String
    let visibility: String
    let plannedStartDate: String?
    let plannedEndDate: String?
}

struct UpdateTripRequest: Encodable {
    let title: String?
    let visibility: String?
    let isDraft: Bool?
    let isPlanning: Bool?
    let coverPhotoUrl: String?
    let coverPhotoAttribution: String?
    let coverPhotoAttributionUrl: String?

    init(
        title: String? = nil,
        visibility: String? = nil,
        isDraft: Bool? = nil,
        isPlanning: Bool? = nil,
        coverPhotoUrl: String? = nil,
        coverPhotoAttribution: String? = nil,
        coverPhotoAttributionUrl: String? = nil
    ) {
        self.title = title
        self.visibility = visibility
        self.isDraft = isDraft
        self.isPlanning = isPlanning
        self.coverPhotoUrl = coverPhotoUrl
        self.coverPhotoAttribution = coverPhotoAttribution
        self.coverPhotoAttributionUrl = coverPhotoAttributionUrl
    }
}

struct SubmitTripRequest: Encodable {
    let message: String?
}

struct SubmitTripResponse: Decodable {
    let submissionId: String
    let status: String
}

struct TripSubmission: Decodable {
    let id: String
    let tripId: String
    let status: String  // "pending" | "approved" | "rejected"
    let message: String?
    let rejectionReason: String?
    let createdAt: Date
}

// MARK: - Unsplash photo picker

struct UnsplashPhoto: Decodable, Identifiable {
    let id: String
    let urls: UnsplashUrls
    let description: String?
    let altDescription: String?
    let user: UnsplashUser?

    var thumbURL: URL? { URL(string: urls.small) }
    var fullURL: URL? { URL(string: urls.regular) }
    var attribution: String { user?.name ?? "Unsplash" }

    var attributionUrl: String? {
        guard let username = user?.username else { return nil }
        return "https://unsplash.com/@\(username)?utm_source=board_postal&utm_medium=referral"
    }
}

struct UnsplashUrls: Decodable {
    let small: String
    let regular: String
    let full: String
}

struct UnsplashUser: Decodable {
    let name: String
    let username: String?
}

struct UnsplashSearchResult: Decodable {
    let results: [UnsplashPhoto]
    let total: Int?
}

// MARK: - Trip Entry (Journal)

struct TripEntry: Codable, Identifiable {
    let id: String
    let tripId: String
    let title: String?
    let content: String
    let entryDate: String?
    let placeName: String?
    let orderIndex: Int
    let visibility: String
    let isDraft: Bool
    let createdAt: Date
    let updatedAt: Date?
}

struct CreateEntryRequest: Encodable {
    let title: String?
    let content: String
    let entryDate: String?
    let placeId: String?
    let orderIndex: Int
    let visibility: String
}

// MARK: - Trip Day (Planning)

struct TripDay: Codable, Identifiable {
    let id: String
    // Server doesn't include tripId on day rows (it's in the URL path).
    // Optional because the wire response omits the URL-scoped trip identifier.
    let tripId: String?
    let dayNumber: Int
    let title: String?
    let date: String?      // "yyyy-MM-dd" string
    let orderIndex: Int
    let items: [TripDayItem]

    private enum CodingKeys: String, CodingKey {
        case id, tripId, dayNumber, title, date, orderIndex, items
    }

    init(
        id: String,
        tripId: String?,
        dayNumber: Int,
        title: String?,
        date: String?,
        orderIndex: Int,
        items: [TripDayItem]
    ) {
        self.id = id
        self.tripId = tripId
        self.dayNumber = dayNumber
        self.title = title
        self.date = date
        self.orderIndex = orderIndex
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        tripId = try container.decodeIfPresent(String.self, forKey: .tripId)
        dayNumber = try container.decode(Int.self, forKey: .dayNumber)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        orderIndex = try container.decode(Int.self, forKey: .orderIndex)
        // Day creation returns the new day before it has an items collection.
        items = try container.decodeIfPresent([TripDayItem].self, forKey: .items) ?? []
    }

    var formattedDate: String? {
        guard let d = date else { return nil }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        guard let dt = parser.date(from: d) else {
            return d
        }
        let display = DateFormatter()
        display.dateFormat = "d MMM yyyy"
        return display.string(from: dt)
    }
}

struct TripDayItem: Codable, Identifiable {
    let id: String
    // Same rationale as TripDay.tripId — wire response doesn't include it.
    let tripDayId: String?
    let type: String
    // The persisted backend entity and GET projection permit legacy null titles.
    let title: String?
    let notes: String?
    let time: String?
    let orderIndex: Int
    let placeId: String?

    var itemType: DayItemType {
        DayItemType(rawValue: type) ?? .note
    }
}

struct CreateDayRequest: Encodable {
    let dayNumber: Int
    let title: String?
    let date: String?      // "yyyy-MM-dd"
    let orderIndex: Int
}

struct UpdateDayRequest: Encodable {
    let title: String?
    let date: String?
    let orderIndex: Int?
}

struct CreateDayItemRequest: Encodable {
    let type: String       // "place"|"transport"|"accommodation"|"note"
    let title: String
    let notes: String?
    let time: String?      // "HH:mm"
    let orderIndex: Int
    let placeId: String?
}

struct UpdateDayItemRequest: Encodable {
    let title: String?
    let notes: String?
    let time: String?
    let orderIndex: Int?
}

struct ReorderRequest: Encodable {
    let orderedIds: [String]
}

// MARK: - Collaborators

struct Collaborator: Codable, Identifiable {
    let id: String
    let userId: String
    let fullName: String
    let email: String
    let avatarUrl: String?
    let role: String
    let inviteAccepted: Bool
    let createdAt: Date

    var initials: String {
        let parts = fullName.components(
            separatedBy: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1))
                + String(parts[1].prefix(1))
        }
        return String(fullName.prefix(2))
            .uppercased()
    }
}

struct InviteCollaboratorRequest: Encodable {
    let email: String
    let role: String
}

enum DayItemType: String, Codable {
    case place          = "place"
    case transport      = "transport"
    case accommodation  = "accommodation"
    case note           = "note"

    var icon: String {
        switch self {
        case .place:         return "mappin"
        case .transport:     return "airplane"
        case .accommodation: return "bed.double"
        case .note:          return "note.text"
        }
    }
}

// MARK: - Place

struct Place: Codable, Identifiable {
    let id: String
    let name: String
    let category: String?
    let latitude: Double?
    let longitude: Double?
    let city: String?
    let country: String?
    let description: String?
}

struct TripPlace: Codable, Identifiable {
    let id: String
    let tripId: String
    let placeId: String
    let placeName: String
    let category: String?
    let latitude: Double?
    let longitude: Double?
    let notes: String?
    let orderIndex: Int
    let imageUrl: String?
}

// MARK: - Place search

struct PlaceSuggestion: Identifiable, Decodable {
    let id: String
    let name: String
    let address: String?
    let category: String?
    let latitude: Double?
    let longitude: Double?
    let osmType: String?
    let osmId: Int?

    // No city/country from autocomplete — derive from address string as fallback
    var subtitle: String {
        address?.components(separatedBy: ",")
            .dropFirst()
            .prefix(2)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: ", ")
            ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case id = "placeId"
        case name, address, category
        case osmType, osmId
        case lat, lng
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // placeId comes as String from backend
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else if let n = try? c.decode(Int.self, forKey: .id) {
            id = String(n)
        } else {
            id = UUID().uuidString
        }

        name = (try? c.decode(String.self, forKey: .name)) ?? "Unknown"
        address = try? c.decode(String.self, forKey: .address)
        category = try? c.decode(String.self, forKey: .category)
        osmType = try? c.decode(String.self, forKey: .osmType)
        osmId = try? c.decode(Int.self, forKey: .osmId)

        // lat is a String in Nominatim response
        if let s = try? c.decode(String.self, forKey: .lat) {
            latitude = Double(s)
        } else if let d = try? c.decode(Double.self, forKey: .lat) {
            latitude = d
        } else {
            latitude = nil
        }

        // lng (not lon) is also a String
        if let s = try? c.decode(String.self, forKey: .lng) {
            longitude = Double(s)
        } else if let d = try? c.decode(Double.self, forKey: .lng) {
            longitude = d
        } else {
            longitude = nil
        }
    }
}

struct CreatePlaceRequest: Encodable {
    let name: String
    let category: String?
    let latitude: Double?
    let longitude: Double?
    let city: String?
    let country: String?
    let description: String?
}

struct AddPlaceToTripRequest: Encodable {
    let placeId: String
    let notes: String?
    let orderIndex: Int
    let imageUrl: String?
}

// MARK: - Media

struct MediaAsset: Codable, Identifiable {
    let id: String
    let fileUrl: String
    let fileName: String?
    let mimeType: String?
    let width: Int?
    let height: Int?
    let altText: String?

    var url: URL? { URL(string: fileUrl) }
}

struct TripMediaAsset: Codable, Identifiable {
    let id: String
    let mediaAssetId: String
    let fileUrl: String
    let fileName: String?
    let caption: String?
    let placeName: String?
    let isCover: Bool
    let orderIndex: Int

    var url: URL? { URL(string: fileUrl) }
}

// MARK: - Explore / Featured

struct FeaturedTrip: Decodable, Identifiable {
    let id: String
    let tripId: String
    let editorNote: String?
    let month: String?
    let orderIndex: Int
    let trip: FeaturedTripPreview?
    let owner: FeaturedTripOwner?
}

struct FeaturedTripPreview: Decodable, Identifiable {
    let id: String
    let title: String
    let coverPhotoUrl: String?
    var coverPhotoAttribution: String? = nil
    var coverPhotoAttributionUrl: String? = nil
    let destinations: [FeaturedDestination]
    let entryCount: Int
    let placeCount: Int?

    var coverURL: URL? {
        guard let s = coverPhotoUrl else { return nil }
        return URL(string: s)
    }

    var destinationSummary: String {
        destinations.prefix(2)
            .map { "\($0.country): \($0.city ?? "")" }
            .joined(separator: " · ")
    }
}

struct FeaturedDestination: Decodable {
    let country: String
    let city: String?
}

struct FeaturedTripOwner: Decodable {
    let id: String
    let fullName: String?
    let avatarUrl: String?
    let avatarId: String?
}

struct PublicTripDetail: Decodable, Identifiable {
    let id: String
    let title: String
    let coverPhotoUrl: String?
    var coverPhotoAttribution: String? = nil
    var coverPhotoAttributionUrl: String? = nil
    let plannedStartDate: String?
    let plannedEndDate: String?
    let visibility: String
    let country: String?
    let city: String?
    let createdAt: Date
    let destinations: [TripDestination]
    let entries: [TripEntry]
    let places: [TripPlace]
    let owner: FeaturedTripOwner?
    let isFollowingAuthor: Bool
    let isSaved: Bool

    var coverURL: URL? {
        guard let s = coverPhotoUrl else { return nil }
        return URL(string: s)
    }
}

// MARK: - Paginated response wrapper
struct PaginatedResponse<T: Decodable>: Decodable {
    let total: Int
    let page: Int
    let pageSize: Int
    let items: [T]
}

// MARK: - Generic message response
struct MessageResponse: Decodable {
    let message: String
}

// MARK: - Social v2: PublicProfile / PublicTripCard / Paginated
// Mirrors backend DTOs verified live in UsersController + SavedTripsController.
// Backend Guid → JSON string; the rest of this file types ids as String for
// consistency, so these new types follow suit (no UUID type).

struct PublicProfile: Codable, Identifiable {
    let id: String
    let fullName: String?
    let bio: String?
    let avatarUrl: String?
    let avatarId: String?
    let followerCount: Int
    let followingCount: Int
    let publicTripCount: Int
    let isFollowing: Bool
}

struct FollowedUser: Codable, Identifiable {
    let id: String
    let fullName: String?
    let avatarUrl: String?
    let avatarId: String?
    let publicTripCount: Int
}

struct TripCardOwner: Codable, Identifiable {
    let id: String
    let fullName: String
    let avatarUrl: String?
    let avatarId: String?
}

// Backend TripDestinationDto.City is nullable, but the existing `TripDestination`
// in this file declares `city: String` (non-optional). A separate type is used
// here to match the wire shape exactly without modifying TripDestination.
struct PublicTripDestination: Codable, Identifiable {
    let id: String
    let country: String
    let city: String?
    let orderIndex: Int
}

struct PublicTripCard: Codable, Identifiable {
    let id: String
    let title: String
    let coverPhotoUrl: String?
    var coverPhotoAttribution: String? = nil
    var coverPhotoAttributionUrl: String? = nil
    let createdAt: Date
    let destinations: [PublicTripDestination]
    let entryCount: Int
    let placeCount: Int
    let owner: TripCardOwner
    let isFollowingAuthor: Bool
    let isSaved: Bool

    var coverURL: URL? {
        guard let coverPhotoUrl else { return nil }
        return URL(string: coverPhotoUrl)
    }

    var destinationSummary: String {
        guard let first = destinations.first else { return "Unknown destination" }
        let firstName = [first.city, first.country]
            .compactMap { $0 }
            .joined(separator: ", ")
        return destinations.count == 1
            ? firstName
            : "\(firstName) + \(destinations.count - 1) more"
    }
}

// Codable variant used by /users/{id}/trips, /me/saved, /me/following.
// It shares the live backend envelope: { total, page, pageSize, items }.
struct Paginated<T: Codable>: Codable {
    let total: Int
    let page: Int
    let pageSize: Int
    let items: [T]
}

// PUT /api/users/me body. PATCH-over-PUT semantics:
//   nil = leave field unchanged
//   ""  = explicit clear (bio, profilePhotoUrl, avatarId; fullName cannot be cleared)
//
// avatarId specifically: send "" (empty string) to clear the user's avatar
// (backend's UserSocialService treats empty string as "set to NULL"). Send
// a real avatar ID string to set it. nil leaves the existing value alone.
struct UpdateProfileRequest: Encodable {
    let fullName: String?
    let bio: String?
    let profilePhotoUrl: String?
    let avatarId: String?

    // Explicit CodingKeys — defensive against any Encodable-existential
    // opening quirk in JSONEncoder.encode(body as any Encodable). Pins the
    // wire keys to exactly what the backend reads (camelCase). Removing
    // these falls back to synthesised keys which SHOULD be identical, but
    // we hit avatarId-not-landing in production so we're locking it in.
    enum CodingKeys: String, CodingKey {
        case fullName
        case bio
        case profilePhotoUrl
        case avatarId
    }

    init(
        fullName: String? = nil,
        bio: String? = nil,
        profilePhotoUrl: String? = nil,
        avatarId: String? = nil
    ) {
        self.fullName = fullName
        self.bio = bio
        self.profilePhotoUrl = profilePhotoUrl
        self.avatarId = avatarId
    }
}

struct FollowResponse: Decodable {
    let isFollowing: Bool
}

struct SaveResponse: Decodable {
    let isSaved: Bool
}
