import SwiftUI
import MapKit
import Combine

// MARK: - TripMapAnnotation

struct TripMapAnnotation: Identifiable {
    let id: String
    let tripId: String
    let tripTitle: String
    let city: String
    let country: String
    var coordinate: CLLocationCoordinate2D
    let color: Color
    let trip: Trip
}

// MARK: - WorldMapViewModel

@MainActor
final class WorldMapViewModel: ObservableObject {
    @Published var trips: [Trip] = []
    @Published var isLoading = false
    @Published var selectedTrip: Trip? = nil
    @Published var error: String? = nil
    @Published var annotations: [TripMapAnnotation] = []

    private let api = APIClient.shared

    private let pinColors: [Color] = [
        .bpCobalt, .bpSaffron, .bpAzure,
        Color(hex: "#E05C5C"), Color(hex: "#2ECC8F")
    ]

    func pinColor(for tripId: String) -> Color {
        let colors: [Color] = [
            .bpCobalt, .bpSaffron, .bpAzure,
            Color(hex: "#E05C5C"), Color(hex: "#2ECC8F")
        ]
        let hash = tripId.utf8.reduce(0) { ($0 &+ Int($1)) }
        return colors[abs(hash) % colors.count]
    }

    func loadTrips() async {
        isLoading = true
        error = nil
        annotations = []
        do {
            let result: [Trip] = try await api.request(.trips)
            trips = result
            let queue = trips.flatMap { trip in
                trip.destinations.map { dest in
                    (tripId: trip.id, city: dest.city, country: dest.country, trip: trip)
                }
            }
            await geocodeAll(destinations: queue)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func geocodeAll(
        destinations: [(tripId: String, city: String, country: String, trip: Trip)]
    ) async {
        await withTaskGroup(of: TripMapAnnotation?.self) { group in
            for dest in destinations {
                let color = self.pinColor(for: dest.tripId)
                group.addTask {
                    let geocoder = CLGeocoder()
                    let query = "\(dest.city), \(dest.country)"
                    guard let placemark = try? await geocoder
                        .geocodeAddressString(query).first,
                          let loc = placemark.location
                    else { return nil }
                    return TripMapAnnotation(
                        id: "\(dest.tripId)-\(dest.city)",
                        tripId: dest.tripId,
                        tripTitle: dest.trip.title,
                        city: dest.city,
                        country: dest.country,
                        coordinate: loc.coordinate,
                        color: color,
                        trip: dest.trip
                    )
                }
            }
            for await annotation in group {
                if let a = annotation {
                    await MainActor.run { self.annotations.append(a) }
                }
            }
        }
    }
}

// MARK: - WorldMapView

struct WorldMapView: View {
    @StateObject private var viewModel = WorldMapViewModel()
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 30, longitude: 15),
            span: MKCoordinateSpan(latitudeDelta: 80, longitudeDelta: 80)
        )
    )

    var body: some View {
        ZStack(alignment: .bottom) {
            // Map layer
            Map(position: $cameraPosition) {
                ForEach(viewModel.annotations) { annotation in
                    Annotation(annotation.city, coordinate: annotation.coordinate) {
                        TripPin(
                            color: annotation.color,
                            isSelected: viewModel.selectedTrip?.id == annotation.tripId
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if viewModel.selectedTrip?.id == annotation.tripId {
                                    viewModel.selectedTrip = nil
                                } else {
                                    viewModel.selectedTrip = annotation.trip
                                }
                            }
                        }
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .ignoresSafeArea(edges: .bottom)

            // Trip count badge (top-left)
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(viewModel.trips.count)")
                            .font(.bpTitle)
                            .foregroundColor(.bpInk)

                        Text(viewModel.trips.count == 1 ? "trip" : "trips")
                            .font(.bpCaption)
                            .foregroundColor(.bpTextMuted)
                    }
                    .padding(12)
                    .background(Color.white)
                    .overlay(
                        Rectangle()
                            .stroke(Color.bpBorder, lineWidth: 1)
                    )

                    Spacer()
                }
                .padding(.top, 8)
                .padding(.horizontal, 20)

                Spacer()
            }

            // Selected trip card (bottom)
            if let trip = viewModel.selectedTrip {
                SelectedTripCard(trip: trip) {
                    viewModel.selectedTrip = nil
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle("World Map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            UITabBar.appearance().backgroundColor = .white
            UITabBar.appearance().barTintColor = .white
        }
        .task {
            await viewModel.loadTrips()
        }
    }
}

// MARK: - TripPin

private struct TripPin: View {
    let color: Color
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(
                    width: isSelected ? 20 : 12,
                    height: isSelected ? 20 : 12
                )

            if isSelected {
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 20, height: 20)
            }
        }
        .shadow(color: color.opacity(0.4), radius: 4, x: 0, y: 2)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - SelectedTripCard

private struct SelectedTripCard: View {
    let trip: Trip
    let onDismiss: () -> Void

