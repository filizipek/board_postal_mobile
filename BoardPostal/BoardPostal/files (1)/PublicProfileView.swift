import SwiftUI
import Combine


// MARK: - PublicProfileViewModel

@MainActor
final class PublicProfileViewModel: ObservableObject {
    let userId: String

    @Published var profile: PublicProfile? = nil
    @Published var trips: [PublicTripCard] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var error: String? = nil
    

    private var currentPage = 1
    private var totalCount = 0
    private let pageSize = 20

    private let api = APIClient.shared

    init(userId: String) {
        self.userId = userId
    }

    var hasMore: Bool {
        trips.count < totalCount
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            async let profileResult: PublicProfile = api.request(
                .userProfile(userId: userId)
            )
            async let tripsResult: Paginated<PublicTripCard> = api.request(
                .userTrips(userId: userId, page: 1, pageSize: pageSize)
            )
            let (p, t) = try await (profileResult, tripsResult)
            profile = p
            trips = t.items
            totalCount = t.total
            currentPage = 1
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func loadMore() async {
        guard !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        do {
            let next = currentPage + 1
            let result: Paginated<PublicTripCard> = try await api.request(
                .userTrips(userId: userId, page: next, pageSize: pageSize)
            )
            trips.append(contentsOf: result.items)
            currentPage = next
        } catch {
            // Preserve current list; user can scroll back up or pull-to-retry on view.
        }
        isLoadingMore = false
    }

    /// Optimistically adjust followerCount in response to a FollowButton toggle.
    /// The button itself owns isFollowing; this view-model only mirrors the count
    /// shown in the header stat row.
    func bumpFollowerCount(by delta: Int) {
        guard let p = profile else { return }
        profile = PublicProfile(
            id: p.id,
            fullName: p.fullName,
            bio: p.bio,
            avatarUrl: p.avatarUrl,
            avatarId: p.avatarId,
            followerCount: max(0, p.followerCount + delta),
            followingCount: p.followingCount,
            publicTripCount: p.publicTripCount,
            isFollowing: p.isFollowing
        )
    }
}

// MARK: - PublicProfileView

struct PublicProfileView: View {
    let userId: String

    @EnvironmentObject private var authStore: AuthStore
    @StateObject private var viewModel: PublicProfileViewModel

    init(userId: String) {
        self.userId = userId
        _viewModel = StateObject(wrappedValue: PublicProfileViewModel(userId: userId))
    }

    private var isOwnProfile: Bool {
        authStore.currentUser?.userId == userId
    }

