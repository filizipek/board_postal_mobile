import SwiftUI
import Combine

// MARK: - ExploreViewModel

@MainActor
protocol ExploreProviding {
    func fetchFeaturedTrips() async throws -> [FeaturedTrip]
    func fetchPublicTrips() async throws -> PaginatedResponse<PublicTripCard>
}

extension APIClient: ExploreProviding {
    func fetchFeaturedTrips() async throws -> [FeaturedTrip] {
        try await request(.exploreFeatured)
    }

    func fetchPublicTrips() async throws -> PaginatedResponse<PublicTripCard> {
        try await request(.exploreTrips)
    }
}

@MainActor
final class ExploreViewModel: ObservableObject {
    @Published var featuredTrips: [FeaturedTrip] = []
    @Published var recentTrips: [PublicTripCard] = []
    @Published var searchResults: [PublicTripCard] = []
    @Published var searchQuery: String = ""
    @Published var isLoading = false
    @Published var isSearching = false
    @Published var error: String?
    @Published var searchError: String?

    private let api: any ExploreProviding

    init(api: any ExploreProviding) {
        self.api = api
    }

    convenience init() {
        self.init(api: APIClient.shared)
    }

    var isShowingSearch: Bool {
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func loadFeed() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let featuredResponse = try await api.fetchFeaturedTrips()
            let recentResponse = try await api.fetchPublicTrips()
            featuredTrips = featuredResponse
            recentTrips = recentResponse.items
        } catch {
            self.error = error.localizedDescription
        }
    }

    func search() async {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            searchResults = []
            searchError = nil
            return
        }
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            let response = try await api.fetchPublicTrips()
            searchResults = response.items.filter {
                $0.title.localizedCaseInsensitiveContains(query)
                || $0.destinationSummary.localizedCaseInsensitiveContains(query)
            }
        } catch {
            searchResults = []
            searchError = error.localizedDescription
        }
    }
}

// MARK: - ExploreView

struct ExploreView: View {
    @StateObject private var viewModel = ExploreViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // BLOCK 1 — Dark editorial header
                editorialHeader

                // BLOCK 2 — Search bar
                searchBar

