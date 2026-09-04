import SwiftUI
import Combine

// MARK: - Supporting types

struct DraftDestination: Identifiable {
    let id = UUID()
    var city: String
    var country: String
}

struct AddDestinationRequest: Encodable {
    let city: String
    let country: String
    let orderIndex: Int
}

// MARK: - Visibility display helpers

func visibilityLabel(_ raw: String) -> String {
    switch raw.lowercased() {
    case "private":       return "Private"
    case "collaborative": return "Collaborative"
    case "public":        return "Public"
    default:              return raw.capitalized
    }
}

func visibilitySubtitle(_ raw: String) -> String {
    switch raw.lowercased() {
    case "private":       return "Only you can see this"
    case "collaborative": return "You and collaborators"
    case "public":        return "Anyone on board_postal"
    default:              return ""
    }
}

// MARK: - CreateTripViewModel

@MainActor
final class CreateTripViewModel: ObservableObject {
    @Published var currentStep: Int = 0
    @Published var title: String = ""
    @Published var isPlanning: Bool = false
    @Published var startDate: Date? = nil
    @Published var endDate: Date? = nil
    @Published var visibility: String = "Private"
    @Published var destinations: [DraftDestination] = []
    @Published var newCity: String = ""
    @Published var newCountry: String = ""
    @Published var isSaving: Bool = false
    @Published var saveError: String? = nil
    @Published var createdTripId: String? = nil

    // Cover photo (new — Phase 3)
    @Published var coverPhotoUrl: String? = nil
    @Published var coverPhotoAttribution: String? = nil
    @Published var coverPhotoAttributionUrl: String? = nil
    @Published var isUploadingCover: Bool = false
    @Published var coverUploadError: String? = nil

    private let api = APIClient.shared

    let totalSteps = 4

    var progressFraction: Double {
        Double(currentStep + 1) / Double(totalSteps)
    }

    var canProceedStep0: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var canProceedStep1: Bool {
        !destinations.isEmpty
    }

    var canFinish: Bool {
        canProceedStep0 && canProceedStep1
    }

    func nextStep() {
        currentStep = min(currentStep + 1, totalSteps - 1)
    }

    func previousStep() {
        currentStep = max(currentStep - 1, 0)
    }

    func addDestination() {
        guard !newCity.trimmingCharacters(in: .whitespaces).isEmpty,
              !newCountry.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        destinations.append(DraftDestination(city: newCity, country: newCountry))
        newCity = ""
        newCountry = ""
    }

    func removeDestination(id: UUID) {
        destinations.removeAll { $0.id == id }
    }

    // MARK: - Cover photo

    func uploadCover(image: UIImage) async {
        isUploadingCover = true
        coverUploadError = nil
        defer { isUploadingCover = false }
        do {
            let asset = try await MediaUploader.shared.upload(image)
            coverPhotoUrl = asset.fileUrl
            coverPhotoAttribution = nil
            coverPhotoAttributionUrl = nil
        } catch {
            coverUploadError = "Couldn't upload that photo. Try another one."
        }
    }

    func applyUnsplashCover(_ photo: UnsplashPhoto) {
        coverPhotoUrl = photo.fullURL?.absoluteString
        coverPhotoAttribution = photo.user?.name
        coverPhotoAttributionUrl = photo.attributionUrl
        coverUploadError = nil
    }

    func clearCover() {
        coverPhotoUrl = nil
        coverPhotoAttribution = nil
        coverPhotoAttributionUrl = nil
        coverUploadError = nil
    }

