#if DEBUG
import SwiftUI

enum Build3VisualScenario: String {
    case createStyle, savedCard, savedDetail, placesList, mapSelection
    case placeDetail, missingCoordinates, photoPicker, photoLoading, accessibility

    static var current: Self? {
        let prefix = "--build3-visual-scenario="
        guard let value = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix(prefix) }) else { return nil }
        return Self(rawValue: String(value.dropFirst(prefix.count)))
    }
}

struct Build3VisualScenarioView: View {
    let scenario: Build3VisualScenario

    var body: some View {
        Group {
            switch scenario {
            case .createStyle:
                createView
            case .savedCard:
                ScrollView { PublicTripCardView(trip: card).padding(20) }
            case .savedDetail:
                detailSummary
            case .placesList:
                VStack(spacing: 0) { PlaceRow(tripPlace: place) {} ; BPDivider() }.padding(.top, 80)
            case .mapSelection, .placeDetail:
                ItineraryPlaceDetailSheet(place: place)
            case .missingCoordinates:
                ItineraryPlaceDetailSheet(place: missingPlace)
            case .photoPicker:
                TripPhotoPickerView(tripId: "visual-trip") {}
            case .photoLoading:
                photoLoading
            case .accessibility:
                createView.environment(\.dynamicTypeSize, .accessibility3)
            }
        }
        .background(Color.bpBackground)
    }

    private var createView: some View {
        let model = CreateTripViewModel()
        model.title = "A Weekend in Warsaw"
        model.isPlanning = true
        model.destinations = [DraftDestination(city: "Warsaw", country: "Poland")]
        model.currentStep = 3
        return CreateTripView(viewModel: model)
    }

    private var detailSummary: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Rectangle().fill(Color.bpPrimaryDeep).frame(height: 280)
                Text(card.title).font(.bpHeadline).foregroundColor(.bpInk)
                Text("Warsaw, Poland").font(.bpBody).foregroundColor(.bpTextSecondary)
                BPSectionHeader(title: "Journal")
                Text("A deterministic public-trip detail reached through the shared Explore route.")
                    .font(.bpBody).foregroundColor(.bpInk)
            }.padding(20)
        }
    }

    private var photoLoading: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.fill").font(.system(size: 72)).foregroundColor(.bpCobalt)
            ProgressView().tint(.bpCobalt)
            Text("Loading selected photos…").font(.bpBody).foregroundColor(.bpTextSecondary)
            Text("Selections remain available if loading or upload fails.")
                .font(.bpCaption).foregroundColor(.bpTextMuted)
        }.padding(24)
    }

    private var card: PublicTripCard {
        PublicTripCard(id: "visual-saved-trip", title: "Warsaw Through Courtyards",
                       coverPhotoUrl: nil, createdAt: Date(timeIntervalSince1970: 0),
                       destinations: [PublicTripDestination(id: "destination", country: "Poland", city: "Warsaw", orderIndex: 0)],
                       entryCount: 4, placeCount: 3,
                       owner: TripCardOwner(id: "visual-owner", fullName: "Boardpostal Traveller", avatarUrl: nil, avatarId: nil),
                       isFollowingAuthor: false, isSaved: true)
    }

    private var place: TripPlace {
        TripPlace(id: "visual-place", tripId: "visual-trip", placeId: "stored-place",
                  placeName: "Stare Miasto", category: "landmark", latitude: 52.2497,
                  longitude: 21.0122, notes: "Warsaw Old Town", orderIndex: 0, imageUrl: nil)
    }

    private var missingPlace: TripPlace {
        TripPlace(id: "visual-missing-place", tripId: "visual-trip", placeId: "stored-missing-place",
                  placeName: "Saved place without coordinates", category: nil, latitude: nil,
                  longitude: nil, notes: nil, orderIndex: 1, imageUrl: nil)
    }
}
#endif