                // BLOCK 3 — Content
                if viewModel.isShowingSearch {
                    searchResultsSection
                } else if viewModel.isLoading && viewModel.featuredTrips.isEmpty {
                    skeletonSection
                } else {
                    feedContent
                }
            }
        }
        .background(Color.bpBackground)
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.inline)
        .bpNavigationStyle()
        .task {
            await viewModel.loadFeed()
        }
        .refreshable {
            await viewModel.loadFeed()
        }
    }

    // MARK: - Editorial header

    private var editorialHeader: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(Color.bpPrimaryDeep)
                .frame(height: 200)

            LinearGradient(
                colors: [
                    Color.bpPrimaryDeep.opacity(0.3),
                    Color.bpPrimaryDeep
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)

            VStack(alignment: .leading, spacing: 6) {
                Text("EDITOR'S PICKS")
                    .font(.bpLabel)
                    .foregroundColor(.bpAzure)
                    .tracking(2.0)

                ItalicLastWord(
                    text: "Stories from around the world.",
                    font: .bpTitle,
                    baseColor: .white
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(height: 200)
        .clipped()
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.bpTextMuted)
                .font(.system(size: 16))

            TextField("Search trips, destinations…", text: $viewModel.searchQuery)
                .font(.bpCallout)
                .foregroundColor(.bpInk)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit {
                    Task { await viewModel.search() }
                }

            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                    viewModel.searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.bpStone)
                        .font(.system(size: 16))
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color.white)
        .overlay(
            Rectangle()
                .stroke(Color.bpBorder, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Feed content

    private var feedContent: some View {
        VStack(spacing: 0) {
            // Featured stack
            if !viewModel.featuredTrips.isEmpty {
                VStack(spacing: 0) {
                    ForEach(viewModel.featuredTrips) { featured in
                        FeaturedCard(featured: featured)
                        BPDivider()
                    }
                }
            }

            // Recent trips grid
            if !viewModel.recentTrips.isEmpty {
                BPSectionHeader(title: "Recent Journeys")
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                let columns = [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ]

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(viewModel.recentTrips) { trip in
                        NavigationLink {
                            ExplorePublicTripView(tripId: trip.id, preview: nil)
                        } label: {
                            ExploreGridCell(trip: trip)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }

            // Empty state
            if viewModel.featuredTrips.isEmpty && viewModel.recentTrips.isEmpty && !viewModel.isLoading {
                BPEmptyState(
                    icon: "safari",
                    title: "Nothing to explore yet",
                    message: "Check back soon for featured trips and stories."
                )
            }
        }
    }

    // MARK: - Search results

    private var searchResultsSection: some View {
        VStack(spacing: 0) {
            if viewModel.isSearching {
                BPLoadingView()
                    .frame(height: 200)
            } else if viewModel.searchError != nil {
                BPEmptyState(
                    icon: "exclamationmark.triangle",
                    title: "Unable to search",
                    message: "Please try again."
                )
            } else if viewModel.searchResults.isEmpty {
                BPEmptyState(
                    icon: "magnifyingglass",
                    title: "No results",
                    message: "Try a different search term."
                )
            } else {
                BPSectionHeader(title: "\(viewModel.searchResults.count) results")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.searchResults.enumerated()), id: \.element.id) { index, trip in
                        NavigationLink {
                            ExplorePublicTripView(tripId: trip.id, preview: nil)
                        } label: {
                            SearchResultRow(trip: trip)
                        }
                        .buttonStyle(.plain)

                        if index < viewModel.searchResults.count - 1 {
                            BPDivider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Skeleton loading

    private var skeletonSection: some View {
        VStack(spacing: 0) {
            BPSectionHeader(title: "Featured")
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        SkeletonFeaturedCard()
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 24)

            BPSectionHeader(title: "Recent Journeys")
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            let columns = [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ]

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonGridCell()
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - FeaturedCard

struct FeaturedCard: View {
    let featured: FeaturedTrip

    var body: some View {
        guard let trip = featured.trip else {
            return AnyView(EmptyView())
        }
        return AnyView(
            NavigationLink(destination: ExplorePublicTripView(
                tripId: featured.tripId,
                preview: featured.trip
            )) {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
                    .background(
                        Group {
                            if let url = trip.coverURL {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let img):
                                        img.resizable().scaledToFill()
                                    default:
                                        LinearGradient.bpCoverGradient(for: trip.id)
                                    }
                                }
                            } else {
                                LinearGradient.bpCoverGradient(for: trip.id)
                            }
                        }
                        .clipped()
                    )
                    .overlay(alignment: .bottom) {
                        LinearGradient(
                            colors: [
                                .black.opacity(0.85),
                                .black.opacity(0.0)
                            ],
                            startPoint: .bottom,
                            endPoint: .init(x: 0.5, y: 0.35)
                        )
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 6) {
                            if let month = featured.month {
                                Text(month.uppercased())
                                    .font(BPFont.inter(size: 9, weight: .semibold))
                                    .foregroundColor(.bpSaffron)
                                    .tracking(1.4)
                            }

                            // Destination eyebrow
                            if !trip.destinations.isEmpty {
                                Text(
                                    trip.destinations
                                        .prefix(2)
                                        .map { "\($0.country.uppercased()): \($0.city?.uppercased() ?? "")" }
                                        .joined(separator: " · ")
                                )
                                .font(BPFont.inter(size: 9, weight: .semibold))
                                .foregroundColor(.bpSaffron)
                                .tracking(1.4)
                            }

                            ItalicLastWord(
                                text: trip.title,
                                font: BPFont.playfair(size: 28, weight: .bold),
                                baseColor: .white
                            )
                            .fixedSize(horizontal: false, vertical: true)

                            if let owner = featured.owner {
                                Text("A trip by " + (owner.fullName ?? ""))
                                    .font(BPFont.inter(size: 11, weight: .regular))
                                    .foregroundColor(.white.opacity(0.6))
                            }

                            if let note = featured.editorNote {
                                Text(note)
                                    .font(BPFont.inter(size: 11, weight: .regular).italic())
                                    .foregroundColor(.bpAzure)
                                    .lineLimit(2)
                            }

                            HStack(spacing: 4) {
                                if trip.entryCount > 0 {
                                    Text("\(trip.entryCount) entries")
                                }
                                if let pc = trip.placeCount, pc > 0 {
                                    Text("·")
                                    Text("\(pc) places")
                                }
                            }
                            .font(BPFont.inter(size: 11, weight: .regular))
                            .foregroundColor(.white.opacity(0.45))
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
            }
            .buttonStyle(.plain)
        )
    }
}

// MARK: - ExplorePublicTripView

struct ExplorePublicTripView: View {
    let tripId: String
    let preview: FeaturedTripPreview?
    @State private var detail: PublicTripDetail? = nil
    @State private var isLoading = true
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authStore: AuthStore

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                heroBlock

                // Author row — tappable name + avatar, optional Follow button.
                if let detail, let owner = detail.owner {
                    HStack(spacing: 12) {
                        NavigationLink {
                            PublicProfileView(userId: owner.id)
                        } label: {
                            HStack(spacing: 10) {
                                AsyncImage(url: owner.avatarUrl.flatMap(URL.init(string:))) { phase in
                                    switch phase {
                                    case .success(let img):
                                        img.resizable().scaledToFill()
                                    default:
                                        Color.bpStone
                                    }
                                }
                                .frame(width: 36, height: 36)
                                .clipShape(Circle())

                                Text(owner.fullName ?? "Traveller")
                                    .font(.bpBody)
                                    .foregroundColor(.bpInk)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        if owner.id != authStore.currentUser?.userId {
                            FollowButton(
                                userId: owner.id,
                                initialIsFollowing: detail.isFollowingAuthor
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }

                if let entries = detail?.entries, !entries.isEmpty {
                    BPSectionHeader(title: "Journal")
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    ForEach(entries) { entry in
                        EntryRow(entry: entry)
                        BPDivider()
                    }
                }

                if let places = detail?.places, !places.isEmpty {
                    BPSectionHeader(title: "Places")
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    ForEach(places) { place in
                        PlaceRow(tripPlace: place)
                        BPDivider()
                    }
                }

                if isLoading {
                    BPLoadingView()
                        .frame(height: 200)
                }
            }
        }
        .background(Color.bpBackground)
        .navigationBarHidden(true)
        .overlay(alignment: .top) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 56)
        }
        .overlay(alignment: .topTrailing) {
            if let detail {
                SaveButton(tripId: detail.id, initialIsSaved: detail.isSaved)
                    .padding(.top, 56)
                    .padding(.trailing, 16)
            }
        }
        .ignoresSafeArea(edges: .top)
        .task {
            do {
                detail = try await APIClient.shared.request(.publicTrip(id: tripId))
            } catch {
                // detail stays nil; preview keeps the hero populated
            }
            isLoading = false
        }
    }

    private var heroBlock: some View {
        let dests = detail?.destinations ?? []
        let title = detail?.title ?? preview?.title ?? ""
        let coverURL = detail?.coverURL ?? preview?.coverURL

        return Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 380)
            .background(
                Group {
                    if let url = coverURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            default:
                                LinearGradient.bpCoverGradient(for: tripId)
                            }
                        }
                    } else {
                        LinearGradient.bpCoverGradient(for: tripId)
                    }
                }
                .clipped()
            )
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        .black.opacity(0.85),
                        .black.opacity(0.0)
                    ],
                    startPoint: .bottom,
                    endPoint: .init(x: 0.5, y: 0.35)
                )
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    if !dests.isEmpty {
                        Text(
                            dests.prefix(2)
                                .map { "\($0.country.uppercased()): \($0.city.uppercased())" }
                                .joined(separator: " · ")
                        )
                        .font(BPFont.inter(size: 9, weight: .semibold))
                        .foregroundColor(.bpSaffron)
                        .tracking(1.4)
                    }

                    ItalicLastWord(
                        text: title,
                        font: BPFont.playfair(size: 32, weight: .bold),
                        baseColor: .white
                    )
                    .fixedSize(horizontal: false, vertical: true)

                    if let owner = detail?.owner, let name = owner.fullName {
                        Text("A trip by \(name)")
                            .font(BPFont.inter(size: 11, weight: .regular))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
    }
}

// MARK: - ExploreGridCell

struct ExploreGridCell: View {
    private let title: String
    private let coverURL: URL?
    private let createdAt: Date
    private let destinationSummary: String

    init(trip: PublicTripCard) {
        title = trip.title
        coverURL = trip.coverURL
        createdAt = trip.createdAt
        destinationSummary = trip.destinationSummary
    }

    init(trip: Trip) {
        title = trip.title
        coverURL = trip.coverURL
        createdAt = trip.createdAt
        destinationSummary = trip.destinationSummary
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: createdAt)
    }

    var body: some View {
        BPCard {
            VStack(spacing: 0) {
                // Cover
                ZStack(alignment: .bottomLeading) {
                    if let url = coverURL {
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
                        .frame(height: 140)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    } else {
                        Rectangle()
                            .fill(Color.bpPrimaryDeep)
                            .frame(height: 140)
                    }
                }
                .frame(height: 140)
                .clipped()

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.bpCallout)
                        .foregroundColor(.bpInk)
                        .lineLimit(1)

                    Text(destinationSummary)
                        .font(.bpCaption)
                        .foregroundColor(.bpTextMuted)
                        .lineLimit(1)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - SearchResultRow

struct SearchResultRow: View {
    private let title: String
    private let coverURL: URL?
    private let createdAt: Date
    private let destinationSummary: String

    init(trip: PublicTripCard) {
        title = trip.title
        coverURL = trip.coverURL
        createdAt = trip.createdAt
        destinationSummary = trip.destinationSummary
    }

    init(trip: Trip) {
        title = trip.title
        coverURL = trip.coverURL
        createdAt = trip.createdAt
        destinationSummary = trip.destinationSummary
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: createdAt)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let url = coverURL {
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
                .frame(width: 64, height: 64)
                .clipped()
            } else {
                Rectangle()
                    .fill(Color.bpPrimaryDeep)
                    .frame(width: 64, height: 64)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.bpBodyBold)
                    .foregroundColor(.bpInk)
                    .lineLimit(1)

                Text(destinationSummary)
                    .font(.bpCaption)
                    .foregroundColor(.bpTextMuted)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(formattedDate)
                        .font(.bpCaption)
                        .foregroundColor(.bpTextMuted)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.bpStone)
        }
        .padding(16)
        .background(Color.white)
    }
}

