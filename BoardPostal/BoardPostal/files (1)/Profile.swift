import SwiftUI
import Combine

// MARK: - ProfileViewModel

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var publishedTrips: [Trip] = []
    @Published var draftTrips: [Trip] = []

    // Saved tab — paginated PublicTripCard
    @Published var savedTrips: [PublicTripCard] = []
    @Published var savedTripsTotal: Int = 0
    @Published var savedTripsCurrentPage: Int = 1
    @Published var isLoadingMoreSavedTrips: Bool = false
    @Published var selectedSavedTrip: PublicTripCard? = nil

    // Following tab
    @Published var followingUsers: [FollowedUser] = []
    @Published var followingTotal: Int = 0
    @Published var followingCurrentPage: Int = 1
    @Published var isLoadingMoreFollowing: Bool = false

    // Current user's public profile (header + edit-sheet prefill source)
    @Published var myProfile: PublicProfile? = nil

    @Published var isLoading = false
    @Published var error: String? = nil
    @Published var selectedTab: ProfileTab = .trips

    enum ProfileTab: String, CaseIterable {
        case trips = "Trips"
        case saved = "Saved"
        case following = "Following"
    }

    private let api = APIClient.shared
    private let pageSize = 20

    var totalTripCount: Int { publishedTrips.count + draftTrips.count }

    var allTrips: [Trip] {
        (publishedTrips + draftTrips).sorted { $0.createdAt > $1.createdAt }
    }

    var countryCount: Int {
        let countries = allTrips.flatMap { trip in
            trip.destinations.map { $0.country }
            + [trip.country].compactMap { $0 }
        }
        return Set(countries).count
    }

    var hasMoreSavedTrips: Bool { savedTrips.count < savedTripsTotal }
    var hasMoreFollowing:  Bool { followingUsers.count < followingTotal }

    var displayName: String {
        if let name = myProfile?.fullName, !name.isEmpty {
            return name
        }
        let email = KeychainService.shared.email ?? ""
        let prefix = email.components(separatedBy: "@").first ?? "Traveller"
        return prefix.isEmpty ? "Traveller" : prefix.capitalized
    }

    func loadAll(currentUserId: String? = nil) async {
        isLoading = true
        error = nil
        do {
            async let my: [Trip] = api.request(.trips)
            async let saved: Paginated<PublicTripCard> = api.request(
                .savedTrips(page: 1, pageSize: pageSize)
            )
            async let followingPage: Paginated<FollowedUser> = api.request(
                .following(page: 1, pageSize: pageSize)
            )
            let (myResult, savedResult, followingResult) =
                try await (my, saved, followingPage)
            publishedTrips = myResult.filter { !$0.isDraft }
            draftTrips     = myResult.filter { $0.isDraft }
            savedTrips             = savedResult.items
            savedTripsTotal        = savedResult.total
            savedTripsCurrentPage  = 1
            followingUsers         = followingResult.items
            followingTotal         = followingResult.total
            followingCurrentPage   = 1
        } catch {
            self.error = error.localizedDescription
        }

        // myProfile loads independently — it's allowed to fail without
        // breaking the rest of the profile screen (best-effort prefill).
        if let id = currentUserId {
            do {
                let profile: PublicProfile = try await api.request(
                    .userProfile(userId: id)
                )
                myProfile = profile
            } catch {
                // silent — header falls back to email-prefix displayName.
            }
        }

        isLoading = false
    }

    func loadMoreSavedTrips() async {
        guard !isLoadingMoreSavedTrips, hasMoreSavedTrips else { return }
        isLoadingMoreSavedTrips = true
        do {
            let next = savedTripsCurrentPage + 1
            let result: Paginated<PublicTripCard> = try await api.request(
                .savedTrips(page: next, pageSize: pageSize)
            )
            savedTrips.append(contentsOf: result.items)
            savedTripsCurrentPage = next
        } catch {
            // preserve current list; user can pull-to-refresh
        }
        isLoadingMoreSavedTrips = false
    }

    func selectSavedTrip(_ trip: PublicTripCard) {
        selectedSavedTrip = trip
    }

    func applySavedState(_ isSaved: Bool, tripId: String) {
        guard !isSaved else { return }
        savedTrips.removeAll { $0.id == tripId }
        savedTripsTotal = max(0, savedTripsTotal - 1)
    }

    func loadMoreFollowing() async {
        guard !isLoadingMoreFollowing, hasMoreFollowing else { return }
        isLoadingMoreFollowing = true
        do {
            let next = followingCurrentPage + 1
            let result: Paginated<FollowedUser> = try await api.request(
                .following(page: next, pageSize: pageSize)
            )
            followingUsers.append(contentsOf: result.items)
            followingCurrentPage = next
        } catch {
            // preserve current list
        }
        isLoadingMoreFollowing = false
    }

    func applyProfileUpdate(_ profile: PublicProfile) {
        myProfile = profile
    }

    func deleteTrip(id: String) async {
        do {
            try await APIClient.shared.requestVoid(.trip(id: id), method: .delete)
            publishedTrips.removeAll { $0.id == id }
            draftTrips.removeAll { $0.id == id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func logout(authStore: AuthStore) async {
        await authStore.logout()
    }
}

// MARK: - ProfileView

struct ProfileView: View {
    @StateObject private var viewModel: ProfileViewModel
    @EnvironmentObject var authStore: AuthStore
    @State private var showSettings = false
    @State private var isEditSheetPresented = false
    @State private var showAvatarPicker = false

    init() {
        _viewModel = StateObject(wrappedValue: ProfileViewModel())
    }

    init(viewModel: ProfileViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    private var avatarInitials: String {
        String(viewModel.displayName.prefix(1)).uppercased()
    }

    /// 52pt circular hero avatar. Renders the catalog-matched avatar on
    /// its driven gradient when the user has picked one; otherwise the
    /// original cobalt monogram with the initial. Centered art, same
    /// footprint either way — drops cleanly into the hero VStack.
    ///
    /// Reads avatarId from authStore.currentUser (same source the picker
    /// uses for initialSelection). viewModel.myProfile?.avatarId would be
    /// the natural pair-source with displayName/stats, but it's currently
    /// nil even when authStore has the value — see report on PublicProfile
    /// decode for the underlying cause.
    @ViewBuilder
    private var heroAvatar: some View {
        if let avatar = AvatarCatalog.avatar(for: authStore.currentUser?.avatarId) {
            ZStack {
                Circle()
                    .fill(avatar.gradient)
                    .frame(width: 52, height: 52)
                Image(avatar.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
            }
        } else {
            ZStack {
                Circle()
                    .fill(Color.bpCobalt.opacity(0.9))
                    .frame(width: 52, height: 52)
                Text(avatarInitials)
                    .font(BPFont.playfair(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    profileHero
                    actionStrip
                    tabContent
                }
            }
            .background(Color.bpBackground)
            .navigationBarHidden(true)
            .refreshable {
                await viewModel.loadAll(
                    currentUserId: authStore.currentUser?.userId
                )
            }
            .task {
                await viewModel.loadAll(
                    currentUserId: authStore.currentUser?.userId
                )
            }
            .navigationDestination(
                isPresented: Binding(
                    get: { viewModel.selectedSavedTrip != nil },
                    set: { if !$0 { viewModel.selectedSavedTrip = nil } }
                )
            ) {
                if let trip = viewModel.selectedSavedTrip {
                    ExplorePublicTripView(tripId: trip.id, preview: nil)
                }
            }
            .sheet(isPresented: $isEditSheetPresented) {
                EditProfileSheet(
                    initialFullName: viewModel.displayName,
                    initialBio: viewModel.myProfile?.bio,
                    onSave: { updated in
                        viewModel.applyProfileUpdate(updated)
                        isEditSheetPresented = false
                    },
                    onCancel: {
                        isEditSheetPresented = false
                    }
                )
                .presentationDragIndicator(.hidden)
            }
            .sheet(isPresented: $showAvatarPicker) {
                AvatarPickerView(
                    initialSelection: authStore.currentUser?.avatarId,
                    onSave: { newAvatarId in
                        // PUT /api/users/me with only the avatarId field set;
                        // bio / fullName / profilePhotoUrl default to nil
                        // ("leave unchanged" per PATCH-over-PUT semantics in
                        // Models.swift's UpdateProfileRequest comment).
                        let body = UpdateProfileRequest(avatarId: newAvatarId)
                        let updated: PublicProfile = try await APIClient.shared.request(
                            .updateProfile,
                            method: .put,
                            body: body
                        )
                        // Backend response is the source of truth — use what
                        // it returned (handles any server-side normalisation).
                        authStore.updateAvatarId(updated.avatarId)
                        viewModel.applyProfileUpdate(updated)
                    },
                    onDismiss: {
                        showAvatarPicker = false
                    }
                )
                .presentationDragIndicator(.hidden)
            }
        }
    }

    // MARK: - Hero

    private var profileHero: some View {
        // Color.clear is the SOLE layout anchor — its frame is what the parent
        // (LazyVStack) sees. The gradient and content live in .background/.overlay;
        // backgrounds/overlays are layout-passive and cannot widen the hero past
        // the explicit frame. This is the same pattern used by TripsFeature.heroBlock.
        //
        // Hero background is a deterministic gradient derived from the current
        // user's ID. Phase A: no auto-pulled photo. Phase B (deferred) will
        // swap this for a curated-avatar-driven gradient.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .background(
                LinearGradient.bpCoverGradient(
                    for: authStore.currentUser?.userId ?? "profile"
                )
            )
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.80),
                        Color.black.opacity(0.0)
                    ],
                    startPoint: .bottom,
                    endPoint: .init(x: 0.5, y: 0.35)
                )
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 10) {
                    // Hero avatar — curated avatar artwork on its driven
                    // gradient when one is set; original monogram otherwise.
                    // Reads from viewModel.myProfile.avatarId (same source as
                    // displayName / stats) so it updates live after Save.
                    heroAvatar
                        .contentShape(Circle())
                        .onTapGesture { showAvatarPicker = true }

                    // Name
                    ItalicLastWord(
                        text: viewModel.displayName,
                        font: BPFont.playfair(size: 28, weight: .bold),
                        baseColor: .white
                    )

                    statsLine
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay(alignment: .topTrailing) {
                Button { isEditSheetPresented = true } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, 56)
                .padding(.trailing, 20)
            }
            .overlay(alignment: .topTrailing) {
                // B5 entry: sibling to the edit-profile pencil. Sits 8pt to
                // its left so both buttons cohabit the top-trailing region.
                Button { showAvatarPicker = true } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, 56)
                .padding(.trailing, 64)
            }
            .clipped()
    }

    @ViewBuilder
    private var statsLine: some View {
        let parts: [String] = [
            viewModel.allTrips.count > 0
                ? "\(viewModel.allTrips.count) trips" : nil,
            viewModel.countryCount > 0
                ? "\(viewModel.countryCount) countries" : nil,
            viewModel.savedTrips.count > 0
                ? "\(viewModel.savedTrips.count) saved" : nil
        ].compactMap { $0 }

        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(BPFont.inter(size: 12, weight: .regular))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    // MARK: - Action strip (tabs + ellipsis)

    private var actionStrip: some View {
        HStack(spacing: 0) {
            ForEach([ProfileViewModel.ProfileTab.trips, .saved, .following], id: \.self) { tab in
                VStack(spacing: 0) {
                    Spacer()
                    Text(tab.rawValue)
                        .font(viewModel.selectedTab == tab ? .bpBodyBold : .bpCallout)
                        .foregroundColor(viewModel.selectedTab == tab ? .bpInk : .bpTextMuted)
                    Spacer()
                    Rectangle()
                        .fill(viewModel.selectedTab == tab ? Color.bpCobalt : Color.clear)
                        .frame(height: 2)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.white)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.selectedTab = tab
                    }
                }
            }

            // Ellipsis menu — tucked away
            Button {
                showSettings = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16))
                    .foregroundColor(.bpTextMuted)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .confirmationDialog("Settings", isPresented: $showSettings, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    Task { await viewModel.logout(authStore: authStore) }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .background(Color.white)
        .overlay(
            Rectangle().stroke(Color.bpBorder, lineWidth: 1),
            alignment: .bottom
        )
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.selectedTab {
        case .trips:
            tripsTabContent
        case .saved:
            savedTabContent
        case .following:
            followingTabContent
        }
    }

    @ViewBuilder
    private var tripsTabContent: some View {
        if viewModel.isLoading && viewModel.allTrips.isEmpty {
            BPLoadingView()
                .frame(height: 300)
        } else if viewModel.allTrips.isEmpty {
            BPEmptyState(
                icon: "suitcase",
                title: "No trips yet",
                message: "Start documenting your travels."
            )
            .padding(.top, 40)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.publishedTrips) { trip in
                    TripCard(
                        trip: trip,
                        onEdit: {},
                        onDelete: {
                            Task { await viewModel.deleteTrip(id: trip.id) }
                        },
                        onToggleDraft: {}
                    )
                }

                if !viewModel.draftTrips.isEmpty {
                    BPSectionHeader(title: "Drafts")
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    ForEach(viewModel.draftTrips) { trip in
                        TripCard(
                            trip: trip,
                            onEdit: {},
                            onDelete: {
                                Task { await viewModel.deleteTrip(id: trip.id) }
                            },
                            onToggleDraft: {}
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var savedTabContent: some View {
        if viewModel.savedTrips.isEmpty && !viewModel.isLoading {
            BPEmptyState(
                icon: "bookmark",
                title: "Nothing saved yet",
                message: "Save trips from the explore feed."
            )
            .padding(.top, 40)
        } else {
            LazyVStack(spacing: 16) {
                ForEach(Array(viewModel.savedTrips.enumerated()), id: \.element.id) { index, trip in
                    PublicTripCardView(
                        trip: trip,
                        onSelect: { viewModel.selectSavedTrip(trip) },
                        onSavedChange: { isSaved in
                            viewModel.applySavedState(isSaved, tripId: trip.id)
                        }
                    )
                        .onAppear {
                            if index == viewModel.savedTrips.count - 1,
                               viewModel.hasMoreSavedTrips,
                               !viewModel.isLoadingMoreSavedTrips {
                                Task { await viewModel.loadMoreSavedTrips() }
                            }
                        }
                }

                if viewModel.isLoadingMoreSavedTrips {
                    ProgressView()
                        .tint(.bpCobalt)
                        .padding(.vertical, 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private var followingTabContent: some View {
        if viewModel.followingUsers.isEmpty && !viewModel.isLoading {
            BPEmptyState(
                icon: "person.2",
                title: "Not following anyone",
                message: "Find travelers to follow from the Explore tab."
            )
            .padding(.top, 40)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.followingUsers.enumerated()), id: \.element.id) { index, user in
                    FollowedUserRow(user: user)
                        .onAppear {
                            if index == viewModel.followingUsers.count - 1,
                               viewModel.hasMoreFollowing,
                               !viewModel.isLoadingMoreFollowing {
                                Task { await viewModel.loadMoreFollowing() }
                            }
                        }
                    BPDivider()
                }

                if viewModel.isLoadingMoreFollowing {
                    ProgressView()
                        .tint(.bpCobalt)
                        .padding(.vertical, 16)
                }
            }
            .background(Color.white)
        }
    }
}

// MARK: - FollowedUserRow

private struct FollowedUserRow: View {
    let user: FollowedUser

    private var avatarURL: URL? {
        guard let s = user.avatarUrl else { return nil }
        return URL(string: s)
    }

    private var tripsLabel: String {
        user.publicTripCount == 1 ? "1 trip" : "\(user.publicTripCount) trips"
    }

    var body: some View {
        NavigationLink {
            PublicProfileView(userId: user.id)
        } label: {
            HStack(spacing: 14) {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        Color.bpLimestone
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 16, weight: .light))
                                    .foregroundColor(.bpStone)
                            )
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(user.fullName ?? "—")
                        .font(.bpBody)
                        .foregroundColor(.bpInk)
                        .lineLimit(1)
                    Text(tripsLabel)
                        .font(.bpCaption)
                        .foregroundColor(.bpTextMuted)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.white)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - EditProfileSheet

private struct EditProfileSheet: View {
    let initialFullName: String
    let initialBio: String?
    var onSave: (PublicProfile) -> Void
    var onCancel: () -> Void

    @State private var fullName: String
    @State private var bio: String
    @State private var isSaving = false
    @State private var errorMessage: String? = nil

    init(
        initialFullName: String,
        initialBio: String?,
        onSave: @escaping (PublicProfile) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialFullName = initialFullName
        self.initialBio = initialBio
        self.onSave = onSave
        self.onCancel = onCancel
        _fullName = State(initialValue: initialFullName)
        _bio      = State(initialValue: initialBio ?? "")
    }

    private var trimmedFullName: String {
        fullName.trimmingCharacters(in: .whitespaces)
    }

    private var canSave: Bool {
        !trimmedFullName.isEmpty && !isSaving
    }

    /// PATCH-over-PUT helper for nullable string fields:
    ///   - unchanged → nil
    ///   - explicit clear (initial was non-empty, current is empty) → ""
    ///   - new / changed value → that value
    private func patch(initial: String?, current: String) -> String? {
        let initialNorm = initial ?? ""
        if current == initialNorm { return nil }
        return current
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    BPTextField(
                        label: "Full name",
                        placeholder: "Your name",
                        text: $fullName
                    )

                    BPTextField(
                        label: "Bio",
                        placeholder: "A short bio",
                        text: $bio
                    )

                    if let errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundColor(.bpError)
                            Text(errorMessage)
                                .font(.bpCallout)
                                .foregroundColor(.bpError)
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.bpError.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    BPButton(
                        "Save",
                        style: .primary,
                        isLoading: isSaving
                    ) {
                        Task { await save() }
                    }
                    .disabled(!canSave)

                    BPButton("Cancel", style: .ghost) {
                        onCancel()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            .background(Color.bpBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.white, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Edit profile")
                        .font(.bpBodyBold)
                        .foregroundColor(.bpInk)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        let body = UpdateProfileRequest(
            fullName: trimmedFullName != initialFullName ? trimmedFullName : nil,
            bio: patch(initial: initialBio, current: bio),
            profilePhotoUrl: nil
        )
        do {
            let updated: PublicProfile = try await APIClient.shared.request(
                .updateProfile,
                method: .put,
                body: body
            )
            onSave(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - Previews

private extension DateFormatter {
    static let profilePreviewFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

private func makePreviewAuthStore() -> AuthStore {
    let store = AuthStore()
    store.currentUser = AuthResponse(
        accessToken: "preview",
        refreshToken: "preview",
        expiresAt: nil,
        userId: "1",
        email: "ilhan@boardpostal.com"
    )
    return store
}

private func makePreviewTrip(
    id: String,
    title: String,
    coverPhotoUrl: String? = nil,
    isDraft: Bool = false,
    isPlanning: Bool = false,
    createdAt: String,
    country: String? = nil,
    city: String? = nil,
    destinations: [TripDestination] = [],
    entryCount: Int = 0,
    dayCount: Int = 0
) -> Trip {
    Trip(
        id: id,
        title: title,
        description: nil,
        coverPhotoUrl: coverPhotoUrl,
        plannedStartDate: nil,
        plannedEndDate: nil,
        actualStartDate: nil,
        actualEndDate: nil,
        visibility: "Public",
        country: country,
        city: city,
        isDraft: isDraft,
        isPlanning: isPlanning,
        createdAt: DateFormatter.profilePreviewFormatter.date(from: createdAt) ?? Date(),
        ownerId: "owner-preview",
        entryCount: entryCount,
        dayCount: dayCount,
        destinations: destinations
    )
}

private var previewPublishedTrips: [Trip] {
    [
        makePreviewTrip(
            id: "madrid",
            title: "Madrid Heat",
            coverPhotoUrl: "https://images.unsplash.com/photo-1539037116277-4db20889f2d4?w=900",
            createdAt: "2026-04-15",
            destinations: [TripDestination(id: "d1", country: "Spain", city: "Madrid", orderIndex: 0)],
            entryCount: 6,
            dayCount: 4
        ),
        makePreviewTrip(
            id: "seville",
            title: "Seville Nights",
            createdAt: "2026-03-02",
            destinations: [TripDestination(id: "d2", country: "Spain", city: "Seville", orderIndex: 0)],
            entryCount: 3,
            dayCount: 3
        ),
        makePreviewTrip(
            id: "poland",
            title: "Poland",
            createdAt: "2026-01-20",
            country: "Poland",
            city: "Krakow",
            entryCount: 2,
            dayCount: 5
        )
    ]
}

private var previewDraftTrips: [Trip] {
    [
        makePreviewTrip(
            id: "edinburgh",
            title: "Edinburgh Dream",
            isDraft: true,
            createdAt: "2026-05-01",
            destinations: [TripDestination(id: "d3", country: "Scotland", city: "Edinburgh", orderIndex: 0)]
        )
    ]
}

private var previewSavedTrips: [PublicTripCard] {
    let owner = TripCardOwner(
        id: "owner-preview",
        fullName: "Liv Marchand",
        avatarUrl: nil,
        avatarId: nil
    )
    return [
        PublicTripCard(
            id: "paris",
            title: "Paris in Spring",
            coverPhotoUrl: nil,
            createdAt: DateFormatter.profilePreviewFormatter.date(from: "2025-04-20") ?? Date(),
            destinations: [
                PublicTripDestination(id: "d4", country: "France", city: "Paris", orderIndex: 0)
            ],
            entryCount: 4,
            placeCount: 6,
            owner: owner,
            isFollowingAuthor: false,
            isSaved: true
        )
    ]
}

private var previewFollowingUsers: [FollowedUser] {
    [
        FollowedUser(id: "u1", fullName: "Liv Marchand", avatarUrl: nil, avatarId: nil, publicTripCount: 12),
        FollowedUser(id: "u2", fullName: "Hiro Tanaka",  avatarUrl: nil, avatarId: nil, publicTripCount: 4),
        FollowedUser(id: "u3", fullName: "Sofia Reyes",  avatarUrl: nil, avatarId: nil, publicTripCount: 1)
    ]
}

#Preview("Profile — with trips") {
    let viewModel = ProfileViewModel()
    viewModel.publishedTrips = previewPublishedTrips
    viewModel.draftTrips = previewDraftTrips
    viewModel.savedTrips = previewSavedTrips
    viewModel.savedTripsTotal = previewSavedTrips.count
    viewModel.followingUsers = previewFollowingUsers
    viewModel.followingTotal = previewFollowingUsers.count
    viewModel.selectedTab = .trips
    viewModel.isLoading = false

    return ProfileView(viewModel: viewModel)
        .environmentObject(makePreviewAuthStore())
}

#Preview("Profile — empty") {
    ProfileView(viewModel: ProfileViewModel())
        .environmentObject(makePreviewAuthStore())
}

#Preview("Edit profile — pre-filled") {
    EditProfileSheet(
        initialFullName: "Liv Marchand",
        initialBio: "Editor at board_postal. Slow travel, long lunches.",
        onSave: { _ in },
        onCancel: {}
    )
}

#Preview("Edit profile — empty bio") {
    EditProfileSheet(
        initialFullName: "New User",
        initialBio: nil,
        onSave: { _ in },
        onCancel: {}
    )
}
