import SwiftUI
import Combine
import PhotosUI
import MapKit

// MARK: - TripViewModel

@MainActor
final class TripViewModel: ObservableObject {
    @Published var trips: [Trip] = []
    @Published var isLoading = false
    @Published var error: String?

    private let api = APIClient.shared

    var publishedTrips: [Trip] {
        trips.filter { !$0.isDraft }
    }

    var draftTrips: [Trip] {
        trips.filter { $0.isDraft }
    }

    func loadTrips() async {
        isLoading = true
        error = nil
        do {
            let result: [Trip] = try await api.request(.trips)
            trips = result
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func deleteTrip(id: String) async {
        do {
            try await api.requestVoid(.trip(id: id), method: .delete)
            trips.removeAll { $0.id == id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func toggleDraft(trip: Trip) async {
        do {
            let body = UpdateTripRequest(
                title: nil,
                visibility: nil,
                isDraft: !trip.isDraft,
                isPlanning: nil,
                coverPhotoUrl: nil
            )
            let updated: Trip = try await api.request(
                .trip(id: trip.id),
                method: .put,
                body: body
            )
            updateTrip(updated)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateTrip(_ updated: Trip) {
        if let i = trips.firstIndex(where: { $0.id == updated.id }) {
            trips[i] = updated
        }
    }
}

enum TripCountText {
    static func make(_ count: Int) -> String {
        "\(count) \(count == 1 ? "trip" : "trips")"
    }
}

#if DEBUG
enum TripsVisualVerificationScenario: String {
    case zero
    case one
    case two
    case several
    case privateDraft
    case publishedPrivate
    case publishedPublic
    case blockedPending
    case blockedListed
    case accessibility

    static var current: Self? {
        let prefix = "--trips-visual-scenario="
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        return Self(rawValue: String(argument.dropFirst(prefix.count)))
    }

    var trips: [Trip] {
        switch self {
        case .zero: []
        case .one: Array(TripsVisualVerificationData.drafts.prefix(1))
        case .two: Array(TripsVisualVerificationData.drafts.prefix(2))
        case .several: TripsVisualVerificationData.drafts
        case .privateDraft, .publishedPrivate, .publishedPublic,
             .blockedPending, .blockedListed, .accessibility: []
        }
    }

    var settingsTrip: Trip? {
        switch self {
        case .privateDraft, .accessibility:
            TripsVisualVerificationData.settingsTrip(isDraft: true, visibility: "private")
        case .publishedPrivate:
            TripsVisualVerificationData.settingsTrip(isDraft: false, visibility: "private")
        case .publishedPublic, .blockedPending, .blockedListed:
            TripsVisualVerificationData.settingsTrip(isDraft: false, visibility: "public")
        default:
            nil
        }
    }

    var blockingError: String? {
        switch self {
        case .blockedPending:
            "Cannot make this trip private while its Explore submission is pending. Explore withdrawal or removal must be resolved first."
        case .blockedListed:
            "Cannot move this trip back to drafts while its Explore submission is approved/listed. Explore withdrawal or removal must be resolved first."
        default:
            nil
        }
    }
}

enum TripsVisualVerificationData {
    static let drafts: [Trip] = [
        makeDraft(id: "draft-izmir", title: "A Slow Weekend Along the İzmir Waterfront", city: "İzmir", country: "Turkey", days: 1),
        makeDraft(id: "draft-ordu", title: "Ordu Highlands and the Very Long Black Sea Coast Journey", city: "Ordu", country: "Turkey", days: 3),
        makeDraft(id: "draft-copenhagen", title: "Copenhagen by Bicycle", city: "Copenhagen", country: "Denmark", days: 5),
        makeDraft(id: "draft-san-francisco", title: "Neighborhood Notes from San Francisco", city: "San Francisco", country: "United States", days: 8)
    ]

    private static func makeDraft(id: String, title: String, city: String, country: String, days: Int) -> Trip {
        Trip(
            id: id,
            title: title,
            description: nil,
            coverPhotoUrl: nil,
            plannedStartDate: nil,
            plannedEndDate: nil,
            actualStartDate: nil,
            actualEndDate: nil,
            visibility: "Private",
            country: country,
            city: city,
            isDraft: true,
            isPlanning: false,
            createdAt: Date(timeIntervalSince1970: 1_750_000_000),
            ownerId: "visual-verification-owner",
            entryCount: 0,
            dayCount: days,
            destinations: [TripDestination(id: "\(id)-destination", country: country, city: city, orderIndex: 0)]
        )
    }

    static func settingsTrip(isDraft: Bool, visibility: String) -> Trip {
        Trip(
            id: "settings-trip",
            title: "A Week Along the Aegean Coast",
            description: "Deterministic lifecycle verification trip",
            coverPhotoUrl: nil,
            plannedStartDate: nil,
            plannedEndDate: nil,
            actualStartDate: nil,
            actualEndDate: nil,
            visibility: visibility,
            country: "Türkiye",
            city: "İzmir",
            isDraft: isDraft,
            isPlanning: false,
            createdAt: Date(timeIntervalSince1970: 1_750_000_000),
            ownerId: "visual-verification-owner",
            entryCount: 3,
            dayCount: 4,
            destinations: []
        )
    }
}

struct TripsVisualVerificationView: View {
    @StateObject private var viewModel: TripViewModel

    init(scenario: TripsVisualVerificationScenario) {
        self.scenario = scenario
        let viewModel = TripViewModel()
        viewModel.trips = scenario.trips
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        if let trip = scenario.settingsTrip {
            EditTripView(
                verificationTrip: trip,
                hasExploreSubmission: scenario.blockingError != nil,
                error: scenario.blockingError
            ) { _ in }
            .environment(
                \.dynamicTypeSize,
                scenario == .accessibility ? .accessibility3 : .large
            )
        } else {
            TripsListView(viewModel: viewModel, automaticallyLoadsTrips: false)
        }
    }

    private let scenario: TripsVisualVerificationScenario
}
#endif

// MARK: - TripsListView

struct TripsListView: View {
    @StateObject private var viewModel: TripViewModel
    private let automaticallyLoadsTrips: Bool
    @State private var showCreateTrip = false
    @State private var showDeleteAlert = false
    @State private var tripToDelete: Trip?
    @State private var tripToEdit: Trip? = nil
    @State private var showEditTrip = false
    @State private var toast: BPToast? = nil

    init() {
        _viewModel = StateObject(wrappedValue: TripViewModel())
        automaticallyLoadsTrips = true
    }

    init(viewModel: TripViewModel, automaticallyLoadsTrips: Bool) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.automaticallyLoadsTrips = automaticallyLoadsTrips
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.trips.isEmpty {
                BPLoadingView()
            } else if viewModel.publishedTrips.isEmpty && viewModel.draftTrips.isEmpty && !viewModel.isLoading {
                BPEmptyState(
                    icon: "suitcase",
                    title: "No trips yet",
                    message: "Start documenting your travels.",
                    actionTitle: "Create your first trip",
                    action: { showCreateTrip = true }
                )
            } else {
                tripsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bpBackground)
        .navigationTitle("board_postal")
        .navigationBarTitleDisplayMode(.inline)
        .bpNavigationStyle()
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    ItalicLastWord(
                        text: "board_postal",
                        font: BPFont.playfair(size: 18, weight: .bold),
                        baseColor: .bpInk
                    )
                    if !viewModel.trips.isEmpty {
                        Text(TripCountText.make(viewModel.trips.count))
                            .font(.bpCaption)
                            .foregroundColor(.bpTextMuted)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showCreateTrip = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(.bpCobalt)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showCreateTrip) {
            CreateTripView()
                .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showEditTrip) {
            if let trip = tripToEdit {
                EditTripView(trip: trip) { updated in
                    viewModel.updateTrip(updated)
                    showEditTrip = false
                    toast = BPToast(message: "Trip updated")
                }
                .presentationDragIndicator(.hidden)
            }
        }
        .onChange(of: showCreateTrip) { _, shown in
            if !shown {
                Task { await viewModel.loadTrips() }
            }
        }
        .alert("Delete trip?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let trip = tripToDelete {
                    Task { await viewModel.deleteTrip(id: trip.id) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .bpToast($toast)
        .onReceive(NotificationCenter.default.publisher(for: .bpTripUpdated)) { _ in
            Task { await viewModel.loadTrips() }
        }
        .task {
            if automaticallyLoadsTrips {
                await viewModel.loadTrips()
            }
        }
        .refreshable {
            await viewModel.loadTrips()
        }
    }

    private var tripsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Section A — Published trips (skip section entirely if empty)
                if !viewModel.publishedTrips.isEmpty {
                    BPSectionHeader(title: "My Trips")
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                    ForEach(Array(viewModel.publishedTrips.enumerated()), id: \.element.id) { index, trip in
                        TripCard(
                            trip: trip,
                            onEdit: {
                                tripToEdit = trip
                                showEditTrip = true
                            },
                            onDelete: {
                                tripToDelete = trip
                                showDeleteAlert = true
                            },
                            onToggleDraft: {
                                Task {
                                    await viewModel.toggleDraft(trip: trip)
                                    toast = BPToast(message: trip.isDraft ? "Trip published" : "Moved to drafts")
                                }
                            }
                        )

                        if index < viewModel.publishedTrips.count - 1 {
                            BPDivider()
                        }
                    }
                }

                // Section B — Drafts (skip section entirely if empty)
                if !viewModel.draftTrips.isEmpty {
                    BPSectionHeader(title: "Drafts")
                        .padding(.horizontal, 16)
                        .padding(.top, 24)
                        .padding(.bottom, 18)

                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.draftTrips) { trip in
                            TripCard(
                                trip: trip,
                                onEdit: {
                                    tripToEdit = trip
                                    showEditTrip = true
                                },
                                onDelete: {
                                    tripToDelete = trip
                                    showDeleteAlert = true
                                },
                                onToggleDraft: {
                                    Task {
                                        await viewModel.toggleDraft(trip: trip)
                                        toast = BPToast(message: trip.isDraft ? "Trip published" : "Moved to drafts")
                                    }
                                }
                            )
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }
}

// MARK: - TripCard

struct TripCard: View {
    let trip: Trip
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggleDraft: () -> Void

    var body: some View {
        NavigationLink(destination: TripDetailView(trip: trip)) {
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(Color.clear)
                    .overlay {
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
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    }

                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.85),
                            Color.black.opacity(0.08)
                        ],
                        startPoint: .bottom,
                        endPoint: .init(x: 0.5, y: 0.4)
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            if trip.isDraft {
                                BPBadge("Draft", color: .white.opacity(0.6))
                            }
                            if trip.isPlanning {
                                BPBadge("Planning", color: .bpAzure)
                            }
                        }
                        BPDestinationEyebrow(
                            destinations: trip.destinations,
                            country: trip.country,
                            city: trip.city
                        )
                        ItalicLastWord(
                            text: trip.title,
                            font: BPFont.playfair(size: 20, weight: .bold),
                            baseColor: .white
                        )
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                        metaLine
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .padding(.top, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: 240, alignment: .bottomLeading)
                .clipped()
        }
        .buttonStyle(.plain)
        .shadow(color: Color.bpInk.opacity(0.1), radius: 8, x: 0, y: 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button { onEdit() } label: {
                Label("Edit", systemImage: "slider.horizontal.3")
            }
            .tint(.bpCobalt)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { onToggleDraft() } label: {
                Label(
                    trip.isDraft ? "Publish" : "Draft",
                    systemImage: trip.isDraft ? "eye" : "eye.slash"
                )
            }
            .tint(.bpSaffron)
        }
    }

    @ViewBuilder
    private var metaLine: some View {
        let parts: [String] = [
            trip.entryCount > 0
                ? "\(trip.entryCount) \(trip.entryCount == 1 ? "entry" : "entries")"
                : nil,
            trip.dayCount > 0
                ? "\(trip.dayCount) \(trip.dayCount == 1 ? "day" : "days")"
                : nil,
            !trip.destinations.isEmpty
                ? "\(trip.destinations.count) \(trip.destinations.count == 1 ? "destination" : "destinations")"
                : nil
        ].compactMap { $0 }

        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(BPFont.inter(size: 11, weight: .regular))
                .foregroundColor(.white.opacity(0.82))
                .shadow(color: .black.opacity(0.45), radius: 1, x: 0, y: 1)
        }
    }
}

// MARK: - TripDetailViewModel

@MainActor
protocol SubmissionAPIProviding {
    func submitTrip(tripId: String, message: String?) async throws -> SubmitTripResponse
}

extension APIClient: SubmissionAPIProviding {}

@MainActor
final class TripDetailViewModel: ObservableObject {
    @Published var entries: [TripEntry] = []
    @Published var places: [TripPlace] = []
    @Published var days: [TripDay] = []
    @Published var mediaAssets: [TripMediaAsset] = []
    @Published var submission: TripSubmission? = nil
    @Published var isLoading = false
    @Published var isSubmitting = false
    @Published var error: String?

    @Published var trip: Trip
    private let api: APIClient
    private let submissionAPI: any SubmissionAPIProviding

    init(trip: Trip) {
        self.trip = trip
        api = .shared
        submissionAPI = APIClient.shared
    }

    init(trip: Trip, submissionAPI: any SubmissionAPIProviding) {
        self.trip = trip
        api = .shared
        self.submissionAPI = submissionAPI
    }

    func loadAll() async {
        isLoading = true
        error = nil

        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                guard let self else { return }
                do {
                    let result: [TripEntry] = try await
                        self.api.request(.entries(tripId: self.trip.id))
                    await MainActor.run {
                        self.entries = result
                    }
                } catch {}
            }

            group.addTask { [weak self] in
                guard let self else { return }
                do {
                    let result: [TripPlace] = try await
                        self.api.request(.tripPlaces(tripId: self.trip.id))
                    await MainActor.run {
                        self.places = result
                    }
                } catch {}
            }

            group.addTask { [weak self] in
                guard let self else { return }
                do {
                    let result: [TripDay] = try await
                        self.api.request(.days(tripId: self.trip.id))
                    await MainActor.run {
                        self.days = result
                    }
                } catch {
                    // Surfaced (was previously swallowed by `catch {}`).
                    // DecodingError prints with full key path + type mismatch.
                    print("[TripDetailViewModel] days decode failed:", error)
                }
            }

            group.addTask { [weak self] in
                guard let self else { return }
                let result: [TripMediaAsset] =
                    (try? await self.api.request(.tripMedia(tripId: self.trip.id))) ?? []
                await MainActor.run {
                    self.mediaAssets = result
                }
            }

            group.addTask { [weak self] in
                guard let self else { return }
                let result: TripSubmission? =
                    try? await self.api.request(.tripSubmission(tripId: self.trip.id))
                await MainActor.run {
                    self.submission = result
                }
            }
        }

        await MainActor.run {
            self.isLoading = false
        }
    }

    func removeEntry(id: String) {
        entries.removeAll { $0.id == id }
    }

    func replaceEntry(_ updated: TripEntry) {
        if let i = entries.firstIndex(where: { $0.id == updated.id }) {
            entries[i] = updated
        }
    }

    var submissionEligibilityError: String? {
        if trip.visibility.lowercased() != "public" {
            return "Trip must be public to submit."
        }
        if trip.isDraft {
            return "Trip must be published to submit."
        }
        if trip.entryCount < 3 {
            return "Trip must have at least 3 entries."
        }
        return nil
    }

    @discardableResult
    func submitForPublication(message: String?) async -> String? {
        guard !isSubmitting else { return "A submission is already in progress." }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let result = try await submissionAPI.submitTrip(
                tripId: trip.id,
                message: message
            )
            submission = TripSubmission(
                id: result.submissionId,
                tripId: trip.id,
                status: result.status,
                message: message,
                rejectionReason: nil,
                createdAt: Date()
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

// MARK: - TripDetailView

@MainActor
protocol ItineraryAPIProviding {
    func createDay(tripId: String, body: CreateDayRequest) async throws -> TripDay
    func updateDay(tripId: String, dayId: String, body: UpdateDayRequest) async throws
    func createDayItem(tripId: String, dayId: String, body: CreateDayItemRequest) async throws -> TripDayItem
}

extension APIClient: ItineraryAPIProviding {}

struct TripDetailView: View {
    @StateObject private var viewModel: TripDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    @State private var showAddEntry = false
    @State private var showAddPhoto = false
    @State private var showAddPlace = false
    @State private var showEditTrip = false
    @State private var showShareSheet = false
    @State private var showMakePublicAlert = false
    @State private var showSubmitSheet = false
    @State private var showCollaborators = false
    @State private var entryToEdit: TripEntry? = nil
    @State private var entryToDelete: TripEntry? = nil
    @State private var showDeleteEntryAlert = false
    @State private var entryDeleteError: String? = nil
    @State private var showEntryDeleteErrorAlert = false
    @State private var isExportingPDF = false
    @State private var pdfData: Data? = nil
    @State private var showPDFShare = false
    private let pdfGenerator = PDFGenerator()
    @State private var submitMessage = ""
    @State private var submitError: String? = nil
    @State private var toast: BPToast? = nil
    @State private var currentTrip: Trip

    private let tabs = ["Journal", "Places", "Itinerary", "Map", "Photos"]

    init(trip: Trip) {
        _viewModel = StateObject(wrappedValue: TripDetailViewModel(trip: trip))
        _currentTrip = State(initialValue: trip)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // BLOCK 1 — Hero
                heroBlock

                // BLOCK 2 — Tab bar
                tabBar

                // BLOCK 3 — Tab content
                tabContent
            }
        }
        .background(Color.bpBackground)
        .ignoresSafeArea(edges: .top)
        .navigationBarHidden(true)
        .overlay(alignment: .top) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button {
                    if currentTrip.visibility.lowercased() == "public" {
                        showShareSheet = true
                    } else if currentTrip.isDraft {
                        showEditTrip = true
                    } else {
                        showMakePublicAlert = true
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                Text(currentTrip.title)
                    .font(BPFont.inter(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 1)

                Spacer()

                trailingToolbarButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 56)
        }
        .sheet(isPresented: $showAddEntry) {
            TripEntryComposerView(tripId: viewModel.trip.id) {
                Task { await viewModel.loadAll() }
                NotificationCenter.default.post(
                    name: .bpTripUpdated,
                    object: currentTrip.id
                )
            }
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showAddPhoto) {
            TripPhotoPickerView(tripId: viewModel.trip.id) {
                Task { await viewModel.loadAll() }
            }
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showAddPlace) {
            AddPlaceView(tripId: viewModel.trip.id) {
                Task { await viewModel.loadAll() }
                showAddPlace = false
            }
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showEditTrip) {
            EditTripView(
                trip: currentTrip,
                hasExploreSubmission: viewModel.submission.map {
                    ["pending", "approved"].contains($0.status.lowercased())
                } ?? false
            ) { updated in
                currentTrip = updated
                viewModel.trip = updated
                toast = BPToast(message: "Trip updated")
                Task { await viewModel.loadAll() }
                NotificationCenter.default.post(
                    name: .bpTripUpdated,
                    object: currentTrip.id
                )
            }
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = publicURL {
                ShareSheet(items: [
                    url,
                    "Check out my trip: \(currentTrip.title)"
                ])
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
            }
        }
        .alert("Delete this entry?", isPresented: $showDeleteEntryAlert) {
            Button("Delete", role: .destructive) {
                if let entry = entryToDelete {
                    Task { await deleteEntry(entry) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .alert(
            "Couldn't delete entry",
            isPresented: $showEntryDeleteErrorAlert,
            presenting: entryDeleteError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .sheet(item: $entryToEdit) { entry in
            EntryEditorSheet(entry: entry) { updated in
                viewModel.replaceEntry(updated)
                entryToEdit = nil
            }
            .presentationDragIndicator(.hidden)
        }
        .alert("Make trip public?", isPresented: $showMakePublicAlert) {
            Button("Make public & share") {
                Task { await makePublicAndShare() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your trip will be visible to anyone on board_postal.")
        }
        .sheet(isPresented: $showSubmitSheet) {
            submitSheet
        }
        .sheet(isPresented: $showCollaborators) {
            if let userId = KeychainService.shared.userId {
                CollaboratorsView(
                    tripId: currentTrip.id,
                    ownerId: currentTrip.ownerId,
                    currentUserId: userId)
                .presentationDragIndicator(.hidden)
            }
        }
        .sheet(isPresented: $showPDFShare) {
            if let data = pdfData {
                let url = FileManager.default
                    .temporaryDirectory
                    .appendingPathComponent(
                        "\(currentTrip.title).pdf")
                let _ = try? data.write(to: url)
                AnyView(ShareSheet(items: [url]))
            } else {
                AnyView(EmptyView())
            }
        }
        .presentationDetents([.medium, .large])
        .bpToast($toast)
        .task {
            await viewModel.loadAll()
        }
    }

    // MARK: - Submit-to-Explore sheet

    private var submitSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your trip will be reviewed by the board_postal editorial team. Public trips only.")
                        .font(.bpCallout)
                        .foregroundColor(.bpTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)

                BPDivider()

                VStack(alignment: .leading, spacing: 10) {
                    submissionRequirement(
                        "Trip must be published",
                        met: !currentTrip.isDraft
                    )
                    submissionRequirement(
                        "Trip must be public",
                        met: currentTrip.visibility.lowercased() == "public"
                    )
                    submissionRequirement(
                        "At least three entries",
                        met: currentTrip.entryCount >= 3
                    )
                    submissionRequirement(
                        "At least one place",
                        met: !viewModel.places.isEmpty
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                // Optional message
                VStack(alignment: .leading, spacing: 8) {
                    Text("MESSAGE (OPTIONAL)")
                        .font(.bpLabel)
                        .foregroundColor(.bpTextMuted)
                        .tracking(1.0)
                    TextField(
                        "Tell us why this trip deserves to be featured...",
                        text: $submitMessage,
                        axis: .vertical
                    )
                    .font(.bpBody)
                    .foregroundColor(.bpInk)
                    .lineLimit(4...8)
                }
                .padding(20)

                BPDivider()

                if let error = submitError {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundColor(.bpError)
                        Text(error)
                            .font(.bpCallout)
                            .foregroundColor(.bpError)
                        Spacer()
                    }
                    .padding(14)
                    .background(Color.bpError.opacity(0.06))
                }

                BPButton(
                    "Submit for review",
                    style: .primary,
                    isLoading: viewModel.isSubmitting
                ) {
                    Task {
                        guard !viewModel.isSubmitting else { return }
                        submitError = nil
                        if let eligibilityError = viewModel.submissionEligibilityError {
                            submitError = eligibilityError
                            return
                        }
                        if viewModel.places.isEmpty {
                            submitError = "Trip must have at least 1 place."
                            return
                        }
                        let error = await viewModel.submitForPublication(
                            message: submitMessage.isEmpty ? nil : submitMessage
                        )
                        if let error {
                            submitError = error
                        } else {
                            toast = BPToast(message: "Submitted for review")
                            showSubmitSheet = false
                        }
                    }
                }
                .disabled(
                    viewModel.submissionEligibilityError != nil
                    || viewModel.places.isEmpty
                    || viewModel.isSubmitting
                )
                .padding(20)

                Spacer()
            }
            .background(Color.bpBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.white, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showSubmitSheet = false
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.bpTextSecondary)
                    .disabled(viewModel.isSubmitting)
                }
                ToolbarItem(placement: .principal) {
                    Text("Submit to Explore")
                        .font(.bpBodyBold)
                        .foregroundColor(.bpInk)
                }
            }
            .presentationDragIndicator(.hidden)
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(viewModel.isSubmitting)
    }

    private func submissionRequirement(_ title: String, met: Bool) -> some View {
        Label(title, systemImage: met ? "checkmark.circle.fill" : "circle")
            .font(.bpCallout)
            .foregroundColor(met ? .bpCobalt : .bpTextSecondary)
            .accessibilityLabel("\(title): \(met ? "met" : "not met")")
    }

    // MARK: - Share helpers

    private var publicURL: URL? {
        URL(string: "\(APIEndpoint.baseURL)/trips/\(currentTrip.id)/public")
    }

    private func deleteEntry(_ entry: TripEntry) async {
        do {
            try await APIClient.shared.deleteEntry(
                tripId: viewModel.trip.id,
                entryId: entry.id
            )
            viewModel.removeEntry(id: entry.id)
            entryToDelete = nil
        } catch {
            entryDeleteError = error.localizedDescription
            showEntryDeleteErrorAlert = true
        }
    }

    private func exportPDF() async {
        isExportingPDF = true
        pdfGenerator.generate(
            trip: currentTrip,
            days: viewModel.days,
            places: viewModel.places
        ) { data in
            DispatchQueue.main.async {
                self.isExportingPDF = false
                if let data {
                    self.pdfData = data
                    self.showPDFShare = true
                }
            }
        }
    }

    private func makePublicAndShare() async {
        do {
            let body = UpdateTripRequest(
                title: nil,
                visibility: "public",
                isDraft: nil,
                isPlanning: nil,
                coverPhotoUrl: nil
            )
            let updated = try await APIClient.shared.updateTrip(id: currentTrip.id, body: body)
            currentTrip = updated
            viewModel.trip = updated
            NotificationCenter.default.post(
                name: .bpTripUpdated,
                object: currentTrip.id
            )
            showShareSheet = true
        } catch {
            toast = BPToast(message: error.localizedDescription)
        }
    }

    // MARK: - Trailing toolbar button (changes per tab)

    @ViewBuilder
    private var trailingToolbarButton: some View {
        switch selectedTab {
        case 0:
            toolbarCircleButton(systemImage: "square.and.pencil") {
                showAddEntry = true
            }
        case 1:
            toolbarCircleButton(systemImage: "mappin.and.ellipse") {
                showAddPlace = true
            }
        case 2, 3:
            Menu {
                Button {
                    showEditTrip = true
                } label: {
                    Label("Trip settings", systemImage: "slider.horizontal.3")
                }

                Button {
                    showCollaborators = true
                } label: {
                    Label("Travelling with", systemImage: "person.2")
                }

                Button {
                    Task { await exportPDF() }
                } label: {
                    if isExportingPDF {
                        Label("Generating...",
                            systemImage: "hourglass")
                    } else {
                        Label("Export PDF",
                            systemImage: "doc.richtext")
                    }
                }
                .disabled(isExportingPDF)

                if KeychainService.shared.userId == currentTrip.ownerId {
                    Divider()
                    if let sub = viewModel.submission {
                        switch sub.status.lowercased() {
                        case "pending":
                            Label("Submission pending", systemImage: "clock")
                        case "approved":
                            Label("Published in Explore", systemImage: "checkmark.seal.fill")
                        default:
                            Button {
                                showSubmitSheet = true
                            } label: {
                                Label("Submit to Explore", systemImage: "paperplane")
                            }
                        }
                    } else {
                        Button {
                            showSubmitSheet = true
                        } label: {
                            Label("Submit to Explore", systemImage: "paperplane")
                        }
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.3))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        case 4:
            toolbarCircleButton(systemImage: "photo.badge.plus") {
                showAddPhoto = true
            }
        default:
            Color.clear.frame(width: 36, height: 36)
        }
    }

    private func toolbarCircleButton(
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Color.black.opacity(0.3))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Date helpers

    private static func parseDate(_ str: String) -> Date? {
        let f1 = DateFormatter()
        f1.dateFormat = "yyyy-MM-dd"
        if let d = f1.date(from: str) { return d }
        let f2 = ISO8601DateFormatter()
        return f2.date(from: str)
    }

    private var formattedPlannedStart: String? {
        guard let dateStr = currentTrip.plannedStartDate,
              let date = Self.parseDate(dateStr)
        else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }

    @ViewBuilder
    private var heroMetaLine: some View {
        let trip = currentTrip
        let parts: [String] = [
            trip.entryCount > 0
                ? "\(trip.entryCount) \(trip.entryCount == 1 ? "entry" : "entries")"
                : nil,
            trip.dayCount > 0
                ? "\(trip.dayCount) \(trip.dayCount == 1 ? "day" : "days")"
                : nil,
            !trip.destinations.isEmpty
                ? "\(trip.destinations.count) \(trip.destinations.count == 1 ? "destination" : "destinations")"
                : nil
        ].compactMap { $0 }

        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(BPFont.inter(size: 11, weight: .regular))
                .foregroundColor(.white.opacity(0.45))
        }
    }

    // MARK: - Hero

    private var heroBlock: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 420)
            .background(
                Group {
                    if let url = currentTrip.coverURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            default:
                                LinearGradient.bpCoverGradient(for: currentTrip.id)
                            }
                        }
                    } else {
                        LinearGradient.bpCoverGradient(for: currentTrip.id)
                    }
                }
                .clipped()
            )
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.85),
                        Color.black.opacity(0.0)
                    ],
                    startPoint: .bottom,
                    endPoint: .init(x: 0.5, y: 0.35)
                )
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    BPDestinationEyebrow(
                        destinations: currentTrip.destinations,
                        country: currentTrip.country,
                        city: currentTrip.city
                    )
                    ItalicLastWord(
                        text: currentTrip.title,
                        font: BPFont.playfair(size: 36, weight: .bold),
                        baseColor: .white
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    if let start = formattedPlannedStart {
                        Text(start)
                            .font(BPFont.inter(size: 11, weight: .regular))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    heroMetaLine
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = index
                        }
                    } label: {
                        VStack(spacing: 0) {
                            Spacer()
                            Text(tab)
                                .font(selectedTab == index ? .bpBodyBold : .bpCallout)
                                .foregroundColor(selectedTab == index ? .bpInk : .bpTextMuted)
                            Spacer()
                            Rectangle()
                                .fill(selectedTab == index ? Color.bpCobalt : Color.clear)
                                .frame(height: 2)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color.white)

            BPDivider()
        }
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case 0:
            JournalTabView(
                entries: viewModel.entries,
                isLoading: viewModel.isLoading,
                onWrite: { showAddEntry = true },
                onEdit: { entry in
                    entryToEdit = entry
                },
                onDelete: { entry in
                    entryToDelete = entry
                    showDeleteEntryAlert = true
                }
            )
        case 1:
            PlacesTabView(
                places: viewModel.places,
                isLoading: viewModel.isLoading,
                onAddPlace: { showAddPlace = true }
            )
        case 2:
            ItineraryTabView(
                tripId: viewModel.trip.id,
                days: viewModel.days,
                places: viewModel.places)
        case 3:
            MapTabView(places: viewModel.places)
                .frame(minHeight: UIScreen.main.bounds.height - 480)
        case 4:
            PhotosTabView(assets: viewModel.mediaAssets, isLoading: viewModel.isLoading)
        default:
            EmptyView()
        }
    }
}