    func save() async {
        isSaving = true
        saveError = nil

        do {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"

            let startStr = startDate.map { formatter.string(from: $0) }
            let endStr = endDate.map { formatter.string(from: $0) }

            // Step 1 — Create the trip (no isDraft/isPlanning on create DTO)
            let createBody = CreateTripRequest(
                title: title,
                visibility: visibility,
                plannedStartDate: startStr,
                plannedEndDate: endStr
            )
            let created: Trip = try await api.request(.trips, method: .post, body: createBody)

            // Step 2 — If isPlanning is set OR a cover is set, PUT to apply.
            if isPlanning || coverPhotoUrl != nil {
                let updateBody = UpdateTripRequest(
                    title: nil,
                    visibility: nil,
                    isDraft: nil,
                    isPlanning: isPlanning ? true : nil,
                    coverPhotoUrl: coverPhotoUrl,
                    coverPhotoAttribution: coverPhotoAttribution,
                    coverPhotoAttributionUrl: coverPhotoAttributionUrl
                )
                _ = try? await api.request(
                    .trip(id: created.id),
                    method: .put,
                    body: updateBody
                ) as Trip
            }

            for (index, dest) in destinations.enumerated() {
                let destBody = AddDestinationRequest(
                    city: dest.city,
                    country: dest.country,
                    orderIndex: index
                )
                let _: TripDestination = try await api.request(
                    .destinations(tripId: created.id),
                    method: .post,
                    body: destBody
                )
            }

            createdTripId = created.id
        } catch {
            saveError = error.localizedDescription
        }

        isSaving = false
    }
}

// MARK: - CreateTripView

struct CreateTripView: View {
    @StateObject private var viewModel: CreateTripViewModel
    @Environment(\.dismiss) var dismiss

    private let stepTitles = ["New trip", "Destinations", "Cover", "Style"]

    init() {
        _viewModel = StateObject(wrappedValue: CreateTripViewModel())
    }

    init(viewModel: CreateTripViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress bar
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.bpLimestone)
                        .frame(height: 4)

                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.bpCobalt)
                            .frame(width: geo.size.width * viewModel.progressFraction, height: 4)
                            .animation(.easeInOut(duration: 0.3), value: viewModel.progressFraction)
                    }
                    .frame(height: 4)
                }

                // Step content
                Group {
                    switch viewModel.currentStep {
                    case 0:
                        StepBasicsView(viewModel: viewModel)
                    case 1:
                        StepDestinationsView(viewModel: viewModel)
                    case 2:
                        StepCoverView(viewModel: viewModel)
                    case 3:
                        StepStyleView(viewModel: viewModel)
                    default:
                        EmptyView()
                    }
                }
                .frame(maxHeight: .infinity)

                // Bottom nav
                CreateTripBottomBar(viewModel: viewModel, onFinish: {
                    Task { await viewModel.save() }
                })
            }
            .background(Color.bpBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.white, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if viewModel.currentStep == 0 {
                        Button("Cancel") { dismiss() }
                            .buttonStyle(.plain)
                            .font(.bpCallout)
                            .foregroundColor(.bpTextSecondary)
                    } else {
                        Button { viewModel.previousStep() } label: {
                            Image(systemName: "chevron.left")
                                .foregroundColor(.bpInk)
                        }
                        .buttonStyle(.plain)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(stepTitles[viewModel.currentStep])
                        .font(.bpBodyBold)
                        .foregroundColor(.bpInk)
                }
            }
        }
        .onChange(of: viewModel.createdTripId) { _, id in
            if id != nil { dismiss() }
        }
    }
}

// MARK: - CreateTripBottomBar

private struct CreateTripBottomBar: View {
    @ObservedObject var viewModel: CreateTripViewModel
    let onFinish: () -> Void