// MARK: - SkeletonFeaturedCard

private struct SkeletonFeaturedCard: View {
    @State private var shimmer = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(Color.bpPrimaryDeep.opacity(0.6))
                .frame(width: 280, height: 380)

            VStack(alignment: .leading, spacing: 8) {
                Rectangle()
                    .fill(Color.white.opacity(shimmer ? 0.15 : 0.08))
                    .frame(width: 100, height: 12)

                Rectangle()
                    .fill(Color.white.opacity(shimmer ? 0.15 : 0.08))
                    .frame(width: 180, height: 18)

                Rectangle()
                    .fill(Color.white.opacity(shimmer ? 0.15 : 0.08))
                    .frame(width: 120, height: 12)
            }
            .padding(16)
        }
        .frame(width: 280, height: 380)
        .clipped()
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                shimmer = true
            }
        }
    }
}

// MARK: - SkeletonGridCell

private struct SkeletonGridCell: View {
    @State private var shimmer = false

    var body: some View {
        BPCard {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.bpStone.opacity(shimmer ? 0.4 : 0.2))
                    .frame(height: 140)

                VStack(alignment: .leading, spacing: 6) {
                    Rectangle()
                        .fill(Color.bpStone.opacity(shimmer ? 0.4 : 0.2))
                        .frame(height: 14)

                    Rectangle()
                        .fill(Color.bpStone.opacity(shimmer ? 0.4 : 0.2))
                        .frame(width: 80, height: 10)
                }
                .padding(10)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                shimmer = true
            }
        }
    }
}