    var body: some View {
        Group {
            if viewModel.profile == nil && viewModel.isLoading {
                BPLoadingView()
            } else if let message = viewModel.error,
                      viewModel.profile == nil {
                BPErrorView(message: message) {
                    Task { await viewModel.load() }
                }
            } else {
                content
            }
        }
        .background(Color.bpBackground)
        .navigationBarTitleDisplayMode(.inline)
        .bpNavigationStyle()
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let profile = viewModel.profile {
                    header(profile)
                    BPDivider()
                        .padding(.top, 20)
                }

                if !viewModel.trips.isEmpty {
                    LazyVStack(spacing: 16) {
                        ForEach(Array(viewModel.trips.enumerated()), id: \.element.id) { index, trip in
                            PublicTripCardView(trip: trip)
                                .onAppear {
                                    if index == viewModel.trips.count - 1,
                                       viewModel.hasMore,
                                       !viewModel.isLoadingMore {
                                        Task { await viewModel.loadMore() }
                                    }
                                }
                        }

                        if viewModel.isLoadingMore {
                            ProgressView()
                                .tint(.bpCobalt)
                                .padding(.vertical, 16)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                } else if viewModel.profile != nil && !viewModel.isLoading {
                    BPEmptyState(
                        icon: "suitcase",
                        title: "No public trips",
                        message: "No public trips yet."
                    )
                    .padding(.top, 20)
                }
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func header(_ profile: PublicProfile) -> some View {
        VStack(spacing: 14) {
            AsyncImage(url: profile.avatarUrl.flatMap(URL.init(string:))) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    Image(systemName: "person.fill")
                        .font(.system(size: 36, weight: .light))
                        .foregroundColor(.bpStone)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.bpLimestone)
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.bpBorder, lineWidth: 1))

            if let name = profile.fullName, !name.isEmpty {
                ItalicLastWord(
                    text: name,
                    font: .bpTitle,
                    baseColor: .bpInk
                )
                .multilineTextAlignment(.center)
            }

            if let bio = profile.bio, !bio.isEmpty {
                Text(bio)
                    .font(.bpBody)
                    .foregroundColor(.bpTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            HStack(spacing: 0) {
                statColumn(
                    count: profile.followerCount,
                    label: profile.followerCount == 1 ? "Follower" : "Followers"
                )
                statColumn(count: profile.followingCount, label: "Following")
                statColumn(
                    count: profile.publicTripCount,
                    label: profile.publicTripCount == 1 ? "Trip" : "Trips"
                )
            }
            .padding(.top, 4)

            if !isOwnProfile {
                FollowButton(
                    userId: userId,
                    initialIsFollowing: profile.isFollowing,
                    onChange: { newState in
                        viewModel.bumpFollowerCount(by: newState ? 1 : -1)
                    }
                )
                .frame(maxWidth: 240)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }

    private func statColumn(count: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(BPFont.inter(size: 20, weight: .semibold))
                .foregroundColor(.bpInk)
            Text(label.uppercased())
                .font(.bpCaption)
                .foregroundColor(.bpTextMuted)
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview("Public Profile") {
    let mockOwner = TripCardOwner(
        id: "owner-1",
        fullName: "Filiz İpek",
        avatarUrl: nil,
        avatarId: nil
    )

    let mockTrips: [PublicTripCard] = [
        PublicTripCard(
            id: "trip-1",
            title: "Bosphorus Mornings",
            coverPhotoUrl: nil,
            createdAt: Date(),
            destinations: [
                PublicTripDestination(id: "d1", country: "Türkiye", city: "İstanbul", orderIndex: 0)
            ],
            entryCount: 6,
            placeCount: 4,
            owner: mockOwner,
            isFollowingAuthor: false,
            isSaved: true
        ),
        PublicTripCard(
            id: "trip-2",
            title: "Aegean Slow Days",
            coverPhotoUrl: nil,
            createdAt: Date(),
            destinations: [
                PublicTripDestination(id: "d2", country: "Türkiye", city: "Bodrum", orderIndex: 0),
                PublicTripDestination(id: "d3", country: "Türkiye", city: "Çeşme", orderIndex: 1)
            ],
            entryCount: 3,
            placeCount: 5,
            owner: mockOwner,
            isFollowingAuthor: false,
            isSaved: false
        ),
        PublicTripCard(
            id: "trip-3",
            title: "Lisbon Notebook",
            coverPhotoUrl: nil,
            createdAt: Date(),
            destinations: [
                PublicTripDestination(id: "d4", country: "Portugal", city: nil, orderIndex: 0)
            ],
            entryCount: 12,
            placeCount: 9,
            owner: mockOwner,
            isFollowingAuthor: true,
            isSaved: false
        )
    ]

    let mockProfile = PublicProfile(
        id: "owner-1",
        fullName: "Filiz İpek",
        bio: "Editor at board_postal. Slow travel, long lunches, and the kind of detours that turn into chapters.",
        avatarUrl: nil,
        avatarId: nil,
        followerCount: 1280,
        followingCount: 184,
        publicTripCount: 7,
        isFollowing: true
    )

    let viewModel = PublicProfileViewModel(userId: "owner-1")
    viewModel.profile = mockProfile
    viewModel.trips = mockTrips

    return NavigationStack {
        PublicProfileView(userId: "owner-1")
            .onAppear {
                // Inject preview state by reaching the view's VM through reflection
                // isn't possible; instead the view spawns its own VM.
                // For canvas verification we rely on the network call failing
                // (preview has no backend) — header + empty list will show.
                // Swap with the mock objects above by running a custom preview
                // wrapper if needed.
            }
    }
    .environmentObject(AuthStore())
}

#Preview("Public Profile · mocked VM") {
    // Wraps PublicProfileView's body manually with a pre-populated VM so
    // canvas renders without a live backend.
    PublicProfilePreviewWrapper()
        .environmentObject(AuthStore())
}

private struct PublicProfilePreviewWrapper: View {
    @StateObject private var viewModel: PublicProfileViewModel = {
        let vm = PublicProfileViewModel(userId: "owner-1")
        let mockOwner = TripCardOwner(
            id: "owner-1",
            fullName: "Filiz İpek",
            avatarUrl: nil,
            avatarId: nil
        )
        vm.profile = PublicProfile(
            id: "owner-1",
            fullName: "Filiz İpek",
            bio: "Editor at board_postal. Slow travel, long lunches, and the kind of detours that turn into chapters.",
            avatarUrl: nil,
            avatarId: nil,
            followerCount: 1280,
            followingCount: 184,
            publicTripCount: 7,
            isFollowing: true
        )
        vm.trips = [
            PublicTripCard(
                id: "trip-1",
                title: "Bosphorus Mornings",
                coverPhotoUrl: nil,
                createdAt: Date(),
                destinations: [
                    PublicTripDestination(id: "d1", country: "Türkiye", city: "İstanbul", orderIndex: 0)
                ],
                entryCount: 6, placeCount: 4,
                owner: mockOwner,
                isFollowingAuthor: false, isSaved: true
            ),
            PublicTripCard(
                id: "trip-2",
                title: "Aegean Slow Days",
                coverPhotoUrl: nil,
                createdAt: Date(),
                destinations: [
                    PublicTripDestination(id: "d2", country: "Türkiye", city: "Bodrum", orderIndex: 0),
                    PublicTripDestination(id: "d3", country: "Türkiye", city: "Çeşme", orderIndex: 1)
                ],
                entryCount: 3, placeCount: 5,
                owner: mockOwner,
                isFollowingAuthor: false, isSaved: false
            ),
            PublicTripCard(
                id: "trip-3",
                title: "Lisbon Notebook",
                coverPhotoUrl: nil,
                createdAt: Date(),
                destinations: [
                    PublicTripDestination(id: "d4", country: "Portugal", city: nil, orderIndex: 0)
                ],
                entryCount: 12, placeCount: 9,
                owner: mockOwner,
                isFollowingAuthor: true, isSaved: false
            )
        ]
        return vm
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if let profile = viewModel.profile {
                        VStack(spacing: 14) {
                            Circle()
                                .fill(Color.bpLimestone)
                                .frame(width: 96, height: 96)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 36, weight: .light))
                                        .foregroundColor(.bpStone)
                                )

                            ItalicLastWord(
                                text: profile.fullName ?? "",
                                font: .bpTitle,
                                baseColor: .bpInk
                            )
                            .multilineTextAlignment(.center)

                            if let bio = profile.bio {
                                Text(bio)
                                    .font(.bpBody)
                                    .foregroundColor(.bpTextSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                            }

                            HStack(spacing: 0) {
                                statColumn(count: profile.followerCount, label: "FOLLOWERS")
                                statColumn(count: profile.followingCount, label: "FOLLOWING")
                                statColumn(count: profile.publicTripCount, label: "TRIPS")
                            }

                            FollowButton(
                                userId: "owner-1",
                                initialIsFollowing: profile.isFollowing
                            )
                            .frame(maxWidth: 240)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 24)

                        BPDivider().padding(.top, 20)
                    }

                    ForEach(viewModel.trips) { trip in
                        PublicTripCardView(trip: trip)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color.bpBackground)
            .bpNavigationStyle()
        }
    }

    private func statColumn(count: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(BPFont.inter(size: 20, weight: .semibold))
                .foregroundColor(.bpInk)
            Text(label)
                .font(.bpCaption)
                .foregroundColor(.bpTextMuted)
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