    private var canContinue: Bool {
        switch viewModel.currentStep {
        case 0: return viewModel.canProceedStep0
        case 1: return viewModel.canProceedStep1
        default: return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            BPDivider()

            HStack(spacing: 12) {
                if viewModel.currentStep > 0 {
                    BPButton("Back", style: .secondary) {
                        viewModel.previousStep()
                    }
                    .frame(width: 100)
                }

                if viewModel.currentStep < 3 {
                    BPButton("Continue") {
                        viewModel.nextStep()
                    }
                    .disabled(!canContinue)
                    .opacity(canContinue ? 1.0 : 0.4)
                } else {
                    BPButton("Create trip", style: .primary, isLoading: viewModel.isSaving) {
                        onFinish()
                    }
                    .disabled(!viewModel.canFinish)
                    .opacity(viewModel.canFinish ? 1.0 : 0.4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color.white)
    }
}

// MARK: - Step 0: Basics

private struct StepBasicsView: View {
    @ObservedObject var viewModel: CreateTripViewModel
    @State private var selectingEnd = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Trip name
                VStack(alignment: .leading, spacing: 12) {
                    BPSectionHeader(title: "Trip name")

                    TextField("e.g. Summer in Istanbul", text: $viewModel.title)
                        .font(.bpSubhead)
                        .foregroundColor(.bpInk)
                        .padding(14)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.bpBorder, lineWidth: 1))
                }

                // Mode toggle
                VStack(alignment: .leading, spacing: 12) {
                    BPSectionHeader(title: "What are you doing?")

                    HStack(spacing: 0) {
                        ModeButton(
                            title: "Planning ahead",
                            subtitle: "Build an itinerary",
                            icon: "calendar",
                            isSelected: viewModel.isPlanning
                        ) { viewModel.isPlanning = true }

                        ModeButton(
                            title: "Documenting now",
                            subtitle: "Write as you go",
                            icon: "pencil",
                            isSelected: !viewModel.isPlanning
                        ) { viewModel.isPlanning = false }
                    }
                }

                // Dates
                VStack(alignment: .leading, spacing: 12) {
                    BPSectionHeader(title: "Dates (optional)")

                    VStack(spacing: 0) {
                        // Mode selector
                        HStack(spacing: 0) {
                            Text("FROM")
                                .font(.bpLabel)
                                .tracking(1.0)
                                .foregroundColor(!selectingEnd ? .white : .bpTextMuted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(!selectingEnd ? Color.bpCobalt : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture { selectingEnd = false }

                            Text("TO")
                                .font(.bpLabel)
                                .tracking(1.0)
                                .foregroundColor(selectingEnd ? .white : .bpTextMuted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(selectingEnd ? Color.bpCobalt : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture { selectingEnd = true }
                        }
                        .background(Color.bpLimestone)
                        .overlay(Rectangle().stroke(Color.bpBorder, lineWidth: 1))

                        // Date display row
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                if let start = viewModel.startDate {
                                    Text(start, format: .dateTime.day().month(.wide).year())
                                        .font(.bpBody)
                                        .foregroundColor(.bpInk)
                                } else {
                                    Text("Select start date")
                                        .font(.bpBody)
                                        .foregroundColor(.bpStone)
                                }
                            }

                            Spacer()

                            Image(systemName: "arrow.right")
                                .foregroundColor(.bpStone)
                                .font(.system(size: 12))

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                if let end = viewModel.endDate {
                                    Text(end, format: .dateTime.day().month(.wide).year())
                                        .font(.bpBody)
                                        .foregroundColor(.bpInk)
                                } else {
                                    Text("Select end date")
                                        .font(.bpBody)
                                        .foregroundColor(.bpStone)
                                }
                            }
                        }
                        .padding(14)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.bpBorder, lineWidth: 1))

                        // Inline calendar
                        DatePicker(
                            "",
                            selection: Binding(
                                get: {
                                    selectingEnd
                                        ? (viewModel.endDate ?? viewModel.startDate ?? Date())
                                        : (viewModel.startDate ?? Date())
                                },
                                set: { newDate in
                                    if selectingEnd {
                                        viewModel.endDate = newDate
                                    } else {
                                        viewModel.startDate = newDate
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            selectingEnd = true
                                        }
                                    }
                                }
                            ),
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .tint(.bpCobalt)
                        .accentColor(.bpCobalt)
                        .foregroundStyle(Color.bpInk)
                        .padding(.horizontal, 4)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.bpBorder, lineWidth: 1))
                        .environment(\.colorScheme, .light)
                    }

                    if viewModel.startDate != nil || viewModel.endDate != nil {
                        Button("Clear dates") {
                            viewModel.startDate = nil
                            viewModel.endDate = nil
                            selectingEnd = false
                        }
                        .font(.bpCaption)
                        .foregroundColor(.bpTextMuted)
                    }
                }
            }
            .padding(20)
        }
    }
}

// MARK: - ModeButton