// MARK: - Previews

private extension DateFormatter {
    static let explorePreviewFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

#Preview("Explore — Feed") {
    NavigationStack {
        ExplorePreviewContent()
    }
}

private struct ExplorePreviewContent: View {
    @StateObject private var viewModel = ExploreViewModel()

    private var mockFeatured: [FeaturedTrip] {
        [
            FeaturedTrip(
                id: "1",
                tripId: "1",
                editorNote: "A deeply personal account of discovering Istanbul's hidden tea gardens and ancient hammams.",
                month: "June 2025",
                orderIndex: 0,
                trip: FeaturedTripPreview(
                    id: "1",
                    title: "Summer in Istanbul",
                    coverPhotoUrl: nil,
                    destinations: [
                        FeaturedDestination(country: "Turkey", city: "Istanbul")
                    ],
                    entryCount: 6,
                    placeCount: 4
                ),
                owner: FeaturedTripOwner(
                    id: "owner-1",
                    fullName: "Elena Vasquez",
                    avatarUrl: nil,
                    avatarId: nil
                )
            ),
            FeaturedTrip(
                id: "2",
                tripId: "2",
                editorNote: nil,
                month: "August 2025",
                orderIndex: 1,
                trip: FeaturedTripPreview(
                    id: "2",
                    title: "Santorini Sunsets",
                    coverPhotoUrl: nil,
                    destinations: [
                        FeaturedDestination(country: "Greece", city: "Santorini")
                    ],
                    entryCount: 3,
                    placeCount: 2
                ),
                owner: FeaturedTripOwner(
                    id: "owner-2",
                    fullName: "Marco Rossi",
                    avatarUrl: nil,
                    avatarId: nil
                )
            )
        ]
    }