    var body: some View {
        NavigationLink(destination: TripDetailView(trip: trip)) {
            HStack(spacing: 0) {
                // Cover thumbnail
                if let url = trip.coverURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        default:
                            Rectangle().fill(Color.bpPrimaryDeep)
                        }
                    }
                    .frame(width: 80, height: 80)
                    .clipped()
                } else {
                    Rectangle()
                        .fill(Color.bpPrimaryDeep)
                        .frame(width: 80, height: 80)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(trip.destinationSummary.uppercased())
                        .font(.bpCaption)
                        .foregroundColor(.bpTextMuted)

                    Text(trip.title)
                        .font(.bpSubhead)
                        .foregroundColor(.bpInk)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if trip.isPlanning {
                            BPBadge("Planning", color: .bpAzure)
                        }
                        if trip.isDraft {
                            BPBadge("Draft", color: .bpTextMuted)
                        }
                    }
                }
                .padding(14)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .foregroundColor(.bpTextMuted)
                        .font(.system(size: 12))
                }
                .padding(16)
            }
            .frame(height: 80)
            .background(Color.white)
            .overlay(
                Rectangle()
                    .stroke(Color.bpBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

private extension DateFormatter {
    static let mapPreviewFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

#Preview("World Map") {
    NavigationStack {
        WorldMapPreviewContent()
    }
}

private struct WorldMapPreviewContent: View {
    @StateObject private var viewModel = WorldMapViewModel()
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 38, longitude: 30),
            span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 40)
        )
    )

    private var mockTrips: [Trip] {
        [
            Trip(
                id: "1",
                title: "Summer in Istanbul",
                description: nil,
                coverPhotoUrl: nil,
                plannedStartDate: nil,
                plannedEndDate: nil,
                actualStartDate: nil,
                actualEndDate: nil,
                visibility: "Public",
                country: nil,
                city: nil,
                isDraft: false,
                isPlanning: false,
                createdAt: DateFormatter.mapPreviewFormatter.date(from: "2025-06-15") ?? Date(),
                ownerId: "owner-1",
                entryCount: 0,
                dayCount: 0,
                destinations: [
                    TripDestination(id: "1", country: "Turkey", city: "Istanbul", orderIndex: 0)
                ]
            ),
            Trip(
                id: "2",
                title: "Santorini Sunsets",
                description: nil,
                coverPhotoUrl: nil,
                plannedStartDate: nil,
                plannedEndDate: nil,
                actualStartDate: nil,
                actualEndDate: nil,
                visibility: "Public",
                country: nil,
                city: nil,
                isDraft: false,
                isPlanning: true,
                createdAt: DateFormatter.mapPreviewFormatter.date(from: "2025-08-01") ?? Date(),
                ownerId: "owner-2",
                entryCount: 0,
                dayCount: 0,
                destinations: [
                    TripDestination(id: "3", country: "Greece", city: "Santorini", orderIndex: 0)
                ]
            ),
            Trip(
                id: "3",
                title: "Kyoto in Autumn",
                description: nil,
                coverPhotoUrl: nil,
                plannedStartDate: nil,
                plannedEndDate: nil,
                actualStartDate: nil,
                actualEndDate: nil,
                visibility: "Private",
                country: nil,
                city: nil,
                isDraft: false,
                isPlanning: false,
                createdAt: DateFormatter.mapPreviewFormatter.date(from: "2025-10-05") ?? Date(),
                ownerId: "owner-3",
                entryCount: 0,
                dayCount: 0,
                destinations: [
                    TripDestination(id: "5", country: "Japan", city: "Kyoto", orderIndex: 0)
                ]
            )
        ]
    }

    private var mockAnnotations: [TripMapAnnotation] {
        let colors: [Color] = [.bpCobalt, .bpSaffron, .bpAzure]
        return [
            TripMapAnnotation(
                id: "1-1", tripId: "1", tripTitle: "Summer in Istanbul",
                city: "Istanbul", country: "Turkey",
                coordinate: CLLocationCoordinate2D(latitude: 41.0, longitude: 28.9),
                color: colors[0], trip: mockTrips[0]
            ),
            TripMapAnnotation(
                id: "2-3", tripId: "2", tripTitle: "Santorini Sunsets",
                city: "Santorini", country: "Greece",
                coordinate: CLLocationCoordinate2D(latitude: 36.4, longitude: 25.4),
                color: colors[1], trip: mockTrips[1]
            ),
            TripMapAnnotation(
                id: "3-5", tripId: "3", tripTitle: "Kyoto in Autumn",
                city: "Kyoto", country: "Japan",
                coordinate: CLLocationCoordinate2D(latitude: 35.0, longitude: 135.7),
                color: colors[2], trip: mockTrips[2]
            )
        ]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $cameraPosition) {
                ForEach(mockAnnotations) { annotation in
                    Annotation(annotation.city, coordinate: annotation.coordinate) {
                        TripPin(
                            color: annotation.color,
                            isSelected: viewModel.selectedTrip?.id == annotation.tripId
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if viewModel.selectedTrip?.id == annotation.tripId {
                                    viewModel.selectedTrip = nil
                                } else {
                                    viewModel.selectedTrip = annotation.trip
                                }
                            }
                        }
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .ignoresSafeArea(edges: .bottom)

            // Trip count badge
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("3")
                            .font(.bpTitle)
                            .foregroundColor(.bpInk)

                        Text("trips")
                            .font(.bpCaption)
                            .foregroundColor(.bpTextMuted)
                    }
                    .padding(12)
                    .background(Color.white)
                    .overlay(
                        Rectangle()
                            .stroke(Color.bpBorder, lineWidth: 1)
                    )

                    Spacer()
                }
                .padding(.top, 8)
                .padding(.horizontal, 20)

                Spacer()
            }

            // Selected trip card
            SelectedTripCard(trip: mockTrips[0]) {}
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
        }
        .navigationTitle("World Map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}
