import SwiftUI
import Combine
import CoreLocation
import PhotosUI

// MARK: - LocationManager
// Lightweight reverse-geocoder used by QuickCaptureView and
// TripEntryComposerView. Defined once here; both views consume it.

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    @Published var locationLabel: String? = nil
    @Published var coordinate: CLLocationCoordinate2D? = nil
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestOnce() {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let loc = locations.first else { return }
        Task { @MainActor in
            self.coordinate = loc.coordinate
            await self.reverseGeocode(loc)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        // Silent fail — location is best-effort
    }

    private func reverseGeocode(_ location: CLLocation) async {
        let geocoder = CLGeocoder()
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first
        else { return }
        let parts = [placemark.name, placemark.locality].compactMap { $0 }
        self.locationLabel = parts.prefix(2).joined(separator: ", ")
    }
}

// MARK: - CameraCapture (UIImagePickerController bridge)

struct CameraCapture: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCapture
        init(_ p: CameraCapture) { parent = p }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - QuickCaptureViewModel

@MainActor
final class QuickCaptureViewModel: ObservableObject {
    @Published var trips: [Trip] = []
    @Published var selectedTrip: Trip? = nil
    @Published var title: String = ""
    @Published var content: String = ""
    @Published var entryDate: Date = Date()
    @Published var isDraft: Bool = false
    @Published var isSaving: Bool = false
    @Published var saveError: String? = nil
    @Published var didSaveSuccessfully: Bool = false
    @Published var attachedPhoto: UIImage? = nil

    private let api = APIClient.shared

    var wordCount: Int {
        guard !content.isEmpty else { return 0 }
        return content.split(whereSeparator: \.isWhitespace).count
    }

    var canSave: Bool {
        content.trimmingCharacters(in: .whitespaces).count > 0
            && selectedTrip != nil
    }

    func loadTrips() async {
        do {
            let result: [Trip] = try await api.request(.trips)
            trips = result
            if selectedTrip == nil {
                selectedTrip = result.first(where: { !$0.isDraft })
            }
        } catch {
            // Silently fail — trips list is supplementary
        }
    }

    func save() async {
        guard canSave, let trip = selectedTrip else { return }
        isSaving = true
        saveError = nil

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let body = CreateEntryRequest(
            title: title.isEmpty ? nil : title,
            content: content,
            entryDate: formatter.string(from: entryDate),
            placeId: nil,
            orderIndex: 0,
            visibility: "private"
        )

        do {
            let _: TripEntry = try await api.request(
                .entries(tripId: trip.id),
                method: .post,
                body: body
            )
            if let photo = attachedPhoto,
               let tripId = selectedTrip?.id,
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
            didSaveSuccessfully = true
        } catch {
            saveError = error.localizedDescription
        }

        isSaving = false
    }

}

// MARK: - QuickCaptureView

struct QuickCaptureView: View {
    @StateObject private var viewModel = QuickCaptureViewModel()
    @StateObject private var locationManager = LocationManager()
    @Environment(\.dismiss) var dismiss
    @FocusState private var contentFocused: Bool
    @State private var showSuccessOverlay = false
    @State private var showCamera = false
    @State private var showPhotoLibrary = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // SECTION 1: Trip selector
                    tripSelector

                    BPDivider()
                        .padding(.top, 12)

                    // SECTION 2: Date
                    dateRow

                    BPDivider()

                    // SECTION 2b: Photo attach + location
                    photoAttachRow

                    BPDivider()

                    if let label = locationManager.locationLabel {
                        locationPill(label: label)
                        BPDivider()
                    }