    private var mockRecent: [Trip] {
        [
            Trip(
                id: "3",
                title: "Amalfi Coast Road Trip",
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
                createdAt: DateFormatter.explorePreviewFormatter.date(from: "2025-09-10") ?? Date(),
                ownerId: "owner-3",
                entryCount: 0,
                dayCount: 0,
                destinations: [TripDestination(id: "4", country: "Italy", city: "Amalfi", orderIndex: 0)]
            ),
            Trip(
                id: "4",
                title: "Porto & the Douro Valley",
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
                createdAt: DateFormatter.explorePreviewFormatter.date(from: "2025-07-20") ?? Date(),
                ownerId: "owner-4",
                entryCount: 0,
                dayCount: 0,
                destinations: [TripDestination(id: "5", country: "Portugal", city: "Porto", orderIndex: 0)]
            ),
            Trip(
                id: "5",
                title: "Moroccan Medinas",
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
                createdAt: DateFormatter.explorePreviewFormatter.date(from: "2025-05-12") ?? Date(),
                ownerId: "owner-5",
                entryCount: 0,
                dayCount: 0,
                destinations: [
                    TripDestination(id: "6", country: "Morocco", city: "Marrakech", orderIndex: 0),
                    TripDestination(id: "7", country: "Morocco", city: "Fes", orderIndex: 1)
                ]
            ),
            Trip(
                id: "6",
                title: "Croatian Coastline",
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
                createdAt: DateFormatter.explorePreviewFormatter.date(from: "2025-08-25") ?? Date(),
                ownerId: "owner-6",
                entryCount: 0,
                dayCount: 0,
                destinations: [TripDestination(id: "8", country: "Croatia", city: "Dubrovnik", orderIndex: 0)]
            )
        ]
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Dark editorial header
                ZStack(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(Color.bpPrimaryDeep)
                        .frame(height: 200)

                    LinearGradient(
                        colors: [Color.bpPrimaryDeep.opacity(0.3), Color.bpPrimaryDeep],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 200)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("EDITOR'S PICKS")
                            .font(.bpLabel)
                            .foregroundColor(.bpAzure)
                            .tracking(2.0)

                        ItalicLastWord(
                            text: "Stories from around the world.",
                            font: .bpTitle,
                            baseColor: .white
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .frame(height: 200)
                .clipped()

                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.bpTextMuted)
                        .font(.system(size: 16))

                    Text("Search trips, destinations…")
                        .font(.bpCallout)
                        .foregroundColor(.bpStone)

                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.white)
                .overlay(
                    Rectangle()
                        .stroke(Color.bpBorder, lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Featured section
                BPSectionHeader(title: "Featured")
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(mockFeatured) { featured in
                            FeaturedCard(featured: featured)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 24)

                // Recent grid
                BPSectionHeader(title: "Recent Journeys")
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                let columns = [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ]

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(mockRecent) { trip in
                        ExploreGridCell(trip: trip)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(Color.bpBackground)
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.inline)
        .bpNavigationStyle()
    }
}

#Preview("Explore — Search Results") {
    NavigationStack {
        ExploreSearchPreview()
    }
}

private struct ExploreSearchPreview: View {
    private var mockResults: [Trip] {
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
                createdAt: DateFormatter.explorePreviewFormatter.date(from: "2025-06-15") ?? Date(),
                ownerId: "owner-1",
                entryCount: 0,
                dayCount: 0,
                destinations: [TripDestination(id: "1", country: "Turkey", city: "Istanbul", orderIndex: 0)]
            ),
            Trip(
                id: "3",
                title: "Amalfi Coast Road Trip",
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
                createdAt: DateFormatter.explorePreviewFormatter.date(from: "2025-09-10") ?? Date(),
                ownerId: "owner-3",
                entryCount: 0,
                dayCount: 0,
                destinations: [TripDestination(id: "4", country: "Italy", city: "Amalfi", orderIndex: 0)]
            )
        ]
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Search bar with query
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.bpTextMuted)
                        .font(.system(size: 16))

                    Text("istanbul")
                        .font(.bpCallout)
                        .foregroundColor(.bpInk)

                    Spacer()

                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.bpStone)
                        .font(.system(size: 16))
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.white)
                .overlay(
                    Rectangle()
                        .stroke(Color.bpBorder, lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Results
                BPSectionHeader(title: "2 results")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                ForEach(Array(mockResults.enumerated()), id: \.element.id) { index, trip in
                    SearchResultRow(trip: trip)

                    if index < mockResults.count - 1 {
                        BPDivider()
                    }
                }
            }
        }
        .background(Color.bpBackground)
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.inline)
        .bpNavigationStyle()
    }
}