// MARK: - JournalTabView

private struct JournalTabView: View {
    let entries: [TripEntry]
    let isLoading: Bool
    var onWrite: (() -> Void)? = nil
    var onEdit: ((TripEntry) -> Void)? = nil
    var onDelete: ((TripEntry) -> Void)? = nil

    var body: some View {
        if isLoading {
            BPLoadingView()
                .frame(height: 200)
        } else if entries.isEmpty {
            BPEmptyState(
                icon: "pencil.and.outline",
                title: "No entries yet",
                message: "Start writing about your journey.",
                actionTitle: onWrite != nil ? "Write first entry" : nil,
                action: onWrite
            )
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    NavigationLink {
                        EntryDetailView(entry: entry)
                    } label: {
                        EntryRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            onDelete?(entry)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            onEdit?(entry)
                        } label: {
                            Label("Edit", systemImage: "slider.horizontal.3")
                        }
                        .tint(.bpCobalt)
                    }

                    if index < entries.count - 1 {
                        BPDivider()
                    }
                }
            }
        }
    }
}

// MARK: - EntryRow

struct EntryRow: View {
    let entry: TripEntry

    private var formattedDate: String? {
        guard let dateStr = entry.entryDate else { return nil }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: dateStr) else { return dateStr }
        let display = DateFormatter()
        display.dateFormat = "d MMM yyyy"
        return display.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if let date = formattedDate {
                    Text(date.uppercased())
                        .font(.bpCaption)
                        .foregroundColor(.bpTextMuted)
                        .tracking(0.5)
                }
                Spacer()
                if entry.isDraft {
                    BPBadge("Draft", color: .bpTextMuted)
                }
            }

            if let title = entry.title {
                Text(title)
                    .font(.bpSubhead)
                    .foregroundColor(.bpInk)
            }

            Text(entry.content)
                .font(.bpCallout)
                .foregroundColor(.bpTextSecondary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            if let place = entry.placeName {
                HStack(spacing: 4) {
                    Image(systemName: "mappin")
                        .font(.system(size: 10))
                        .foregroundColor(.bpCobalt)
                    Text(place)
                        .font(.bpCaption)
                        .foregroundColor(.bpCobalt)
                }
            }

            HStack {
                Text("\(entry.content.split(whereSeparator: \.isWhitespace).count) words")
                    .font(.bpCaption)
                    .foregroundColor(.bpTextMuted)
                Spacer()
                Text(entry.visibility)
                    .font(.bpCaption)
                    .foregroundColor(.bpTextMuted)
            }
        }
        .padding(16)
        .background(Color.white)
    }
}

