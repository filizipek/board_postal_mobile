import Foundation

// MARK: - API Endpoints
// All endpoints mirror the existing .NET backend exactly.
// Change baseURL to your production URL before App Store submission.

enum APIEndpoint {
    // MARK: - Base
    // Driven by xcconfig (Debug.xcconfig / Release.xcconfig) → Info.plist key API_BASE_URL.
    static let baseURL: String = {
        guard let raw = Bundle.main.object(
                forInfoDictionaryKey: "API_BASE_URL") as? String,
              !raw.isEmpty else {
            fatalError("API_BASE_URL missing or invalid in Info.plist")
        }
        return raw
    }()

    // MARK: - Auth
    case register
    case login
    case refresh
    case revoke

    // MARK: - Trips
    case trips
    case trip(id: String)
    case tripPublic(id: String)
    case publicTrip(id: String)

    // MARK: - Destinations
    case destinations(tripId: String)
    case destination(tripId: String, destId: String)

    // MARK: - Entries (journal)
    case entries(tripId: String)
    case entry(tripId: String, entryId: String)

    // MARK: - Days (planning)
    case days(tripId: String)
    case day(tripId: String, dayId: String)
    case reorderDays(tripId: String)
    case dayItems(tripId: String, dayId: String)
    case dayItem(tripId: String, dayId: String, itemId: String)
    case reorderDayItems(tripId: String, dayId: String)

    // MARK: - Collaborators
    case collaborators(tripId: String)
    case collaborator(tripId: String, collaboratorId: String)

    // MARK: - Places
    case places
    case place(id: String)
    case tripPlaces(tripId: String)
    case tripPlace(tripId: String, placeId: String)

    // MARK: - Media
    case mediaUpload
    case tripMedia(tripId: String)
    case tripCover(tripId: String)

    // MARK: - Explore
    case exploreFeatured
    case exploreTrips
    case exploreFollowing
    case exploreUsers

    // MARK: - Submissions
    case submitTrip(tripId: String)
    case tripSubmission(tripId: String)
    case mySubmissions

    // MARK: - Profile
    case myProfile

    // MARK: - Proxy (geocoding, photos)
    case nominatimAutocomplete
    case unsplashSearch

    // MARK: - Profile v2 / Social v2
    case toggleFollow(userId: String)
    case userProfile(userId: String)
    case userTrips(userId: String, page: Int, pageSize: Int)
    case updateProfile
    case savedTrips(page: Int, pageSize: Int)
    case following(page: Int, pageSize: Int)
    case toggleSaveTrip(tripId: String)

    // MARK: - URL resolution
    var path: String {
        switch self {
        case .register:                      return "/api/auth/register"
        case .login:                         return "/api/auth/login"
        case .refresh:                       return "/api/auth/refresh"
        case .revoke:                        return "/api/auth/revoke"

        case .trips:                         return "/api/trips"
        case .trip(let id):                  return "/api/trips/\(id)"
        case .tripPublic(let id):            return "/api/trips/\(id)/public"
        case .publicTrip(let id):            return "/api/trips/\(id)/public"

        case .destinations(let tripId):      return "/api/trips/\(tripId)/destinations"
        case .destination(let t, let d):     return "/api/trips/\(t)/destinations/\(d)"

        case .entries(let tripId):           return "/api/trips/\(tripId)/entries"
        case .entry(let t, let e):           return "/api/trips/\(t)/entries/\(e)"

        case .days(let tripId):              return "/api/trips/\(tripId)/days"
        case .day(let t, let d):             return "/api/trips/\(t)/days/\(d)"
        case .reorderDays(let t):            return "/api/trips/\(t)/days/reorder"
        case .dayItems(let t, let d):        return "/api/trips/\(t)/days/\(d)/items"
        case .dayItem(let t, let d, let i):  return "/api/trips/\(t)/days/\(d)/items/\(i)"
        case .reorderDayItems(let t, let d): return "/api/trips/\(t)/days/\(d)/items/reorder"

        case .collaborators(let tripId):     return "/api/trips/\(tripId)/collaborators"
        case .collaborator(let t, let c):    return "/api/trips/\(t)/collaborators/\(c)"

        case .places:                        return "/api/places"
        case .place(let id):                 return "/api/places/\(id)"
        case .tripPlaces(let tripId):        return "/api/trips/\(tripId)/places"
        case .tripPlace(let t, let p):       return "/api/trips/\(t)/places/\(p)"

        case .mediaUpload:                   return "/api/media/upload"
        case .tripMedia(let tripId):         return "/api/trips/\(tripId)/media"
        case .tripCover(let tripId):         return "/api/trips/\(tripId)/cover"

        case .exploreFeatured:               return "/api/explore/featured"
        case .exploreTrips:                  return "/api/explore/trips"
        case .exploreFollowing:              return "/api/explore/following"
        case .exploreUsers:                  return "/api/explore/users"

        case .submitTrip(let tripId):        return "/api/trips/\(tripId)/submit"
        case .tripSubmission(let tripId):    return "/api/trips/\(tripId)/submission"
        case .mySubmissions:                 return "/api/users/me/submissions"

        case .myProfile:                     return "/api/users/me"

        case .nominatimAutocomplete:         return "/api/proxy/places/autocomplete"
        case .unsplashSearch:                return "/api/proxy/unsplash/search"

        // Profile v2 / Social v2
        case .toggleFollow(let userId):
            return "/api/users/\(userId)/follow"
        case .userProfile(let userId):
            return "/api/users/\(userId)"
        case .userTrips(let userId, let page, let pageSize):
            return "/api/users/\(userId)/trips?page=\(page)&pageSize=\(pageSize)"
        case .updateProfile:
            return "/api/users/me"
        case .savedTrips(let page, let pageSize):
            return "/api/users/me/saved?page=\(page)&pageSize=\(pageSize)"
        case .following(let page, let pageSize):
            return "/api/users/me/following?page=\(page)&pageSize=\(pageSize)"
        case .toggleSaveTrip(let tripId):
            return "/api/trips/\(tripId)/save"
        }
    }

    var url: URL {
        URL(string: APIEndpoint.baseURL + path)!
    }

    // MARK: - Query-string helpers

    static func nominatimSearch(query: String) -> URL {
        var components = URLComponents(
            string: baseURL + "/api/proxy/places/autocomplete"
        )!
        components.queryItems = [
            URLQueryItem(name: "input", value: query)
        ]
        return components.url!
    }

    static func unsplashSearch(query: String) -> URL {
        var components = URLComponents(
            string: baseURL + "/api/proxy/unsplash/search"
        )!
        components.queryItems = [
            URLQueryItem(name: "query", value: query)
        ]
        return components.url!
    }
}