private struct ModeButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(isSelected ? .bpCobalt : .bpTextMuted)

            Text(title)
                .font(isSelected ? .bpBodyBold : .bpCallout)
                .foregroundColor(.bpInk)

            Text(subtitle)
                .font(.bpCaption)
                .foregroundColor(.bpTextMuted)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(isSelected ? Color.bpCobalt.opacity(0.06) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(
                isSelected ? Color.bpCobalt : Color.bpBorder,
                lineWidth: isSelected ? 1.5 : 1
            )
        )
        .onTapGesture { action() }
    }
}

// MARK: - Step 1: Destinations

private struct StepDestinationsView: View {
    @ObservedObject var viewModel: CreateTripViewModel

    private var canAdd: Bool {
        !viewModel.newCity.trimmingCharacters(in: .whitespaces).isEmpty
            && !viewModel.newCountry.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                BPSectionHeader(title: "Where are you going?")

                // Add form
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("CITY")
                                .font(.bpLabel)
                                .foregroundColor(.bpTextMuted)
                                .tracking(1.0)

                            TextField("Istanbul", text: $viewModel.newCity)
                                .font(.bpBody)
                                .foregroundColor(.bpInk)
                                .padding(12)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.bpBorder, lineWidth: 1))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("COUNTRY")
                                .font(.bpLabel)
                                .foregroundColor(.bpTextMuted)
                                .tracking(1.0)

                            TextField("Turkey", text: $viewModel.newCountry)
                                .font(.bpBody)
                                .foregroundColor(.bpInk)
                                .padding(12)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.bpBorder, lineWidth: 1))
                        }
                    }

                    BPButton("Add destination", style: .secondary) {
                        viewModel.addDestination()
                    }
                    .opacity(viewModel.newCity.isEmpty || viewModel.newCountry.isEmpty ? 0.4 : 1.0)
                    .disabled(viewModel.newCity.isEmpty || viewModel.newCountry.isEmpty)
                }

                // Added list
                if !viewModel.destinations.isEmpty {
                    VStack(spacing: 0) {
                        BPSectionHeader(title: "Your route")
                            .padding(.bottom, 8)

                        ForEach(Array(viewModel.destinations.enumerated()), id: \.element.id) { index, dest in
                            DestinationRow(dest: dest) {
                                viewModel.removeDestination(id: dest.id)
                            }

                            if index < viewModel.destinations.count - 1 {
                                BPDivider()
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

// MARK: - DestinationRow

private struct DestinationRow: View {
    let dest: DraftDestination
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(dest.city)
                    .font(.bpBodyBold)
                    .foregroundColor(.bpInk)

                Text(dest.country)
                    .font(.bpCaption)
                    .foregroundColor(.bpTextMuted)
            }

            Spacer()

            Button { onDelete() } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.bpTextMuted)
            }
        }
        .padding(.vertical, 14)
    }
}

// MARK: - Step 2: Style

// MARK: - Step 2: Cover

private struct StepCoverView: View {
    @ObservedObject var viewModel: CreateTripViewModel
    @State private var showPhotoLibraryPicker = false
    @State private var showUnsplashPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                BPSectionHeader(title: "Cover photo")

                if let urlStr = viewModel.coverPhotoUrl,
                   let coverURL = URL(string: urlStr) {
                    selectedState(coverURL: coverURL)
                } else {
                    emptyState
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showPhotoLibraryPicker) {
            PhotoLibraryPicker(images: Binding(
                get: { [] },
                set: { picked in
                    if let first = picked.first {
                        Task { await viewModel.uploadCover(image: first) }
                    }
                }
            ))
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showUnsplashPicker) {
            UnsplashPickerView(
                onSelect: { photo in
                    viewModel.applyUnsplashCover(photo)
                },
                initialQuery: viewModel.destinations.first?.city
            )
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Optional — give your trip visual identity")
                .font(.bpCallout)
                .foregroundColor(.bpTextSecondary)

            if viewModel.isUploadingCover {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.bpCobalt)
                        .scaleEffect(0.8)
                    Text("Uploading…")
                        .font(.bpCallout)
                        .foregroundColor(.bpTextSecondary)
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 12) {
                    BPButton("Choose from library", style: .primary) {
                        showPhotoLibraryPicker = true
                    }
                    BPButton("Browse Unsplash", style: .ghost) {
                        showUnsplashPicker = true
                    }
                }
            }

            if let error = viewModel.coverUploadError {
                Text(error)
                    .font(.bpCaption)
                    .foregroundColor(.bpError)
            }
        }
    }

    @ViewBuilder
    private func selectedState(coverURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: coverURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        Rectangle().fill(Color.bpLimestone)
                    }
                }
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .clipped()

                if let attribution = viewModel.coverPhotoAttribution {
                    Text("Photo by \(attribution) on Unsplash")
                        .font(.bpCaption)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.5))
                }
            }

            HStack(spacing: 12) {
                BPButton("Change", style: .ghost) {
                    viewModel.clearCover()
                }
                BPButton("Remove", style: .ghost) {
                    viewModel.clearCover()
                }
            }
        }
    }
}