// MARK: - EntryEditorSheet

struct EntryEditorSheet: View {
    let entry: TripEntry
    let onSave: (TripEntry) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var editingTitle: String
    @State private var editingContent: String
    @State private var isSaving = false
    @State private var saveError: String? = nil

    init(entry: TripEntry, onSave: @escaping (TripEntry) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _editingTitle = State(initialValue: entry.title ?? "")
        _editingContent = State(initialValue: entry.content)
    }

    private var trimmedTitle: String {
        editingTitle.trimmingCharacters(in: .whitespaces)
    }

    private var hasChanges: Bool {
        editingTitle != (entry.title ?? "")
            || editingContent != entry.content
    }

    private var canSave: Bool {
        !trimmedTitle.isEmpty && hasChanges && !isSaving
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Title", text: $editingTitle, axis: .horizontal)
                    .font(BPFont.playfair(size: 22, weight: .bold))
                    .foregroundColor(.bpInk)
                    .lineLimit(1)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 12)

                BPDivider()

                TextEditor(text: $editingContent)
                    .font(BPFont.inter(size: 16, weight: .regular))
                    .foregroundColor(.bpInk)
                    .scrollContentBackground(.hidden)
                    .background(Color.white)
                    .frame(minHeight: 240)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                if let saveError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundColor(.bpError)
                        Text(saveError)
                            .font(.bpCallout)
                            .foregroundColor(.bpError)
                        Spacer()
                    }
                    .padding(14)
                    .background(Color.bpError.opacity(0.06))
                }

                Spacer(minLength: 0)
            }
            .background(Color.white)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.white, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.plain)
                        .foregroundColor(.bpTextSecondary)
                }
                ToolbarItem(placement: .principal) {
                    Text("Edit entry")
                        .font(.bpBodyBold)
                        .foregroundColor(.bpInk)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().tint(.bpCobalt)
                        } else {
                            Text("Save")
                                .font(.bpBodyBold)
                                .foregroundColor(canSave ? .bpCobalt : .bpStone)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        saveError = nil
        do {
            let updated = try await APIClient.shared.updateEntry(
                tripId: entry.tripId,
                entryId: entry.id,
                title: trimmedTitle,
                content: editingContent
            )
            onSave(updated)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - EntryDetailView

struct EntryDetailView: View {
    let entry: TripEntry
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                
                // Header block — dark navy
                VStack(alignment: .leading, spacing: 8) {
                    if let dateStr = entry.entryDate {
                        let formatted: String = {
                            let parser = DateFormatter()
                            parser.dateFormat = "yyyy-MM-dd"
                            let display = DateFormatter()
                            display.dateFormat = "d MMMM yyyy"
                            return parser.date(from: dateStr)
                                .map { display.string(from: $0) }
                                ?? dateStr
                        }()
                        Text(formatted.uppercased())
                            .font(.bpLabel)
                            .foregroundColor(.bpAzure)
                            .tracking(1.0)
                    }

                    if let title = entry.title {
                        Text(title)
                            .font(.bpTitle)
                            .foregroundColor(.white)
                    }

                    HStack(spacing: 12) {
                        Text("\(entry.content.split(whereSeparator: \.isWhitespace).count) words")
                            .font(.bpCaption)
                            .foregroundColor(.white.opacity(0.5))
                        if entry.isDraft {
                            BPBadge("Draft", color: .bpSaffron)
                        }
                    }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                        .background(Color.bpPrimaryDeep)
                    
                    // Body
                    Text(entry.content)
                        .font(.bpBody)
                        .foregroundColor(.bpInk)
                        .lineSpacing(8)
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Color.bpBackground)
            .navigationBarTitleDisplayMode(.inline)
            .bpNavigationStyle()
        }
    }
}

    // MARK: - PlacesTabView

    private struct PlacesTabView: View {
        let places: [TripPlace]
        let isLoading: Bool
        var onAddPlace: (() -> Void)? = nil
        
        var body: some View {
            if isLoading {
                BPLoadingView()
                    .frame(height: 200)
            } else if places.isEmpty {
                BPEmptyState(
                    icon: "mappin.and.ellipse",
                    title: "No places saved",
                    message: "Pin the spots that matter.",
                    actionTitle: onAddPlace != nil ? "Add a place" : nil,
                    action: onAddPlace
                )
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(places.enumerated()), id: \.element.id) { index, tripPlace in
                        PlaceRow(tripPlace: tripPlace)
                        
                        if index < places.count - 1 {
                            BPDivider()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - PlaceRow
    
    struct PlaceRow: View {
        let tripPlace: TripPlace
        
        private var displayName: String {
            tripPlace.placeName
        }

        private var displayCity: String {
            ""
        }

        private var displayCategory: String {
            tripPlace.category ?? ""
        }
        
        private var categoryIcon: String {
            switch displayCategory.lowercased() {
            case "restaurant", "cafe":
                return "fork.knife"
            case "hotel", "accommodation":
                return "bed.double"
            case "museum", "culture":
                return "building.columns"
            default:
                return "mappin"
            }
        }
        
        var body: some View {
            HStack(spacing: 12) {
                // Category icon square
                Image(systemName: categoryIcon)
                    .font(.system(size: 16))
                    .foregroundColor(.bpCobalt)
                    .frame(width: 40, height: 40)
                    .background(Color.bpLimestone)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.bpBodyBold)
                        .foregroundColor(.bpInk)
                    
                    if !displayCity.isEmpty {
                        Text(displayCity)
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
    
    // MARK: - ItineraryViewModel

    @MainActor
    final class ItineraryViewModel: ObservableObject {
        let tripId: String
        private let api: any ItineraryAPIProviding
        @Published var days: [TripDay]
        @Published var isLoading = false
        @Published var error: String? = nil
        @Published var isAddingDay = false
        @Published var isSavingItem = false
        @Published var isUpdatingDay = false

        init(tripId: String, days: [TripDay]) {
            self.tripId = tripId
            api = APIClient.shared
            self.days = days.sorted {
                $0.dayNumber < $1.dayNumber }
        }

        init(tripId: String, days: [TripDay], api: any ItineraryAPIProviding) {
            self.tripId = tripId
            self.api = api
            self.days = days.sorted {
                $0.dayNumber < $1.dayNumber }
        }

        var sortedDays: [TripDay] {
            days.sorted { $0.dayNumber < $1.dayNumber }
        }

        @discardableResult
        func addDay() async -> Bool {
            guard !isAddingDay else { return false }
            isAddingDay = true
            defer { isAddingDay = false }
            let nextNumber = (days.map {
                $0.dayNumber }.max() ?? 0) + 1
            do {
                let body = CreateDayRequest(
                    dayNumber: nextNumber,
                    title: "Day \(nextNumber)",
                    date: nil,
                    orderIndex: nextNumber - 1)
                let newDay = try await api.createDay(tripId: tripId, body: body)
                days.append(newDay)
                return true
            } catch {
                self.error = error.localizedDescription
                return false
            }
        }

        func updateDay(_ day: TripDay,
                       title: String,
                       date: String?) async {
            isUpdatingDay = true
            defer { isUpdatingDay = false }
            do {
                let body = UpdateDayRequest(
                    title: title.isEmpty ? nil : title,
                    date: date,
                    orderIndex: nil)
                try await api.updateDay(tripId: tripId, dayId: day.id, body: body)
                if let i = days.firstIndex(
                    where: { $0.id == day.id }) {
                    let currentDay = days[i]
                    days[i] = TripDay(
                        id: currentDay.id,
                        tripId: currentDay.tripId,
                        dayNumber: currentDay.dayNumber,
                        title: body.title ?? currentDay.title,
                        date: body.date ?? currentDay.date,
                        orderIndex: currentDay.orderIndex,
                        items: currentDay.items
                    )
                }
            } catch {
                self.error = error.localizedDescription
            }
        }

        func deleteDay(id: String) async {
            do {
                try await APIClient.shared.requestVoid(
                    .day(tripId: tripId, dayId: id),
                    method: .delete)
                days.removeAll { $0.id == id }
            } catch {
                self.error = error.localizedDescription
            }
        }

        @discardableResult
        func addItem(to day: TripDay,
                     type: String,
                     title: String,
                     notes: String?,
                     time: String?) async -> String? {
            guard !isSavingItem else {
                return "An itinerary item is already being saved."
            }
            guard let currentDay = days.first(where: { $0.id == day.id }) else {
                let message = "This itinerary day is no longer available."
                error = message
                return message
            }
            isSavingItem = true
            defer { isSavingItem = false }
            do {
                let nextOrder = (currentDay.items.map {
                    $0.orderIndex }.max() ?? -1) + 1
                let body = CreateDayItemRequest(
                    type: type,
                    title: title,
                    notes: notes,
                    time: time,
                    orderIndex: nextOrder,
                    placeId: nil)
                let newItem = try await api.createDayItem(
                    tripId: tripId,
                    dayId: day.id,
                    body: body
                )
                if let i = days.firstIndex(
                    where: { $0.id == day.id }) {
                    let updatedDay = days[i]
                    var items = updatedDay.items
                    items.append(newItem)
                    days[i] = TripDay(
                        id: updatedDay.id,
                        tripId: updatedDay.tripId,
                        dayNumber: updatedDay.dayNumber,
                        title: updatedDay.title,
                        date: updatedDay.date,
                        orderIndex: updatedDay.orderIndex,
                        items: items)
                }
                return nil
            } catch {
                let message = error.localizedDescription
                self.error = message
                return message
            }
        }

        func replaceDayItem(_ updated: TripDayItem) {
            // Locate the parent day by searching items arrays for a matching
            // item id. tripDayId is no longer on the wire (it's nullable now),
            // so we can't rely on it for parent lookup.
            guard let di = days.firstIndex(where: { day in
                day.items.contains(where: { $0.id == updated.id })
            }) else { return }
            let updatedDay = days[di]
            var items = updatedDay.items
            guard let ii = items.firstIndex(
                where: { $0.id == updated.id }) else { return }
            items[ii] = updated
            days[di] = TripDay(
                id: updatedDay.id,
                tripId: updatedDay.tripId,
                dayNumber: updatedDay.dayNumber,
                title: updatedDay.title,
                date: updatedDay.date,
                orderIndex: updatedDay.orderIndex,
                items: items)
        }

        @discardableResult
        func deleteItem(dayId: String,
                        itemId: String) async -> String? {
            do {
                try await APIClient.shared.requestVoid(
                    .dayItem(tripId: tripId,
                             dayId: dayId,
                             itemId: itemId),
                    method: .delete)
                if let di = days.firstIndex(
                    where: { $0.id == dayId }) {
                    let updatedDay = days[di]
                    var items = updatedDay.items
                    items.removeAll { $0.id == itemId }
                    days[di] = TripDay(
                        id: updatedDay.id,
                        tripId: updatedDay.tripId,
                        dayNumber: updatedDay.dayNumber,
                        title: updatedDay.title,
                        date: updatedDay.date,
                        orderIndex: updatedDay.orderIndex,
                        items: items)
                }
                return nil
            } catch {
                let message = error.localizedDescription
                self.error = message
                return message
            }
        }
    }

    // MARK: - ItineraryTabView

    struct ItineraryTabView: View {
        let tripId: String
        let places: [TripPlace]
        @StateObject var viewModel: ItineraryViewModel
        @State private var showAddItem = false
        @State private var selectedDay: TripDay? = nil
        @State private var expandedDayId: String? = nil
        @State private var toast: BPToast? = nil
        @State private var itemToEdit: ItemEditingContext? = nil
        @State private var placeToView: PlaceDetailContext? = nil

        /// Carries the dayId alongside the item so .sheet(item:) doesn't have
        /// to derive it from a model field that's no longer on the wire.
        private struct ItemEditingContext: Identifiable {
            let dayId: String
            let item: TripDayItem
            var id: String { item.id }
        }

        private struct PlaceDetailContext: Identifiable {
            let dayId: String
            let item: TripDayItem
            let place: TripPlace
            var id: String { item.id }
        }

        init(tripId: String, days: [TripDay], places: [TripPlace] = []) {
            self.tripId = tripId
            self.places = places
            _viewModel = StateObject(wrappedValue:
                ItineraryViewModel(tripId: tripId,
                                   days: days))
        }

        var body: some View {
            VStack(spacing: 0) {
                if viewModel.isLoading {
                    BPLoadingView().frame(height: 200)
                } else if viewModel.sortedDays.isEmpty {
                    BPEmptyState(
                        icon: "calendar",
                        title: "No days planned",
                        message: "Add your first day to"
                            + " start planning.",
                        actionTitle: "Add day",
                        isLoading: viewModel.isAddingDay,
                        action: {
                            Task { await viewModel.addDay() }
                        }
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.sortedDays) {
                                day in
                                DaySection(
                                    day: day,
                                    isExpanded: expandedDayId
                                        == day.id,
                                    onToggle: {
                                        withAnimation(
                                            .spring(
                                            response: 0.3)){
                                            expandedDayId =
                                                expandedDayId
                                                == day.id
                                                ? nil : day.id
                                        }
                                    },
                                    onAddItem: {
                                        selectedDay = day
                                        showAddItem = true
                                    },
                                    onEditItem: { item in
                                        if item.itemType == .place,
                                           let placeId = item.placeId,
                                           let place = places.first(where: {
                                               $0.placeId == placeId
                                           }) {
                                            placeToView = PlaceDetailContext(
                                                dayId: day.id,
                                                item: item,
                                                place: place
                                            )
                                        } else {
                                            itemToEdit = ItemEditingContext(
                                                dayId: day.id,
                                                item: item
                                            )
                                        }
                                    },
                                    onDeleteItem: {
                                        itemId in
                                        Task {
                                            await viewModel
                                            .deleteItem(
                                                dayId: day.id,
                                                itemId: itemId)
                                        }
                                    },
                                    onDeleteDay: {
                                        Task {
                                            await viewModel
                                                .deleteDay(
                                                id: day.id)
                                        }
                                    }
                                )
                                BPDivider()
                            }

                            Button {
                                Task { await viewModel.addDay() }
                            } label: {
                                HStack(spacing: 10) {
                                    if viewModel.isAddingDay {
                                        ProgressView()
                                            .tint(.bpCobalt)
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundColor(.bpCobalt)
                                            .font(.system(size: 18))
                                    }
                                    Text("Add day")
                                        .font(.bpBodyBold)
                                        .foregroundColor(.bpCobalt)
                                    Spacer()
                                }
                                .padding(20)
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isAddingDay)
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddItem) {
                if let day = selectedDay {
                    AddDayItemSheet(day: day) {
                        type, title, notes, time in
                        await viewModel.addItem(
                            to: day,
                            type: type,
                            title: title,
                            notes: notes,
                            time: time)
                    }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.hidden)
                }
            }
            .sheet(item: $itemToEdit) { context in
                DayItemEditorSheet(
                    tripId: tripId,
                    dayId: context.dayId,
                    item: context.item,
                    onSave: { updated in
                        viewModel.replaceDayItem(updated)
                    },
                    onDelete: {
                        await viewModel.deleteItem(
                            dayId: context.dayId,
                            itemId: context.item.id)
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
            }
            .sheet(item: $placeToView) { context in
                ItineraryPlaceDetailSheet(
                    place: context.place,
                    onEdit: {
                        placeToView = nil
                        Task { @MainActor in
                            await Task.yield()
                            itemToEdit = ItemEditingContext(
                                dayId: context.dayId,
                                item: context.item
                            )
                        }
                    }
                )
            }
            .onChange(of: viewModel.error) { _, error in
                if let error {
                    toast = BPToast(message: error)
                    viewModel.error = nil
                }
            }
            .bpToast($toast)
        }
    }

    struct PlaceNavigationURLs {
        static func appleMaps(for place: TripPlace) -> URL? {
            guard let latitude = place.latitude,
                  let longitude = place.longitude else { return nil }
            var components = URLComponents(string: "https://maps.apple.com/")
            components?.queryItems = [
                URLQueryItem(name: "daddr", value: "\(latitude),\(longitude)"),
                URLQueryItem(name: "q", value: place.placeName)
            ]
            return components?.url
        }

        static func googleMaps(for place: TripPlace) -> URL? {
            guard let latitude = place.latitude,
                  let longitude = place.longitude else { return nil }
            var components = URLComponents(string: "https://www.google.com/maps/dir/")
            components?.queryItems = [
                URLQueryItem(name: "api", value: "1"),
                URLQueryItem(name: "destination", value: "\(latitude),\(longitude)")
            ]
            return components?.url
        }
    }

    struct ItineraryPlaceDetailSheet: View {
        let place: TripPlace
        let onEdit: () -> Void
        @Environment(\.dismiss) private var dismiss
        @Environment(\.openURL) private var openURL
        @State private var showDirections = false
        @State private var position: MapCameraPosition

        init(place: TripPlace, onEdit: @escaping () -> Void) {
            self.place = place
            self.onEdit = onEdit
            if let latitude = place.latitude, let longitude = place.longitude {
                _position = State(initialValue: .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )))
            } else {
                _position = State(initialValue: .automatic)
            }
        }

        var body: some View {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(place.placeName)
                            .font(.bpHeadline)
                            .foregroundColor(.bpInk)
                        if let category = place.category, !category.isEmpty {
                            Text(category)
                                .font(.bpCallout)
                                .foregroundColor(.bpTextSecondary)
                        }
                    }

                    if let latitude = place.latitude, let longitude = place.longitude {
                        Map(position: $position) {
                            Marker(
                                place.placeName,
                                coordinate: CLLocationCoordinate2D(
                                    latitude: latitude,
                                    longitude: longitude
                                )
                            )
                        }
                        .frame(minHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        BPButton("Directions", style: .primary) {
                            showDirections = true
                        }
                    } else {
                        BPEmptyState(
                            icon: "map",
                            title: "Location unavailable",
                            message: "This place does not have stored coordinates."
                        )
                    }
                    Spacer()
                }
                .padding(20)
                .background(Color.bpBackground)
                .navigationTitle("Place")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Edit", action: onEdit)
                    }
                }
                .confirmationDialog("Open directions in", isPresented: $showDirections) {
                    if let url = PlaceNavigationURLs.appleMaps(for: place) {
                        Button("Apple Maps") { openURL(url) }
                    }
                    if let url = PlaceNavigationURLs.googleMaps(for: place) {
                        Button("Google Maps") { openURL(url) }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
    }

    // MARK: - DaySection

    struct DaySection: View {
        let day: TripDay
        let isExpanded: Bool
        let onToggle: () -> Void
        let onAddItem: () -> Void
        let onEditItem: (TripDayItem) -> Void
        let onDeleteItem: (String) -> Void
        let onDeleteDay: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.bpCobalt)
                            .frame(width: 36, height: 36)
                        Text("\(day.dayNumber)")
                            .font(.bpBodyBold)
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading,
                           spacing: 2) {
                        Text(day.title
                            ?? "Day \(day.dayNumber)")
                            .font(.bpBodyBold)
                            .foregroundColor(.bpInk)
                        if let date = day.formattedDate {
                            Text(date)
                                .font(.bpCaption)
                                .foregroundColor(
                                    .bpTextMuted)
                        }
                    }

                    Spacer()

                    if !day.items.isEmpty {
                        Text("\(day.items.count)")
                            .font(.bpCaption)
                            .foregroundColor(.bpTextMuted)
                    }

                    Image(systemName: isExpanded
                        ? "chevron.up"
                        : "chevron.down")
                        .font(.system(size: 13,
                            weight: .medium))
                        .foregroundColor(.bpStone)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.bpLimestone)
                .contentShape(Rectangle())
                .onTapGesture { onToggle() }
                .contextMenu {
                    Button(role: .destructive, action: onDeleteDay) {
                        Label("Delete Day", systemImage: "trash")
                    }
                }

                if isExpanded {
                    VStack(spacing: 0) {
                        ForEach(day.items.sorted {
                            $0.orderIndex
                            < $1.orderIndex }) { item in
                            DayItemRow(item: item)
                                .contentShape(Rectangle())
                                .onTapGesture { onEditItem(item) }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        onDeleteItem(item.id)
                                    } label: {
                                        Label("Delete Item", systemImage: "trash")
                                    }
                                }
                            BPDivider()
                        }

                        Button(action: onAddItem) {
                            HStack(spacing: 8) {
                                Image(systemName:
                                    "plus.circle")
                                    .font(.system(size: 15))
                                    .foregroundColor(
                                        .bpCobalt)
                                Text("Add item")
                                    .font(.bpCallout)
                                    .foregroundColor(
                                        .bpCobalt)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                        .background(Color.white)
                    }
                }
            }
        }
    }

    // MARK: - DayItemRow

    struct DayItemRow: View {
        let item: TripDayItem

        var body: some View {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconBackground)
                        .frame(width: 36, height: 36)
                    Image(systemName: item.itemType.icon)
                        .font(.system(size: 15))
                        .foregroundColor(iconColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if let time = item.time,
                           !time.isEmpty {
                            Text(time)
                                .font(.bpCaption)
                                .foregroundColor(.bpCobalt)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Color.bpCobalt.opacity(
                                        0.1))
                                .cornerRadius(4)
                        }
                        Text(item.title)
                            .font(.bpBodyBold)
                            .foregroundColor(.bpInk)
                    }
                    if let notes = item.notes,
                       !notes.isEmpty {
                        Text(notes)
                            .font(.bpCaption)
                            .foregroundColor(.bpTextMuted)
                            .lineLimit(2)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)
        }

        private var iconBackground: Color {
            switch item.itemType {
            case .place: return .bpCobalt.opacity(0.1)
            case .transport: return .bpAzure.opacity(0.1)
            case .accommodation: return .bpSaffron.opacity(0.1)
            case .note: return .bpLimestone
            }
        }

        private var iconColor: Color {
            switch item.itemType {
            case .place: return .bpCobalt
            case .transport: return .bpAzure
            case .accommodation: return .bpSaffron
            case .note: return .bpTextMuted
            }
        }
    }

    // MARK: - AddDayItemSheet

    struct AddDayItemSheet: View {
        let day: TripDay
        let onAdd: (String, String, String?, String?) async -> String?
        @Environment(\.dismiss) var dismiss

        @State private var selectedType = "place"
        @State private var title = ""
        @State private var notes = ""
        @State private var time = ""
        @State private var isSaving = false
        @State private var saveError: String? = nil

        let types = [
            ("place", "mappin", "Place"),
            ("transport", "airplane", "Transport"),
            ("accommodation", "bed.double", "Hotel"),
            ("note", "note.text", "Note")
        ]

        var body: some View {
            NavigationStack {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        ForEach(types, id: \.0) {
                            type, icon, label in
                            Button {
                                selectedType = type
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: icon)
                                        .font(.system(
                                            size: 18))
                                    Text(label)
                                        .font(.bpCaption)
                                }
                                .foregroundColor(
                                    selectedType == type
                                    ? .bpCobalt : .bpStone)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    selectedType == type
                                    ? Color.bpCobalt
                                        .opacity(0.08)
                                    : Color.clear)
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(
                                        cornerRadius: 10)
                                    .stroke(
                                        selectedType == type
                                        ? Color.bpCobalt
                                        : Color.bpBorder,
                                        lineWidth:
                                        selectedType == type
                                        ? 1.5 : 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)

                    BPDivider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("TITLE")
                            .font(.bpLabel)
                            .foregroundColor(.bpTextMuted)
                            .tracking(1.0)
                        TextField(titlePlaceholder,
                            text: $title)
                            .font(.bpSubhead)
                            .foregroundColor(.bpInk)
                    }
                    .padding(16)

                    BPDivider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("TIME (OPTIONAL)")
                            .font(.bpLabel)
                            .foregroundColor(.bpTextMuted)
                            .tracking(1.0)
                        TextField("e.g. 09:00",
                            text: $time)
                            .font(.bpBody)
                            .foregroundColor(.bpInk)
                            .keyboardType(.numbersAndPunctuation)
                    }
                    .padding(16)

                    BPDivider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOTES (OPTIONAL)")
                            .font(.bpLabel)
                            .foregroundColor(.bpTextMuted)
                            .tracking(1.0)
                        TextField("Any details...",
                            text: $notes,
                            axis: .vertical)
                            .font(.bpBody)
                            .foregroundColor(.bpInk)
                            .lineLimit(3...5)
                    }
                    .padding(16)

                    if let saveError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundColor(.bpError)
                            Text(saveError)
                                .font(.bpCallout)
                                .foregroundColor(.bpError)
                            Spacer()
                        }
                        .padding(14)
                        .background(Color.bpError.opacity(0.06))
                    }

                    Spacer()

                    BPButton(
                        "Add to Day \(day.dayNumber)",
                        style: .primary,
                        isLoading: isSaving
                    ) {
                        Task { await save() }
                    }
                    .disabled(title.trimmingCharacters(
                        in: .whitespaces).isEmpty || isSaving)
                    .padding(16)
                }
                .background(Color.bpBackground)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color.white,
                    for: .navigationBar)
                .toolbarBackground(.visible,
                    for: .navigationBar)
                .toolbar {
                    ToolbarItem(
                        placement: .navigationBarLeading) {
                        Button("Cancel") { dismiss() }
                            .buttonStyle(.plain)
                            .foregroundColor(.bpTextSecondary)
                            .disabled(isSaving)
                    }
                    ToolbarItem(placement: .principal) {
                        Text("Add to Day \(day.dayNumber)")
                            .font(.bpBodyBold)
                            .foregroundColor(.bpInk)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
        }

        private func save() async {
            guard !isSaving else { return }
            isSaving = true
            saveError = nil
            defer { isSaving = false }
            let error = await onAdd(
                selectedType,
                title,
                notes.isEmpty ? nil : notes,
                time.isEmpty ? nil : time
            )
            if let error {
                saveError = error
            } else {
                dismiss()
            }
        }

        private var titlePlaceholder: String {
            switch selectedType {
            case "place": return "e.g. Sagrada Família"
            case "transport": return "e.g. Train to Barcelona"
            case "accommodation": return "e.g. Hotel Arts"
            default: return "e.g. Pack sunscreen"
            }
        }
    }

    enum ItemEditorMutationState: Equatable {
        case idle
        case saving
        case deleting

        mutating func begin(_ operation: Self) -> Bool {
            guard self == .idle, operation != .idle else { return false }
            self = operation
            return true
        }

        mutating func finish() {
            self = .idle
        }
    }

    // MARK: - DayItemEditorSheet

    struct DayItemEditorSheet: View {
        let tripId: String
        let dayId: String
        let item: TripDayItem
        let onSave: (TripDayItem) -> Void
        let onDelete: () async -> String?
        @Environment(\.dismiss) private var dismiss

        @State private var title: String
        @State private var selectedType: String
        @State private var notes: String
        @State private var time: String
        @State private var mutationState = ItemEditorMutationState.idle
        @State private var saveError: String? = nil
        @State private var showDeleteConfirm = false

        private let types = [
            ("place", "mappin", "Place"),
            ("transport", "airplane", "Transport"),
            ("accommodation", "bed.double", "Hotel"),
            ("note", "note.text", "Note")
        ]

        init(
            tripId: String,
            dayId: String,
            item: TripDayItem,
            onSave: @escaping (TripDayItem) -> Void,
            onDelete: @escaping () async -> String?
        ) {
            self.tripId = tripId
            self.dayId = dayId
            self.item = item
            self.onSave = onSave
            self.onDelete = onDelete
            _title = State(initialValue: item.title)
            _selectedType = State(initialValue: item.type)
            _notes = State(initialValue: item.notes ?? "")
            _time = State(initialValue: item.time ?? "")
        }

        private var trimmedTitle: String {
            title.trimmingCharacters(in: .whitespaces)
        }

        private var hasChanges: Bool {
            title != item.title
                || selectedType != item.type
                || notes != (item.notes ?? "")
                || time != (item.time ?? "")
        }

        private var canSave: Bool {
            !trimmedTitle.isEmpty && hasChanges && mutationState == .idle
        }

        var body: some View {
            NavigationStack {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        ForEach(types, id: \.0) {
                            type, icon, label in
                            Button {
                                selectedType = type
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: icon)
                                        .font(.system(
                                            size: 18))
                                    Text(label)
                                        .font(.bpCaption)
                                }
                                .foregroundColor(
                                    selectedType == type
                                    ? .bpCobalt : .bpStone)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    selectedType == type
                                    ? Color.bpCobalt
                                        .opacity(0.08)
                                    : Color.clear)
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(
                                        cornerRadius: 10)
                                    .stroke(
                                        selectedType == type
                                        ? Color.bpCobalt
                                        : Color.bpBorder,
                                        lineWidth:
                                        selectedType == type
                                        ? 1.5 : 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)

                    BPDivider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("TITLE")
                            .font(.bpLabel)
                            .foregroundColor(.bpTextMuted)
                            .tracking(1.0)
                        TextField(titlePlaceholder, text: $title)
                            .font(.bpSubhead)
                            .foregroundColor(.bpInk)
                    }
                    .padding(16)

                    BPDivider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("TIME (OPTIONAL)")
                            .font(.bpLabel)
                            .foregroundColor(.bpTextMuted)
                            .tracking(1.0)
                        TextField("e.g. 09:00", text: $time)
                            .font(.bpBody)
                            .foregroundColor(.bpInk)
                            .keyboardType(.numbersAndPunctuation)
                    }
                    .padding(16)

                    BPDivider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOTES (OPTIONAL)")
                            .font(.bpLabel)
                            .foregroundColor(.bpTextMuted)
                            .tracking(1.0)
                        TextField(
                            "Any details...",
                            text: $notes,
                            axis: .vertical)
                            .font(.bpBody)
                            .foregroundColor(.bpInk)
                            .lineLimit(3...5)
                    }
                    .padding(16)

                    if let saveError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundColor(.bpError)
                            Text(saveError)
                                .font(.bpCallout)
                                .foregroundColor(.bpError)
                            Spacer()
                        }
                        .padding(14)
                        .background(Color.bpError.opacity(0.06))
                    }

                    Spacer(minLength: 0)

                    Button {
                        showDeleteConfirm = true
                    } label: {
                        HStack(spacing: 8) {
                            if mutationState == .deleting {
                                ProgressView()
                                    .tint(.bpError)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "trash")
                                    .font(.system(size: 15))
                            }
                            Text("Delete item")
                                .font(.bpBodyBold)
                            Spacer()
                        }
                        .foregroundColor(.bpError)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(Color.bpError.opacity(0.06))
                    }
                    .buttonStyle(.plain)
                    .disabled(mutationState != .idle)
                }
                .background(Color.bpBackground)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color.white, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { dismiss() }
                            .buttonStyle(.plain)
                            .foregroundColor(.bpTextSecondary)
                            .disabled(mutationState != .idle)
                    }
                    ToolbarItem(placement: .principal) {
                        Text("Edit item")
                            .font(.bpHeadline)
                            .foregroundColor(.bpInk)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            Task { await save() }
                        } label: {
                            if mutationState == .saving {
                                ProgressView().tint(.bpCobalt)
                            } else {
                                Text("Save")
                                    .font(.bpBodyBold)
                                    .foregroundColor(
                                        canSave ? .bpCobalt : .bpStone)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSave)
                    }
                }
                .alert(
                    "Delete this item?",
                    isPresented: $showDeleteConfirm
                ) {
                    Button("Delete", role: .destructive) {
                        Task { await delete() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This cannot be undone.")
                }
            }
            .interactiveDismissDisabled(mutationState != .idle)
        }

        private func save() async {
            guard mutationState.begin(.saving) else { return }
            saveError = nil
            defer { mutationState.finish() }
            do {
                let updated = try await APIClient.shared.updateDayItem(
                    tripId: tripId,
                    dayId: dayId,
                    item: item,
                    title: trimmedTitle,
                    type: selectedType,
                    notes: notes.isEmpty ? nil : notes,
                    time: time.isEmpty ? nil : time
                )
                onSave(updated)
                dismiss()
            } catch {
                saveError = error.localizedDescription
            }
        }

        private func delete() async {
            guard mutationState.begin(.deleting) else { return }
            saveError = nil
            defer { mutationState.finish() }
            if let error = await onDelete() {
                saveError = error
            } else {
                dismiss()
            }
        }

        private var titlePlaceholder: String {
            switch selectedType {
            case "place": return "e.g. Sagrada Família"
            case "transport": return "e.g. Train to Barcelona"
            case "accommodation": return "e.g. Hotel Arts"
            default: return "e.g. Pack sunscreen"
            }
        }
    }

    // MARK: - MapTabView
    
    private struct MapTabView: View {
        let places: [TripPlace]
        @State private var selectedPlace: TripPlace? = nil
        @State private var position: MapCameraPosition = .automatic

        private var annotations: [TripPlaceAnnotation] {
            places.compactMap { p in
                guard let lat = p.latitude,
                      let lng = p.longitude
                else { return nil }
                return TripPlaceAnnotation(
                    id: p.id,
                    name: p.placeName,
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                    place: p
                )
            }
        }

        var body: some View {
            if annotations.isEmpty {
                BPEmptyState(
                    icon: "map",
                    title: "No places on map",
                    message: "Add places to see them here."
                )
            } else {
                ZStack(alignment: .bottom) {
                    Map(position: $position) {
                        ForEach(annotations) { ann in
                            Annotation(
                                ann.name,
                                coordinate: ann.coordinate,
                                anchor: .bottom
                            ) {
                                VStack(spacing: 2) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.bpCobalt)
                                            .frame(width: 36, height: 36)
                                            .shadow(
                                                color: .bpCobalt.opacity(0.4),
                                                radius: 4, x: 0, y: 2
                                            )
                                        Image(systemName: "mappin")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                    .scaleEffect(
                                        selectedPlace?.id == ann.id ? 1.3 : 1.0
                                    )
                                    .animation(
                                        .spring(response: 0.3),
                                        value: selectedPlace?.id
                                    )
                                    .onTapGesture {
                                        withAnimation {
                                            selectedPlace =
                                                selectedPlace?.id == ann.id ? nil : ann.place
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .ignoresSafeArea(edges: .bottom)
                    .onAppear { fitMap() }

                    if let place = selectedPlace {
                        placeCard(place)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                            .transition(
                                .move(edge: .bottom).combined(with: .opacity)
                            )
                    }
                }
                .animation(.spring(response: 0.3), value: selectedPlace?.id)
            }
        }

        private func fitMap() {
            guard !annotations.isEmpty else { return }
            if annotations.count == 1 {
                position = .region(MKCoordinateRegion(
                    center: annotations[0].coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
                return
            }
            let lats = annotations.map { $0.coordinate.latitude }
            let lngs = annotations.map { $0.coordinate.longitude }
            let center = CLLocationCoordinate2D(
                latitude: (lats.min()! + lats.max()!) / 2,
                longitude: (lngs.min()! + lngs.max()!) / 2
            )
            let span = MKCoordinateSpan(
                latitudeDelta: max((lats.max()! - lats.min()!) * 1.5, 0.05),
                longitudeDelta: max((lngs.max()! - lngs.min()!) * 1.5, 0.05)
            )
            position = .region(MKCoordinateRegion(center: center, span: span))
        }

        private func placeCard(_ place: TripPlace) -> some View {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.bpLimestone)
                        .frame(width: 44, height: 44)
                    Image(systemName: "mappin.fill")
                        .foregroundColor(.bpCobalt)
                        .font(.system(size: 18))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(place.placeName)
                        .font(.bpBodyBold)
                        .foregroundColor(.bpInk)
                    if let notes = place.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.bpCaption)
                            .foregroundColor(.bpTextMuted)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Button {
                    withAnimation { selectedPlace = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.bpTextMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 2)
        }
    }

    // Place annotation model for Map
    struct TripPlaceAnnotation: Identifiable {
        let id: String
        let name: String
        let coordinate: CLLocationCoordinate2D
        let place: TripPlace
    }
    
    // MARK: - PhotosTabView
    
    private struct PhotosTabView: View {
        let assets: [TripMediaAsset]
        let isLoading: Bool
        
        var body: some View {
            if isLoading && assets.isEmpty {
                BPLoadingView()
            } else if assets.isEmpty {
                BPEmptyState(
                    icon: "photo.on.rectangle",
                    title: "No photos yet",
                    message: "Upload photos from your journey."
                )
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 2),
                            GridItem(.flexible(), spacing: 2),
                            GridItem(.flexible(), spacing: 2)
                        ],
                        spacing: 2
                    ) {
                        ForEach(assets) { asset in
                            AsyncImage(url: asset.url) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable()
                                        .scaledToFill()
                                        .frame(height: 120)
                                        .clipped()
                                default:
                                    Rectangle()
                                        .fill(Color.bpLimestone)
                                        .frame(height: 120)
                                }
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }
    
    // MARK: - TripEntryComposerView
    
    struct TripEntryComposerView: View {
        let tripId: String
        let onSave: () -> Void
        @Environment(\.dismiss) var dismiss
        @StateObject private var locationManager = LocationManager()
        @State private var title = ""
        @State private var content = ""
        @State private var entryDate = Date()
        @State private var isDraft = false
        @State private var isSaving = false
        @State private var saveError: String?
        @State private var showSuccessOverlay = false
        @State private var attachedPhoto: UIImage? = nil
        @State private var showCamera = false
        @State private var showPhotoLibrary = false
        @FocusState private var contentFocused: Bool
        
        var wordCount: Int {
            content.split(whereSeparator: \.isWhitespace).count
        }
        var canSave: Bool {
            !content.trimmingCharacters(in: .whitespaces).isEmpty
        }
        
        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 0) {
                        // Date row
                        HStack(spacing: 10) {
                            Image(systemName: "calendar")
                                .foregroundColor(.bpCobalt)
                                .font(.system(size: 14))
                            DatePicker("", selection: $entryDate, displayedComponents: .date)
                                .labelsHidden()
                                .tint(.bpCobalt)
                            Spacer()
                            Text(entryDate, style: .relative)
                            + Text(" ago")
                        }
                        .font(.bpCaption)
                        .foregroundColor(.bpTextMuted)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        
                        BPDivider()
                        
                        // Photo attach row
                        photoAttachRow
                        
                        BPDivider()
                        
                        if let label = locationManager.locationLabel {
                            locationPill(label: label)
                            BPDivider()
                        }
                        
                        // Title field
                        TextField("Title (optional)", text: $title)
                            .font(.bpSubhead)
                            .foregroundColor(.bpInk)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                        
                        BPDivider()
                        
                        // Content area
                        ZStack(alignment: .topLeading) {
                            if content.isEmpty {
                                Text("What happened?\nWhere did you go?")
                                    .font(.bpBody)
                                    .foregroundColor(.bpStone)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 16)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $content)
                                .font(.bpBody)
                                .foregroundColor(.bpInk)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 320)
                                .scrollDisabled(true)
                                .focused($contentFocused)
                                .scrollContentBackground(.hidden)
                                .background(Color.white)
                        }
                        
                        BPDivider()
                        
                        // Metadata bar
                        HStack {
                            Text("\(wordCount) words")
                                .font(.bpCaption)
                                .foregroundColor(.bpTextMuted)
                            Spacer()
                            HStack(spacing: 6) {
                                Text("DRAFT")
                                    .font(.bpLabel)
                                    .foregroundColor(isDraft ? .bpSaffron : .bpTextMuted)
                                    .tracking(0.8)
                                Toggle("", isOn: $isDraft)
                                    .labelsHidden()
                                    .tint(.bpSaffron)
                                    .scaleEffect(0.8)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        
                        BPDivider()
                        
                        if let error = saveError {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundColor(.bpError)
                                Text(error)
                                    .font(.bpCallout)
                                    .foregroundColor(.bpError)
                                Spacer()
                            }
                            .padding(14)
                            .background(Color.bpError.opacity(0.08))
                            .overlay(Rectangle().stroke(Color.bpError.opacity(0.3), lineWidth: 1))
                            .padding(.horizontal, 20)
                        }
                    }
                }
                .background(Color.white)
                .overlay {
                    if showSuccessOverlay {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                            .overlay {
                                VStack(spacing: 16) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 56))
                                        .foregroundColor(.white)
                                    Text("Entry saved")
                                        .font(.bpHeadline)
                                        .foregroundColor(.white)
                                }
                            }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: showSuccessOverlay)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color.white, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { dismiss() }
                            .buttonStyle(.plain)
                            .font(.bpCallout)
                            .foregroundColor(.bpTextSecondary)
                    }
                    ToolbarItem(placement: .principal) {
                        Text("New Entry")
                            .font(.bpBodyBold)
                            .foregroundColor(.bpInk)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if isSaving {
                            ProgressView()
                                .tint(.bpCobalt)
                        } else {
                            Button("Save") {
                                Task { await save() }
                            }
                            .buttonStyle(.plain)
                            .font(.bpBodyBold)
                            .foregroundColor(canSave ? .bpCobalt : .bpStone)
                            .disabled(!canSave)
                        }
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { contentFocused = false }
                            .font(.bpCallout)
                            .foregroundColor(.bpCobalt)
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        contentFocused = true
                    }
                    locationManager.requestOnce()
                }
                .sheet(isPresented: $showCamera) {
                    CameraCapture(image: $attachedPhoto)
                        .ignoresSafeArea()
                        .presentationDragIndicator(.hidden)
                }
                .sheet(isPresented: $showPhotoLibrary) {
                    PhotoLibraryPicker(images: Binding(
                        get: { attachedPhoto.map { [$0] } ?? [] },
                        set: { attachedPhoto = $0.first }
                    ))
                    .presentationDragIndicator(.hidden)
                }
            }
        }
        
        // MARK: - Photo attach row
        
        private var photoAttachRow: some View {
            HStack(spacing: 10) {
                Button { showCamera = true } label: {
                    Label("Camera", systemImage: "camera")
                        .font(.bpCallout)
                        .foregroundColor(.bpCobalt)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.bpLimestone)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                
                Button { showPhotoLibrary = true } label: {
                    Label("Library", systemImage: "photo.on.rectangle")
                        .font(.bpCallout)
                        .foregroundColor(.bpCobalt)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.bpLimestone)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                if let photo = attachedPhoto {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 52, height: 52)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        Button { attachedPhoto = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.white)
                                .shadow(radius: 2)
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -6)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        
        // MARK: - Location pill
        
        private func locationPill(label: String) -> some View {
            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.bpCobalt)
                Text(label)
                    .font(.bpCaption)
                    .foregroundColor(.bpTextSecondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.bpCobalt.opacity(0.05))
        }
        
        private func save() async {
            isSaving = true
            saveError = nil
            do {
                let entryFormatter = DateFormatter()
                entryFormatter.dateFormat = "yyyy-MM-dd"
                let body = CreateEntryRequest(
                    title: title.isEmpty ? nil : title,
                    content: content,
                    entryDate: entryFormatter.string(from: entryDate),
                    placeId: nil,
                    orderIndex: 0,
                    visibility: "private"
                )
                let _: TripEntry = try await APIClient.shared.request(
                    .entries(tripId: tripId),
                    method: .post,
                    body: body
                )
                if let photo = attachedPhoto,
                   let asset = try? await MediaUploader.shared.upload(photo) {
                    struct LinkRequest: Encodable {
                        let mediaAssetId: String
                        let isCover: Bool
                        let orderIndex: Int
                    }
                    try? await APIClient.shared.requestVoid(
                        .tripMedia(tripId: tripId),
                        method: .post,
                        body: LinkRequest(mediaAssetId: asset.id, isCover: false, orderIndex: 0)
                    )
                }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showSuccessOverlay = true
                try? await Task.sleep(nanoseconds: 800_000_000)
                onSave()
                dismiss()
            } catch {
                saveError = error.localizedDescription
            }
            isSaving = false
        }
        
    }

    // MARK: - TripPhotoPickerView
    
    struct TripPhotoPickerView: View {
        let tripId: String
        let onComplete: () -> Void
        @Environment(\.dismiss) var dismiss
        @State private var showPicker = false
        @State private var selectedImages: [UIImage] = []
        @State private var isUploading = false
        @State private var uploadError: String?
        @State private var uploadProgress = 0
        @State private var uploadTotal = 0
        
        var body: some View {
            NavigationStack {
                VStack(spacing: 0) {
                    if selectedImages.isEmpty {
                        BPEmptyState(
                            icon: "photo.on.rectangle.angled",
                            title: "Select photos",
                            message: "Choose photos from your library to add to this trip.",
                            actionTitle: "Open photo library",
                            action: { showPicker = true }
                        )
                        .padding(.top, 60)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 2),
                                GridItem(.flexible(), spacing: 2),
                                GridItem(.flexible(), spacing: 2)
                            ], spacing: 2) {
                                ForEach(Array(selectedImages.enumerated()), id: \.offset) { _, img in
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 120)
                                        .clipped()
                                }
                            }
                            .padding(.top, 2)
                        }
                        
                        BPDivider()
                        
                        VStack(spacing: 12) {
                            if isUploading {
                                HStack(spacing: 10) {
                                    ProgressView()
                                        .tint(.bpCobalt)
                                    Text("Uploading \(uploadProgress) of \(uploadTotal)...")
                                        .font(.bpCallout)
                                        .foregroundColor(.bpTextSecondary)
                                }
                            } else {
                                BPButton("Upload \(selectedImages.count) photo\(selectedImages.count == 1 ? "" : "s")") {
                                    Task { await uploadPhotos() }
                                }
                            }
                            if let error = uploadError {
                                Text(error)
                                    .font(.bpCaption)
                                    .foregroundColor(.bpError)
                            }
                        }
                        .padding(20)
                    }
                    
                    Spacer()
                }
                .background(Color.bpBackground)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color.white, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { dismiss() }
                            .buttonStyle(.plain)
                            .font(.bpCallout)
                            .foregroundColor(.bpTextSecondary)
                    }
                    ToolbarItem(placement: .principal) {
                        Text("Add Photos")
                            .font(.bpBodyBold)
                            .foregroundColor(.bpInk)
                    }
                    if !selectedImages.isEmpty && !isUploading {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Library") { showPicker = true }
                                .buttonStyle(.plain)
                                .font(.bpCallout)
                                .foregroundColor(.bpCobalt)
                        }
                    }
                }
                .sheet(isPresented: $showPicker) {
                    PhotoLibraryPicker(images: $selectedImages)
                }
                .onAppear { showPicker = true }
            }
        }
        
        private func uploadPhotos() async {
            isUploading = true
            uploadError = nil
            uploadProgress = 0
            uploadTotal = selectedImages.count

            for image in selectedImages {
                do {
                    let asset = try await MediaUploader.shared.upload(image)
                    struct LinkRequest: Encodable {
                        let mediaAssetId: String
                        let isCover: Bool
                        let orderIndex: Int
                    }
                    try await APIClient.shared.requestVoid(
                        .tripMedia(tripId: tripId),
                        method: .post,
                        body: LinkRequest(mediaAssetId: asset.id, isCover: false, orderIndex: 0)
                    )
                    uploadProgress += 1
                } catch {
                    uploadError = error.localizedDescription
                    isUploading = false
                    return
                }
            }

            isUploading = false
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onComplete()
            dismiss()
        }
    }
    
    // MARK: - ShareSheet (UIActivityViewController bridge)
    
    struct ShareSheet: UIViewControllerRepresentable {
        let items: [Any]
        
        func makeUIViewController(context: Context) -> UIActivityViewController {
            UIActivityViewController(
                activityItems: items,
                applicationActivities: nil
            )
        }
        
        func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
    }
    
    // MARK: - PhotoLibraryPicker (PHPicker bridge)
    
    struct PhotoLibraryPicker: UIViewControllerRepresentable {
        @Binding var images: [UIImage]
        @Environment(\.dismiss) var dismiss
        
        func makeUIViewController(context: Context) -> PHPickerViewController {
            var config = PHPickerConfiguration()
            config.selectionLimit = 10
            config.filter = .images
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = context.coordinator
            return picker
        }
        
        func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}
        
        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }
        
        class Coordinator: NSObject, PHPickerViewControllerDelegate {
            let parent: PhotoLibraryPicker
            init(_ parent: PhotoLibraryPicker) {
                self.parent = parent
            }
            func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
                parent.dismiss()
                for result in results {
                    result.itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                        if let img = obj as? UIImage {
                            DispatchQueue.main.async {
                                self.parent.images.append(img)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - AddPlaceViewModel
    
    @MainActor
    final class AddPlaceViewModel: ObservableObject {
        let tripId: String
        let onSave: () -> Void
        
        @Published var query = ""
        @Published var suggestions: [PlaceSuggestion] = []
        @Published var isSearching = false
        @Published var isSaving = false
        @Published var saveError: String? = nil
        @Published var selectedSuggestion: PlaceSuggestion? = nil
        @Published var notes = ""
        
        private var searchTask: Task<Void, Never>? = nil
        
        init(tripId: String, onSave: @escaping () -> Void) {
            self.tripId = tripId
            self.onSave = onSave
        }
        
        func search() {
            searchTask?.cancel()
            let q = query.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2 else {
                suggestions = []
                return
            }
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                isSearching = true
                defer { isSearching = false }
                do {
                    let url = APIEndpoint.nominatimSearch(query: q)
                    var req = URLRequest(url: url)
                    req.setValue("application/json", forHTTPHeaderField: "Accept")
                    if let token = KeychainService.shared.accessToken {
                        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    }
                    let (data, _) = try await URLSession.shared.data(for: req)
                    suggestions = (try? JSONDecoder.bpDecoder.decode(
                        [PlaceSuggestion].self,
                        from: data
                    )) ?? []
                } catch {
                    suggestions = []
                }
            }
        }
        
        func save(suggestion: PlaceSuggestion) async {
            isSaving = true
            saveError = nil
            do {
                // Parse city/country from address ("Name, City, …, Country")
                let parts = suggestion.address?
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    ?? []
                let city = parts.count > 1 ? parts[1] : nil
                let country = parts.last

                // Step 1 — Create the place in /api/places
                let createBody = CreatePlaceRequest(
                    name: suggestion.name,
                    category: suggestion.category,
                    latitude: suggestion.latitude,
                    longitude: suggestion.longitude,
                    city: city,
                    country: country,
                    description: notes.isEmpty ? nil : notes
                )
                let createdPlace: Place = try await APIClient.shared.request(
                    .places,
                    method: .post,
                    body: createBody
                )

                // Step 2 — Link place to trip
                let linkBody = AddPlaceToTripRequest(
                    placeId: createdPlace.id,
                    notes: notes.isEmpty ? nil : notes,
                    orderIndex: 0,
                    imageUrl: nil
                )
                let _: TripPlace = try await APIClient.shared.request(
                    .tripPlaces(tripId: tripId),
                    method: .post,
                    body: linkBody
                )

                onSave()
            } catch let apiError as APIError {
                switch apiError {
                case .serverError(let code) where code == 409:
                    saveError = "This place is already saved to this trip."
                case .serverError(let code) where code == 404:
                    saveError = "Trip not found. Please go back and try again."
                case .serverError(let code) where code == 403:
                    saveError = "You don't have permission to add places to this trip."
                case .serverError(let code):
                    saveError = "Server error \(code). Please try again."
                default:
                    saveError = apiError.localizedDescription
                }
            } catch {
                saveError = error.localizedDescription
            }
            isSaving = false
        }
    }

    // MARK: - AddPlaceView
    
    struct AddPlaceView: View {
        @StateObject var viewModel: AddPlaceViewModel
        @Environment(\.dismiss) var dismiss
        
        init(tripId: String, onSave: @escaping () -> Void) {
            _viewModel = StateObject(wrappedValue: AddPlaceViewModel(
                tripId: tripId,
                onSave: onSave
            ))
        }
        
        var body: some View {
            NavigationStack {
                VStack(spacing: 0) {
                    searchBar
                    
                    BPDivider()
                    
                    if let selected = viewModel.selectedSuggestion {
                        selectedPane(selected)
                    } else if viewModel.query.count >= 2
                                && !viewModel.isSearching
                                && viewModel.suggestions.isEmpty {
                        BPEmptyState(
                            icon: "magnifyingglass",
                            title: "No places found",
                            message: "Try a different name or city."
                        )
                        .padding(.top, 40)
                    } else if viewModel.suggestions.isEmpty {
                        BPEmptyState(
                            icon: "mappin.and.ellipse",
                            title: "Find a place",
                            message: "Search by name, type, or address."
                        )
                        .padding(.top, 40)
                    } else {
                        suggestionList
                    }
                    
                    Spacer()
                }
                .background(Color.bpBackground)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color.white, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { dismiss() }
                            .buttonStyle(.plain)
                            .font(.bpCallout)
                            .foregroundColor(.bpTextSecondary)
                    }
                    ToolbarItem(placement: .principal) {
                        Text("Add place")
                            .font(.bpBodyBold)
                            .foregroundColor(.bpInk)
                    }
                }
                .presentationDragIndicator(.hidden)
            }
        }
        
        // MARK: - Search bar
        
        private var searchBar: some View {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.bpTextMuted)
                    .font(.system(size: 16))
                
                TextField(
                    "Search restaurants, museums, hotels…",
                    text: $viewModel.query
                )
                .font(.bpBody)
                .foregroundColor(.bpInk)
                .autocorrectionDisabled()
                .onChange(of: viewModel.query) { _, _ in
                    viewModel.search()
                }
                
                if viewModel.isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.bpCobalt)
                } else if !viewModel.query.isEmpty {
                    Button {
                        viewModel.query = ""
                        viewModel.suggestions = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.bpStone)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)
        }
        
        // MARK: - Suggestion list
        
        private var suggestionList: some View {
            List(viewModel.suggestions) { suggestion in
                Button {
                    viewModel.selectedSuggestion = suggestion
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.bpLimestone)
                                .frame(width: 40, height: 40)
                            Image(systemName: categoryIcon(suggestion.category))
                                .font(.system(size: 16))
                                .foregroundColor(.bpCobalt)
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text(suggestion.name)
                                .font(.bpBodyBold)
                                .foregroundColor(.bpInk)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle)
                                    .font(.bpCaption)
                                    .foregroundColor(.bpTextMuted)
                            }
                        }
                        Spacer()
                        Image(systemName: "plus.circle")
                            .foregroundColor(.bpCobalt)
                            .font(.system(size: 18))
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.white)
                .listRowSeparatorTint(.bpBorder)
            }
            .listStyle(.plain)
            .background(Color.white)
        }
        
        // MARK: - Selected pane (confirm + notes)
        
        private func selectedPane(_ selected: PlaceSuggestion) -> some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Selected place header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selected.name)
                                .font(.bpSubhead)
                                .foregroundColor(.bpInk)
                            if !selected.subtitle.isEmpty {
                                Text(selected.subtitle)
                                    .font(.bpCaption)
                                    .foregroundColor(.bpTextMuted)
                            }
                            if let cat = selected.category {
                                BPBadge(cat.capitalized, color: .bpCobalt)
                            }
                        }
                        Spacer()
                        Button {
                            viewModel.selectedSuggestion = nil
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundColor(.bpTextMuted)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(20)
                    .background(Color.bpCobalt.opacity(0.04))
                    
                    BPDivider()
                    
                    // Notes field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NOTES (OPTIONAL)")
                            .font(.bpLabel)
                            .foregroundColor(.bpTextMuted)
                            .tracking(1.0)
                        
                        TextField(
                            "What made this place special?",
                            text: $viewModel.notes,
                            axis: .vertical
                        )
                        .font(.bpBody)
                        .foregroundColor(.bpInk)
                        .lineLimit(3...6)
                    }
                    .padding(20)
                    
                    BPDivider()
                    
                    if let err = viewModel.saveError {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundColor(.bpError)
                            Text(err)
                                .font(.bpCallout)
                                .foregroundColor(.bpError)
                            Spacer()
                        }
                        .padding(16)
                        .background(Color.bpError.opacity(0.06))
                    }
                    
                    BPButton(
                        "Add to trip",
                        style: .primary,
                        isLoading: viewModel.isSaving
                    ) {
                        Task {
                            await viewModel.save(suggestion: selected)
                            if viewModel.saveError == nil {
                                dismiss()
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        
        // MARK: - Category icon mapping
        
        private func categoryIcon(_ category: String?) -> String {
            switch category?.lowercased() {
            case "restaurant", "food", "cafe", "bar":
                return "fork.knife"
            case "hotel", "accommodation", "lodging":
                return "bed.double"
            case "museum", "gallery", "culture":
                return "building.columns"
            case "park", "nature", "outdoor":
                return "leaf"
            case "shop", "shopping", "store":
                return "bag"
            case "transport", "station", "airport":
                return "airplane"
            case "church", "mosque", "temple", "religious":
                return "building"
            default:
                return "mappin"
            }
        }
    }
    
    // MARK: - EditTripViewModel

    @MainActor
    protocol TripSettingsAPIProviding {
        func updateTrip(id: String, body: UpdateTripRequest) async throws -> Trip
    }

    extension APIClient: TripSettingsAPIProviding {}
    
    @MainActor
    final class EditTripViewModel: ObservableObject {
        let trip: Trip
        let onSave: (Trip) -> Void
        
        @Published var title: String
        @Published var visibility: String
        @Published var isDraft: Bool
        @Published var isPlanning: Bool
        @Published var coverPhotoUrl: String?
        @Published var isSaving = false
        @Published var saveError: String? = nil
        @Published var activeTransition: TripStateTransition? = nil

        enum TripStateTransition: Equatable {
            case publishing
            case movingToDraft
            case makingPublic
            case makingPrivate
        }

        private let api: any TripSettingsAPIProviding

        @Published var selectedPhoto: UnsplashPhoto? = nil
        @Published var showUnsplashPicker = false

        init(
            trip: Trip,
            api: (any TripSettingsAPIProviding)? = nil,
            onSave: @escaping (Trip) -> Void
        ) {
            self.trip = trip
            self.api = api ?? APIClient.shared
            self.onSave = onSave
            self.title = trip.title
            self.visibility = trip.visibility
            self.isDraft = trip.isDraft
            self.isPlanning = trip.isPlanning
            self.coverPhotoUrl = trip.coverPhotoUrl
        }
        
        func selectPhoto(_ photo: UnsplashPhoto) {
            selectedPhoto = photo
            coverPhotoUrl = photo.fullURL?.absoluteString
        }
        
        @discardableResult
        func save() async -> Bool {
            guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
            guard !isSaving, activeTransition == nil else { return false }
            isSaving = true
            defer { isSaving = false }
            saveError = nil
            do {
                let body = UpdateTripRequest(
                    title: title,
                    isPlanning: isPlanning,
                    coverPhotoUrl: coverPhotoUrl
                )
                let updated = try await api.updateTrip(id: trip.id, body: body)
                onSave(updated)
                return true
            } catch {
                saveError = error.localizedDescription
                return false
            }
        }

        func changeState(_ transition: TripStateTransition) async {
            guard activeTransition == nil, !isSaving else { return }
            activeTransition = transition
            saveError = nil
            defer { activeTransition = nil }

            let body: UpdateTripRequest
            switch transition {
            case .publishing:
                body = UpdateTripRequest(isDraft: false)
            case .movingToDraft:
                body = UpdateTripRequest(isDraft: true)
            case .makingPublic:
                body = UpdateTripRequest(visibility: "public")
            case .makingPrivate:
                body = UpdateTripRequest(visibility: "private")
            }

            do {
                let updated = try await api.updateTrip(id: trip.id, body: body)
                isDraft = updated.isDraft
                visibility = updated.visibility
                onSave(updated)
            } catch {
                saveError = error.localizedDescription
            }
        }
    }
    
    // MARK: - UnsplashPickerView
    
    struct UnsplashPickerView: View {
        let onSelect: (UnsplashPhoto) -> Void
        var initialQuery: String? = nil

        @State private var query: String = ""
        @State private var results: [UnsplashPhoto] = []
        @State private var isSearching: Bool = false
        @State private var searchTask: Task<Void, Never>? = nil
        @Environment(\.dismiss) private var dismiss

        private let columns = [
            GridItem(.flexible(), spacing: 2),
            GridItem(.flexible(), spacing: 2),
            GridItem(.flexible(), spacing: 2)
        ]

        var body: some View {
            NavigationStack {
                VStack(spacing: 0) {
                    searchBar

                    BPDivider()

                    if results.isEmpty && !isSearching {
                        BPEmptyState(
                            icon: "photo.on.rectangle",
                            title: "Search for photos",
                            message: "Type a destination or keyword."
                        )
                        .padding(.top, 40)
                    } else {
                        photoGrid
                    }

                    Spacer()
                }
                .background(Color.bpBackground)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color.white, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { dismiss() }
                            .buttonStyle(.plain)
                            .font(.bpCallout)
                            .foregroundColor(.bpTextSecondary)
                    }
                    ToolbarItem(placement: .principal) {
                        Text("Choose cover photo")
                            .font(.bpBodyBold)
                            .foregroundColor(.bpInk)
                    }
                }
                .presentationDragIndicator(.hidden)
            }
        }

        private var searchBar: some View {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.bpTextMuted)
                    .font(.system(size: 16))
                TextField("Search photos…", text: $query)
                    .font(.bpBody)
                    .foregroundColor(.bpInk)
                    .autocorrectionDisabled()
                    .onSubmit { scheduleSearch(query) }
                    .onChange(of: query) { _, newValue in
                        scheduleSearch(newValue)
                    }
                    .task {
                        guard query.isEmpty,
                              let seed = initialQuery?
                                .trimmingCharacters(in: .whitespaces),
                              !seed.isEmpty
                        else { return }
                        query = seed
                        scheduleSearch(seed)
                    }
                if isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.bpCobalt)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)
        }

        private var photoGrid: some View {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(results) { photo in
                        Button {
                            onSelect(photo)
                            dismiss()
                        } label: {
                            AsyncImage(url: photo.thumbURL) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable()
                                        .scaledToFill()
                                        .frame(height: 120)
                                        .clipped()
                                default:
                                    Rectangle()
                                        .fill(LinearGradient.bpCoverGradient(for: photo.id))
                                        .frame(height: 120)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)

                Text("Photos from Unsplash")
                    .font(.bpCaption)
                    .foregroundColor(.bpTextMuted)
                    .padding(16)
            }
        }

        // MARK: - Search

        private func scheduleSearch(_ value: String) {
            searchTask?.cancel()
            let q = value.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2 else {
                results = []
                return
            }
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                await performSearch(q)
            }
        }

        @MainActor
        private func performSearch(_ query: String) async {
            isSearching = true
            defer { isSearching = false }
            guard let token = KeychainService.shared.accessToken else { return }
            var req = URLRequest(url: APIEndpoint.unsplashSearch(query: query))
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            guard let (data, _) = try? await URLSession.shared.data(for: req) else { return }
            if let result = try? JSONDecoder.bpDecoder.decode(UnsplashSearchResult.self, from: data) {
                results = result.results
            } else if let photos = try? JSONDecoder.bpDecoder.decode([UnsplashPhoto].self, from: data) {
                results = photos
            }
        }
    }
    
    // MARK: - EditTripView
    
    struct EditTripView: View {
        @StateObject var viewModel: EditTripViewModel
        let hasExploreSubmission: Bool
        @Environment(\.dismiss) var dismiss
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @State private var confirmation: EditTripViewModel.TripStateTransition? = nil
        
        init(
            trip: Trip,
            hasExploreSubmission: Bool = false,
            onSave: @escaping (Trip) -> Void
        ) {
            self.hasExploreSubmission = hasExploreSubmission
            _viewModel = StateObject(wrappedValue: EditTripViewModel(
                trip: trip,
                onSave: onSave
            ))
        }

#if DEBUG
        init(
            verificationTrip trip: Trip,
            hasExploreSubmission: Bool,
            error: String?,
            onSave: @escaping (Trip) -> Void
        ) {
            self.hasExploreSubmission = hasExploreSubmission
            let viewModel = EditTripViewModel(trip: trip, onSave: onSave)
            viewModel.saveError = error
            _viewModel = StateObject(wrappedValue: viewModel)
        }
#endif
        
        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 0) {
                        coverPhotoBlock
                        formFields
                    }
                }
                .background(Color.bpBackground)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color.white, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { dismiss() }
                            .buttonStyle(.plain)
                            .font(.bpCallout)
                            .foregroundColor(.bpTextSecondary)
                    }
                    ToolbarItem(placement: .principal) {
                        Text("Edit trip")
                            .font(.bpBodyBold)
                            .foregroundColor(.bpInk)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if viewModel.isSaving {
                            ProgressView()
                                .tint(.bpCobalt)
                        } else {
                            Button("Save") {
                                Task {
                                    if await viewModel.save() {
                                        dismiss()
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.bpBodyBold)
                            .foregroundColor(.bpCobalt)
                            .disabled(viewModel.title.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                .sheet(isPresented: $viewModel.showUnsplashPicker) {
                    UnsplashPickerView(
                        onSelect: { photo in
                            viewModel.selectPhoto(photo)
                        },
                        initialQuery: viewModel.trip.destinations.first?.city
                            ?? viewModel.trip.city
                            ?? viewModel.trip.title
                    )
                        .presentationDragIndicator(.hidden)
                }
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled(
                    viewModel.isSaving || viewModel.activeTransition != nil
                )
                .confirmationDialog(
                    confirmationTitle,
                    isPresented: Binding(
                        get: { confirmation != nil },
                        set: { if !$0 { confirmation = nil } }
                    ),
                    presenting: confirmation
                ) { transition in
                    Button(transitionActionTitle(transition), role: .destructive) {
                        Task { await viewModel.changeState(transition) }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { _ in
                    Text("If this trip has a pending or approved Explore submission, the server will keep the current state until withdrawal or removal is resolved.")
                }
            }
        }
        
        // MARK: - Cover photo
        
        private var coverPhotoBlock: some View {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let urlStr = viewModel.coverPhotoUrl,
                       let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            default:
                                LinearGradient.bpCoverGradient(for: viewModel.trip.id)
                            }
                        }
                    } else {
                        LinearGradient.bpCoverGradient(for: viewModel.trip.id)
                    }
                }
                .frame(height: 220)
                .clipped()
                
                LinearGradient(
                    colors: [Color.black.opacity(0.5), Color.clear],
                    startPoint: .bottom,
                    endPoint: .center
                )
                .frame(height: 220)
                
                Button {
                    viewModel.showUnsplashPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 13))
                        Text("Change photo")
                            .font(.bpCallout)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(16)
            }
        }
        
        // MARK: - Form fields
        
        private var formFields: some View {
            VStack(spacing: 24) {
                if let err = viewModel.saveError {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundColor(.bpError)
                        Text(err)
                            .font(.bpCallout)
                            .foregroundColor(.bpError)
                        Spacer()
                    }
                    .padding(14)
                    .background(Color.bpError.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                titleField
                modeToggle
                lifecycleList
                visibilityList
            }
            .padding(20)
        }

        private var lifecycleList: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("STATUS")
                    .font(.bpLabel)
                    .foregroundColor(.bpTextMuted)
                    .tracking(1.0)
                Text("Publishing marks the trip as complete. Visibility separately controls who can see it.")
                    .font(.bpCaption)
                    .foregroundColor(.bpTextSecondary)
                stateAction(
                    title: viewModel.isDraft ? "Draft" : "Published",
                    actionTitle: viewModel.isDraft ? "Publish trip" : "Move back to drafts",
                    transition: viewModel.isDraft ? .publishing : .movingToDraft,
                    destructive: !viewModel.isDraft,
                    disabled: !viewModel.isDraft && viewModel.visibility.lowercased() == "public"
                )
            }
        }
        
        private var titleField: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("TRIP NAME")
                    .font(.bpLabel)
                    .foregroundColor(.bpTextMuted)
                    .tracking(1.0)
                TextField("Trip name", text: $viewModel.title)
                    .font(.bpSubhead)
                    .foregroundColor(.bpInk)
                    .padding(14)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.bpBorder, lineWidth: 1)
                    )
            }
        }
        
        private var modeToggle: some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 8))
                : AnyLayout(HStackLayout(spacing: 0))
            return VStack(alignment: .leading, spacing: 8) {
                Text("MODE")
                    .font(.bpLabel)
                    .foregroundColor(.bpTextMuted)
                    .tracking(1.0)
                layout {
                    modeOption(isPlanning: false, label: "Documenting", icon: "pencil")
                    modeOption(isPlanning: true, label: "Planning", icon: "calendar")
                }
            }
        }
        
        private func modeOption(isPlanning: Bool, label: String, icon: String) -> some View {
            let isSelected = viewModel.isPlanning == isPlanning
            return Button {
                viewModel.isPlanning = isPlanning
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                    Text(label)
                        .font(.bpCallout)
                }
                .foregroundColor(isSelected ? .bpCobalt : .bpTextMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isSelected ? Color.bpCobalt.opacity(0.06) : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            isSelected ? Color.bpCobalt : Color.bpBorder,
                            lineWidth: isSelected ? 1.5 : 1
                        )
                )
            }
            .buttonStyle(.plain)
        }
        
        private var visibilityList: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("VISIBILITY")
                    .font(.bpLabel)
                    .foregroundColor(.bpTextMuted)
                    .tracking(1.0)
                VStack(spacing: 0) {
                    visibilityOption("Private")
                    BPDivider()
                    visibilityOption("Public")
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.bpBorder, lineWidth: 1)
                )
            }
        }
        
        private func visibilityOption(_ option: String) -> some View {
            let isSelected = viewModel.visibility.lowercased() == option.lowercased()
            let transition: EditTripViewModel.TripStateTransition = option.lowercased() == "public"
                ? .makingPublic : .makingPrivate
            return Button {
                guard !isSelected else { return }
                if transition == .makingPrivate && hasExploreSubmission {
                    confirmation = transition
                } else {
                    Task { await viewModel.changeState(transition) }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option)
                            .font(.bpBodyBold)
                            .foregroundColor(.bpInk)
                        Text(visibilitySubtitle(option))
                            .font(.bpCaption)
                            .foregroundColor(.bpTextMuted)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundColor(.bpCobalt)
                            .font(.system(size: 14, weight: .semibold))
                    } else if viewModel.activeTransition == transition {
                        ProgressView().tint(.bpCobalt)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(isSelected ? Color.bpCobalt.opacity(0.04) : Color.white)
            }
            .buttonStyle(.plain)
            .disabled(
                viewModel.activeTransition != nil
                || viewModel.isSaving
                || (transition == .makingPublic && viewModel.isDraft)
            )
            .accessibilityLabel("Visibility: \(option)")
        }
        
        private func visibilitySubtitle(_ v: String) -> String {
            switch v.lowercased() {
            case "private":       return "Only you can see this"
            case "public":        return "Anyone on board_postal"
            default:              return ""
            }
        }

        private func stateAction(
            title: String,
            actionTitle: String,
            transition: EditTripViewModel.TripStateTransition,
            destructive: Bool,
            disabled: Bool
        ) -> some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout())
            return layout {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.bpBodyBold).foregroundColor(.bpInk)
                    Text(actionTitle).font(.bpCaption).foregroundColor(.bpTextSecondary)
                }
                Spacer()
                if viewModel.activeTransition == transition {
                    ProgressView().tint(.bpCobalt)
                } else {
                    Button(actionTitle) {
                        if destructive && hasExploreSubmission {
                            confirmation = transition
                        } else {
                            Task { await viewModel.changeState(transition) }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(disabled || viewModel.activeTransition != nil || viewModel.isSaving)
                }
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.bpBorder))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Status: \(title). \(actionTitle)")
        }

        private var confirmationTitle: String {
            guard let confirmation else { return "Confirm change" }
            return transitionActionTitle(confirmation) + "?"
        }

        private func transitionActionTitle(
            _ transition: EditTripViewModel.TripStateTransition
        ) -> String {
            switch transition {
            case .publishing: return "Publish trip"
            case .movingToDraft: return "Move back to drafts"
            case .makingPublic: return "Make public"
            case .makingPrivate: return "Make private"
            }
        }
    }
    