                    // SECTION 3: Title
                    TextField("Title (optional)", text: $viewModel.title)
                        .font(.bpSubhead)
                        .foregroundColor(.bpInk)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)

                    BPDivider()

                    // SECTION 4: Content
                    contentArea

                    // SECTION 5: Bottom metadata
                    metadataBar

                    BPDivider()

                    // Error banner
                    if let error = viewModel.saveError {
                        errorBanner(error)
                    }
                }
            }
            .background(Color.white)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.white, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
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
                    Button {
                        Task { await viewModel.save() }
                    } label: {
                        if viewModel.isSaving {
                            ProgressView()
                                .tint(.bpCobalt)
                        } else {
                            Text("Save")
                                .font(.bpBodyBold)
                                .foregroundColor(.bpCobalt)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.canSave || viewModel.isSaving)
                    .opacity(viewModel.canSave ? 1.0 : 0.4)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        contentFocused = false
                    }
                    .buttonStyle(.plain)
                    .font(.bpCallout)
                    .foregroundColor(.bpCobalt)
                }
            }
        }
        .task {
            await viewModel.loadTrips()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                contentFocused = true
            }
            locationManager.requestOnce()
        }
        .sheet(isPresented: $showCamera) {
            CameraCapture(image: Binding(
                get: { viewModel.attachedPhoto },
                set: { viewModel.attachedPhoto = $0 }
            ))
            .ignoresSafeArea()
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showPhotoLibrary) {
            PhotoLibraryPicker(images: Binding(
                get: { viewModel.attachedPhoto.map { [$0] } ?? [] },
                set: { viewModel.attachedPhoto = $0.first }
            ))
            .presentationDragIndicator(.hidden)
        }
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
        .onChange(of: viewModel.didSaveSuccessfully) { _, success in
            guard success else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showSuccessOverlay = true
            Task {
                try? await Task.sleep(nanoseconds: 800_000_000)
                dismiss()
            }
        }
    }

    // MARK: - Trip selector

    private var tripSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ATTACH TO TRIP")
                .font(.bpLabel)
                .foregroundColor(.bpTextMuted)
                .tracking(1.0)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.trips) { trip in
                        TripChip(
                            trip: trip,
                            isSelected: viewModel.selectedTrip?.id == trip.id
                        )
                        .onTapGesture {
                            viewModel.selectedTrip = trip
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Date row

    private var dateRow: some View {
        HStack {
            Image(systemName: "calendar")
                .foregroundColor(.bpCobalt)
                .font(.system(size: 14))

            DatePicker("", selection: $viewModel.entryDate, displayedComponents: .date)
                .labelsHidden()
                .font(.bpCallout)
                .tint(.bpCobalt)

            Spacer()

            Text(viewModel.entryDate, style: .relative)
                .font(.bpCaption)
                .foregroundColor(.bpTextMuted)
            + Text(" ago")
                .font(.bpCaption)
                .foregroundColor(.bpTextMuted)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
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

            if let photo = viewModel.attachedPhoto {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Button { viewModel.attachedPhoto = nil } label: {
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

    // MARK: - Content area

    private var contentArea: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.content.isEmpty {
                Text("What happened today?\nWhere did you go? What did you feel?")
                    .font(.bpBody)
                    .foregroundColor(.bpStone)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $viewModel.content)
                .font(.bpBody)
                .foregroundColor(.bpInk)
                .padding(.horizontal, 16)
                .frame(minHeight: 280)
                .scrollDisabled(true)
                .focused($contentFocused)
                .scrollContentBackground(.hidden)
                .background(Color.white)
        }
    }

    // MARK: - Metadata bar

    private var metadataBar: some View {
        HStack {
            Text("\(viewModel.wordCount) words")
                .font(.bpCaption)
                .foregroundColor(.bpTextMuted)

            Spacer()

            HStack(spacing: 6) {
                Text("SAVE AS DRAFT")
                    .font(.bpLabel)
                    .foregroundColor(viewModel.isDraft ? .bpSaffron : .bpTextMuted)
                    .tracking(0.8)

                Toggle("", isOn: $viewModel.isDraft)
                    .labelsHidden()
                    .tint(.bpSaffron)
                    .scaleEffect(0.8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .foregroundColor(.bpError)
                .font(.system(size: 16))

            Text(message)
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
        .padding(.horizontal, 20)
    }
}

// MARK: - TripChip

struct TripChip: View {
    let trip: Trip
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
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
                .frame(width: 24, height: 24)
                .clipped()
            } else {
                Rectangle()
                    .fill(Color.bpPrimaryDeep)
                    .frame(width: 24, height: 24)
            }

            Text(trip.title)
                .font(.bpCallout)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.bpCobalt : Color.bpLimestone)
        .foregroundColor(isSelected ? .white : .bpInk)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    isSelected ? Color.bpCobalt : Color.bpBorder,
                    lineWidth: isSelected ? 0 : 1
                )
        )
    }
}

// MARK: - Preview

#Preview("Quick Capture — Populated") {
    QuickCapturePreviewContent()
}