// MARK: - Step 3: Style

private struct StepStyleView: View {
    @ObservedObject var viewModel: CreateTripViewModel

    private let visibilityOptions: [String] = ["Private", "Collaborative", "Public"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Visibility
                VStack(alignment: .leading, spacing: 12) {
                    BPSectionHeader(title: "Who can see this trip?")

                    VStack(spacing: 0) {
                        ForEach(Array(visibilityOptions.enumerated()), id: \.element) { index, option in
                            VisibilityRow(
                                option: option,
                                isSelected: viewModel.visibility == option
                            ) {
                                viewModel.visibility = option
                            }

                            if index < visibilityOptions.count - 1 {
                                BPDivider()
                            }
                        }
                    }
                }

                // Summary
                VStack(alignment: .leading, spacing: 0) {
                    BPSectionHeader(title: "Summary")
                        .padding(.bottom, 12)

                    BPCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(viewModel.title)
                                .font(.bpSubhead)
                                .foregroundColor(.bpInk)

                            if !viewModel.destinations.isEmpty {
                                Text(viewModel.destinations
                                    .map { "\($0.city), \($0.country)" }
                                    .joined(separator: " → "))
                                    .font(.bpCallout)
                                    .foregroundColor(.bpTextSecondary)
                            }

                            HStack(spacing: 8) {
                                BPBadge(
                                    viewModel.isPlanning ? "Planning" : "Documenting",
                                    color: viewModel.isPlanning ? .bpAzure : .bpSaffron
                                )
                                BPBadge(visibilityLabel(viewModel.visibility), color: .bpTextMuted)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Error
                if let error = viewModel.saveError {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundColor(.bpError)
                            .font(.system(size: 16))

                        Text(error)
                            .font(.bpCallout)
                            .foregroundColor(.bpError)

                        Spacer()
                    }
                    .padding(14)
                    .background(Color.bpError.opacity(0.08))
                    .overlay(
                        Rectangle()
                            .stroke(Color.bpError.opacity(0.3), lineWidth: 1)
                    )
                }
            }
            .padding(20)
        }
    }
}

// MARK: - VisibilityRow

private struct VisibilityRow: View {
    let option: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(visibilityLabel(option))
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
                    .font(.callout)
                    .fontWeight(.semibold)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(isSelected ? Color.bpCobalt.opacity(0.04) : Color.white)
        .onTapGesture { onSelect() }
    }
}

// MARK: - Previews

#Preview("Step 0 — Basics") {
    CreateTripView()
}

#Preview("Step 1 — Destinations") {
    let vm = CreateTripViewModel()
    vm.currentStep = 1
    vm.title = "Summer in Istanbul"
    vm.destinations = [
        DraftDestination(city: "Istanbul", country: "Turkey"),
        DraftDestination(city: "Cappadocia", country: "Turkey")
    ]
    return CreateTripView(viewModel: vm)
}

#Preview("Step 2 — Style") {
    let vm = CreateTripViewModel()
    vm.currentStep = 2
    vm.title = "Summer in Istanbul"
    vm.destinations = [
        DraftDestination(city: "Istanbul", country: "Turkey"),
        DraftDestination(city: "Cappadocia", country: "Turkey")
    ]
    vm.visibility = "Public"
    return CreateTripView(viewModel: vm)
}