private extension DateFormatter {
    static let previewFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - CollaboratorsViewModel

@MainActor
final class CollaboratorsViewModel: ObservableObject {
    let tripId: String
    let ownerId: String
    let currentUserId: String

    @Published var collaborators: [Collaborator] = []
    @Published var isLoading = false
    @Published var isInviting = false
    @Published var error: String? = nil
    @Published var inviteEmail = ""
    @Published var inviteRole = "viewer"

    var isOwner: Bool { currentUserId == ownerId }

    init(tripId: String,
         ownerId: String,
         currentUserId: String) {
        self.tripId = tripId
        self.ownerId = ownerId
        self.currentUserId = currentUserId
    }

    func load() async {
        isLoading = true
        do {
            collaborators = try await
                APIClient.shared.request(
                    .collaborators(tripId: tripId))
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func invite() async {
        guard !inviteEmail.isEmpty else { return }
        isInviting = true
        error = nil
        do {
            let body = InviteCollaboratorRequest(
                email: inviteEmail.lowercased()
                    .trimmingCharacters(
                        in: .whitespaces),
                role: inviteRole)
            let newCollab: Collaborator =
                try await APIClient.shared.request(
                    .collaborators(tripId: tripId),
                    method: .post,
                    body: body)
            collaborators.append(newCollab)
            inviteEmail = ""
        } catch {
            self.error = "Could not invite: "
                + error.localizedDescription
        }
        isInviting = false
    }

    func remove(_ collaborator: Collaborator) async {
        do {
            try await APIClient.shared.requestVoid(
                .collaborator(
                    tripId: tripId,
                    collaboratorId: collaborator.id),
                method: .delete)
            collaborators.removeAll {
                $0.id == collaborator.id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - CollaboratorsView

struct CollaboratorsView: View {
    @StateObject var viewModel: CollaboratorsViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showInviteSheet = false

    init(tripId: String,
         ownerId: String,
         currentUserId: String) {
        _viewModel = StateObject(
            wrappedValue: CollaboratorsViewModel(
                tripId: tripId,
                ownerId: ownerId,
                currentUserId: currentUserId))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.isLoading {
                    BPLoadingView()
                        .frame(height: 200)
                } else if viewModel.collaborators
                    .isEmpty {
                    BPEmptyState(
                        icon: "person.2",
                        title: "No collaborators",
                        message: "Invite friends to"
                            + " join this trip.",
                        actionTitle: viewModel.isOwner
                            ? "Invite someone" : nil,
                        action: viewModel.isOwner
                            ? { showInviteSheet = true }
                            : nil
                    )
                    .padding(.top, 40)
                } else {
                    List {
                        ForEach(
                            viewModel.collaborators
                        ) { collab in
                            CollaboratorRow(
                                collaborator: collab,
                                isOwner: viewModel.isOwner
                            )
                            .swipeActions(
                                edge: .trailing,
                                allowsFullSwipe: true
                            ) {
                                if viewModel.isOwner
                                    || collab.userId
                                    == viewModel
                                    .currentUserId {
                                    Button(
                                        role: .destructive
                                    ) {
                                        Task {
                                            await viewModel
                                            .remove(collab)
                                        }
                                    } label: {
                                        Label("Remove",
                                        systemImage:
                                        "person.badge.minus")
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }

                if let error = viewModel.error {
                    HStack(spacing: 8) {
                        Image(systemName:
                            "exclamationmark.circle")
                            .foregroundColor(.bpError)
                        Text(error)
                            .font(.bpCallout)
                            .foregroundColor(.bpError)
                        Spacer()
                    }
                    .padding(14)
                    .background(
                        Color.bpError.opacity(0.06))
                }

                Spacer()
            }
            .background(Color.bpBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.white,
                for: .navigationBar)
            .toolbarBackground(.visible,
                for: .navigationBar)
            .toolbar {
                ToolbarItem(
                    placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .buttonStyle(.plain)
                        .foregroundColor(.bpCobalt)
                }
                ToolbarItem(placement: .principal) {
                    Text("Travelling with")
                        .font(.bpBodyBold)
                        .foregroundColor(.bpInk)
                }
                if viewModel.isOwner {
                    ToolbarItem(
                        placement:
                        .navigationBarTrailing) {
                        Button {
                            showInviteSheet = true
                        } label: {
                            Image(systemName:
                                "person.badge.plus")
                                .foregroundColor(
                                    .bpCobalt)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .sheet(isPresented: $showInviteSheet) {
                InviteCollaboratorSheet(
                    viewModel: viewModel)
                .presentationDetents([.medium])
                .presentationDragIndicator(.hidden)
            }
            .presentationDragIndicator(.hidden)
        }
        .task { await viewModel.load() }
    }
}

// MARK: - CollaboratorRow

struct CollaboratorRow: View {
    let collaborator: Collaborator
    let isOwner: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.bpCobalt)
                    .frame(width: 44, height: 44)
                Text(collaborator.initials)
                    .font(BPFont.inter(
                        size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(collaborator.fullName)
                    .font(.bpBodyBold)
                    .foregroundColor(.bpInk)
                Text(collaborator.email)
                    .font(.bpCaption)
                    .foregroundColor(.bpTextMuted)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(collaborator.role.capitalized)
                    .font(.bpCaption)
                    .foregroundColor(.bpCobalt)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Color.bpCobalt.opacity(0.1))
                    .cornerRadius(4)

                if !collaborator.inviteAccepted {
                    Text("Pending")
                        .font(.bpCaption)
                        .foregroundColor(.bpSaffron)
                }
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(Color.white)
        .listRowSeparatorTint(.bpBorder)
    }
}

// MARK: - InviteCollaboratorSheet

struct InviteCollaboratorSheet: View {
    @ObservedObject var viewModel:
        CollaboratorsViewModel
    @Environment(\.dismiss) var dismiss
    @FocusState private var emailFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading,
                       spacing: 8) {
                    Text("EMAIL ADDRESS")
                        .font(.bpLabel)
                        .foregroundColor(.bpTextMuted)
                        .tracking(1.0)
                    TextField(
                        "friend@example.com",
                        text: $viewModel.inviteEmail)
                        .font(.bpBody)
                        .foregroundColor(.bpInk)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .focused($emailFocused)
                }
                .padding(20)

                BPDivider()

                VStack(alignment: .leading,
                       spacing: 8) {
                    Text("ROLE")
                        .font(.bpLabel)
                        .foregroundColor(.bpTextMuted)
                        .tracking(1.0)
                    HStack(spacing: 0) {
                        ForEach([
                            ("viewer", "Can view"),
                            ("editor", "Can edit")
                        ], id: \.0) { role, label in
                            Button {
                                viewModel.inviteRole
                                    = role
                            } label: {
                                VStack(spacing: 4) {
                                    Text(role
                                        .capitalized)
                                        .font(.bpBodyBold)
                                    Text(label)
                                        .font(.bpCaption)
                                }
                                .foregroundColor(
                                    viewModel.inviteRole
                                    == role
                                    ? .bpCobalt
                                    : .bpTextMuted)
                                .frame(maxWidth:
                                    .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    viewModel.inviteRole
                                    == role
                                    ? Color.bpCobalt
                                        .opacity(0.08)
                                    : Color.white)
                                .overlay(
                                    RoundedRectangle(
                                    cornerRadius: 10)
                                    .stroke(
                                    viewModel.inviteRole
                                    == role
                                    ? Color.bpCobalt
                                    : Color.bpBorder,
                                    lineWidth:
                                    viewModel.inviteRole
                                    == role ? 1.5 : 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)

                BPDivider()

                BPButton(
                    "Send invite",
                    style: .primary,
                    isLoading: viewModel.isInviting
                ) {
                    Task {
                        await viewModel.invite()
                        if viewModel.error == nil {
                            dismiss()
                        }
                    }
                }
                .disabled(
                    viewModel.inviteEmail.isEmpty
                    || viewModel.isInviting)
                .padding(20)

                Spacer()
            }
            .background(Color.bpBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.white,
                for: .navigationBar)
            .toolbarBackground(.visible,
                for: .navigationBar)
            .toolbar {
                ToolbarItem(
                    placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.plain)
                        .foregroundColor(
                            .bpTextSecondary)
                }
                ToolbarItem(placement: .principal) {
                    Text("Invite collaborator")
                        .font(.bpBodyBold)
                        .foregroundColor(.bpInk)
                }
            }
        }
        .onAppear { emailFocused = true }
    }
}

// MARK: - Previews

#Preview("Trips List") {
        let mockTrips: [Trip] = [
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
                createdAt: DateFormatter.previewFormatter.date(from: "2025-06-15") ?? Date(),
                ownerId: "owner-1",
                entryCount: 0,
                dayCount: 0,
                destinations: [
                    TripDestination(id: "1", country: "Turkey", city: "Istanbul", orderIndex: 0),
                    TripDestination(id: "2", country: "Turkey", city: "Cappadocia", orderIndex: 1)
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
                createdAt: DateFormatter.previewFormatter.date(from: "2025-08-01") ?? Date(),
                ownerId: "owner-1",
                entryCount: 0,
                dayCount: 0,
                destinations: [
                    TripDestination(id: "3", country: "Greece", city: "Santorini", orderIndex: 0)
                ]
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
                visibility: "Private",
                country: nil,
                city: nil,
                isDraft: true,
                isPlanning: false,
                createdAt: DateFormatter.previewFormatter.date(from: "2025-09-10") ?? Date(),
                ownerId: "owner-1",
                entryCount: 0,
                dayCount: 0,
                destinations: [
                    TripDestination(id: "4", country: "Italy", city: "Amalfi", orderIndex: 0),
                    TripDestination(id: "5", country: "Italy", city: "Positano", orderIndex: 1),
                    TripDestination(id: "6", country: "Italy", city: "Ravello", orderIndex: 2)
                ]
            )
        ]
        
        return NavigationStack {
            TripsListPreviewWrapper(mockTrips: mockTrips)
        }
    }

#if DEBUG
    #Preview("Drafts — One") {
        NavigationStack {
            TripsListPreviewWrapper(mockTrips: Array(TripsVisualVerificationData.drafts.prefix(1)))
        }
    }

    #Preview("Drafts — Multiple") {
        NavigationStack {
            TripsListPreviewWrapper(mockTrips: TripsVisualVerificationData.drafts)
        }
    }

    #Preview("Drafts — Accessibility") {
        NavigationStack {
            TripsListPreviewWrapper(mockTrips: TripsVisualVerificationData.drafts)
        }
        .environment(\.dynamicTypeSize, .accessibility3)
    }
#endif
    
    private struct TripsListPreviewWrapper: View {
        @StateObject private var viewModel: TripViewModel

        init(mockTrips: [Trip]) {
            let viewModel = TripViewModel()
            viewModel.trips = mockTrips
            _viewModel = StateObject(wrappedValue: viewModel)
        }
        
        var body: some View {
            TripsListView(viewModel: viewModel, automaticallyLoadsTrips: false)
        }
    }

    #Preview("Trip Detail") {
        let mockTrip = Trip(
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
            createdAt: DateFormatter.previewFormatter.date(from: "2025-06-15") ?? Date(),
            ownerId: "owner-1",
            entryCount: 0,
            dayCount: 0,
            destinations: [
                TripDestination(id: "1", country: "Turkey", city: "Istanbul", orderIndex: 0),
                TripDestination(id: "2", country: "Turkey", city: "Cappadocia", orderIndex: 1)
            ]
        )
        
        return NavigationStack {
            TripDetailPreviewWrapper(trip: mockTrip)
        }
    }
    
    private struct TripDetailPreviewWrapper: View {
        let trip: Trip
        
        var body: some View {
            TripDetailView(trip: trip)
                .onAppear {
                    // Inject mock data into the viewModel after it initializes
                    Task { @MainActor in
                        // Access the view model through the environment is not possible here,
                        // so the preview will show the empty/loading states.
                        // For populated previews, see TripDetailPopulated below.
                    }
                }
        }
    }
    
    #Preview("Trip Detail — Populated") {
        NavigationStack {
            TripDetailPopulatedPreview()
        }
    }
    
    private struct TripDetailPopulatedPreview: View {
        @StateObject private var viewModel = TripDetailViewModel(
            trip: Trip(
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
                createdAt: DateFormatter.previewFormatter.date(from: "2025-06-15") ?? Date(),
                ownerId: "owner-1",
                entryCount: 0,
                dayCount: 0,
                destinations: [
                    TripDestination(id: "1", country: "Turkey", city: "Istanbul", orderIndex: 0),
                    TripDestination(id: "2", country: "Turkey", city: "Cappadocia", orderIndex: 1)
                ]
            )
        )
        
        @State private var selectedTab = 2
        private let tabs = ["Journal", "Places", "Itinerary", "Map", "Photos"]
        
        var body: some View {
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Hero
                    ZStack(alignment: .bottomLeading) {
                        Rectangle()
                            .fill(Color.bpPrimaryDeep)
                            .frame(height: 300)
                        
                        LinearGradient(
                            colors: [Color.black.opacity(0), Color.black.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 300)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text(viewModel.trip.title)
                                .font(.bpTitle)
                                .foregroundColor(.white)
                            
                            Text(viewModel.trip.destinationSummary)
                                .font(.bpCallout)
                                .foregroundColor(.bpAzure)
                                .italic()
                            
                            HStack(spacing: 0) {
                                Text("Istanbul")
                                    .font(.bpCaption)
                                    .foregroundColor(.white)
                                Text(" \u{00B7} ")
                                    .font(.bpCaption)
                                    .foregroundColor(.bpTextMuted)
                                Text("Cappadocia")
                                    .font(.bpCaption)
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(20)
                    }
                    .frame(height: 300)
                    .clipped()
                    
                    // Tab bar
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedTab = index
                                    }
                                } label: {
                                    VStack(spacing: 0) {
                                        Spacer()
                                        Text(tab)
                                            .font(selectedTab == index ? .bpBodyBold : .bpCallout)
                                            .foregroundColor(selectedTab == index ? .bpInk : .bpTextMuted)
                                        Spacer()
                                        Rectangle()
                                            .fill(selectedTab == index ? Color.bpCobalt : Color.clear)
                                            .frame(height: 2)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(Color.white)
                        BPDivider()
                    }
                    
                    // Tab content with mock data
                    switch selectedTab {
                    case 0:
                        JournalTabView(entries: mockEntries, isLoading: false)
                    case 1:
                        PlacesTabView(places: mockPlaces, isLoading: false)
                    case 2:
                        ItineraryTabView(
                            tripId: "preview-trip-id",
                            days: mockDays)
                    case 3:
                        MapTabView(places: mockPlaces)
                    default:
                        PhotosTabView(assets: [], isLoading: false)
                    }
                }
            }
            .background(Color.bpBackground)
            .navigationTitle("Summer in Istanbul")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .ignoresSafeArea(edges: .top)
        }
        
        private var mockEntries: [TripEntry] {
            [
                TripEntry(
                    id: "1",
                    tripId: "1",
                    title: "Arrival at the Golden Horn",
                    content: "The ferry from Kadikoy cut through the choppy Bosphorus waters as the sun dipped behind the minarets of Sultanahmet. Istanbul greeted us with the call to prayer echoing across the water, a sound that immediately made this city feel ancient and alive.",
                    entryDate: "2025-06-15",
                    placeName: "Sultanahmet",
                    orderIndex: 0,
                    visibility: "Public",
                    isDraft: false,
                    createdAt: DateFormatter.previewFormatter.date(from: "2025-06-15") ?? Date(),
                    updatedAt: nil
                ),
                TripEntry(
                    id: "2",
                    tripId: "1",
                    title: "Grand Bazaar & Spice Market",
                    content: "Lost in the labyrinthine corridors of the Grand Bazaar, every turn revealed another treasure — hand-painted ceramics, Turkish lamps casting kaleidoscope shadows, merchants offering apple tea with warm smiles.",
                    entryDate: "2025-06-17",
                    placeName: nil,
                    orderIndex: 1,
                    visibility: "Public",
                    isDraft: true,
                    createdAt: DateFormatter.previewFormatter.date(from: "2025-06-17") ?? Date(),
                    updatedAt: nil
                )
            ]
        }
        
        private var mockDays: [TripDay] {
            [
                TripDay(
                    id: "d1",
                    tripId: "1",
                    dayNumber: 1,
                    title: "Arrival & Sultanahmet",
                    date: "2025-06-15",
                    orderIndex: 0,
                    items: []
                ),
                TripDay(
                    id: "d2",
                    tripId: "1",
                    dayNumber: 2,
                    title: "Bosphorus & Spice Market",
                    date: "2025-06-16",
                    orderIndex: 1,
                    items: []
                )
            ]
        }
        
        private var mockPlaces: [TripPlace] {
            [
                TripPlace(
                    id: "1",
                    tripId: "1",
                    placeId: "1",
                    placeName: "Hagia Sophia",
                    category: "museum",
                    latitude: 41.0086,
                    longitude: 28.9802,
                    notes: "Incredible mosaics",
                    orderIndex: 0,
                    imageUrl: nil
                ),
                TripPlace(
                    id: "2",
                    tripId: "1",
                    placeId: "2",
                    placeName: "Sultanahmet Koftecisi",
                    category: "restaurant",
                    latitude: 41.0082,
                    longitude: 28.9784,
                    notes: "Best kebabs in the old city",
                    orderIndex: 1,
                    imageUrl: nil
                )
            ]
        }
    }