private struct QuickCapturePreviewContent: View {
    @StateObject private var viewModel = QuickCaptureViewModel()

    private var mockTrips: [Trip] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return [
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
                createdAt: formatter.date(from: "2025-06-15") ?? Date(),
                ownerId: "owner-1",
                entryCount: 0,
                dayCount: 0,
                destinations: [TripDestination(id: "1", country: "Turkey", city: "Istanbul", orderIndex: 0)]
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
                createdAt: formatter.date(from: "2025-08-01") ?? Date(),
                ownerId: "owner-2",
                entryCount: 0,
                dayCount: 0,
                destinations: [TripDestination(id: "3", country: "Greece", city: "Santorini", orderIndex: 0)]
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
                isDraft: false,
                isPlanning: false,
                createdAt: formatter.date(from: "2025-09-10") ?? Date(),
                ownerId: "owner-3",
                entryCount: 0,
                dayCount: 0,
                destinations: [TripDestination(id: "4", country: "Italy", city: "Amalfi", orderIndex: 0)]
            )
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Trip selector
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ATTACH TO TRIP")
                            .font(.bpLabel)
                            .foregroundColor(.bpTextMuted)
                            .tracking(1.0)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(viewModel.trips) { trip in
                                    TripChip(
                                        trip: trip,
                                        isSelected: viewModel.selectedTrip?.id == trip.id
                                    )
                                    .onTapGesture { viewModel.selectedTrip = trip }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    BPDivider().padding(.top, 12)

                    // Date row
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.bpCobalt)
                            .font(.system(size: 14))
                        DatePicker("", selection: $viewModel.entryDate, displayedComponents: .date)
                            .labelsHidden()
                            .tint(.bpCobalt)
                        Spacer()
                        Text(viewModel.entryDate, style: .relative)
                            .font(.bpCaption)
                            .foregroundColor(.bpTextMuted)
                        + Text(" ago")
                            .font(.bpCaption)
                            .foregroundColor(.bpTextMuted)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                    BPDivider()

                    // Title
                    TextField("Title (optional)", text: $viewModel.title)
                        .font(.bpSubhead)
                        .foregroundColor(.bpInk)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)

                    BPDivider()

                    // Content
                    ZStack(alignment: .topLeading) {
                        if viewModel.content.isEmpty {
                            Text("What happened today?\nWhere did you go? What did you feel?")
                                .font(.bpBody)
                                .foregroundColor(.bpStone)
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $viewModel.content)
                            .font(.bpBody)
                            .foregroundColor(.bpInk)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 280)
                            .scrollDisabled(true)
                            .scrollContentBackground(.hidden)
                            .background(Color.white)
                    }

                    // Metadata bar
                    HStack {
                        Text("\(viewModel.wordCount) words")
                            .font(.bpCaption)
                            .foregroundColor(.bpTextMuted)
                        Spacer()
                        HStack(spacing: 6) {
                            Text("SAVE AS DRAFT")
                                .font(.bpLabel)
                                .foregroundColor(viewModel.isDraft ? .bpSaffron : .bpTextMuted)
                                .tracking(0.8)
                            Toggle("", isOn: $viewModel.isDraft)
                                .labelsHidden()
                                .tint(.bpSaffron)
                                .scaleEffect(0.8)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                    BPDivider()
                }
            }
            .background(Color.white)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Text("Cancel")
                        .font(.bpCallout)
                        .foregroundColor(.bpTextSecondary)
                }
                ToolbarItem(placement: .principal) {
                    Text("New Entry")
                        .font(.bpBodyBold)
                        .foregroundColor(.bpInk)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Text("Save")
                        .font(.bpBodyBold)
                        .foregroundColor(.bpCobalt)
                }
            }
        }
        .onAppear {
            viewModel.trips = mockTrips
            viewModel.selectedTrip = mockTrips.first
            viewModel.content = "Arrived at Sultanahmet just before sunset. The call to prayer echoed across the Golden Horn, bouncing between the domes of the Blue Mosque and Hagia Sophia. We found a small tea garden tucked behind the Arasta Bazaar and sat watching the light change over the Sea of Marmara."
        }
    }
}
