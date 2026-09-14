import SwiftUI

// MARK: - board_postal Component Library
// Sharp corners on structural / editorial elements (dividers, hero blocks,
// tab underlines, progress bars). Soft radii on interactive containers
// (buttons, inputs, cards, badges).
// All components follow the Mediterranean blue palette.

// MARK: - BPButton
struct BPButton: View {
    enum Style { case primary, secondary, ghost, destructive }

    let title: String
    let style: Style
    let isLoading: Bool
    let action: () -> Void

    init(_ title: String, style: Style = .primary, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: foregroundColor))
                        .scaleEffect(0.85)
                }
                Text(title)
                    .font(.bpButton)
                    .foregroundColor(foregroundColor)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
        }
        .disabled(isLoading)
        .opacity(isLoading ? 0.7 : 1.0)
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:     return .bpCobalt
        case .secondary:   return .bpLimestone
        case .ghost:       return .clear
        case .destructive: return .bpError
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary:     return .white
        case .secondary:   return .bpInk
        case .ghost:       return .bpCobalt
        case .destructive: return .white
        }
    }

    private var borderColor: Color {
        switch style {
        case .ghost: return .bpCobalt
        default:     return .clear
        }
    }

    private var borderWidth: CGFloat {
        style == .ghost ? 1.5 : 0
    }
}

// MARK: - BPTextField
struct BPTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences

    @FocusState private var isFocused: Bool
    @State private var isPasswordVisible: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.bpLabel)
                .foregroundColor(.bpTextMuted)
                .tracking(1.0)

            HStack(spacing: 8) {
                Group {
                    if isSecure && !isPasswordVisible {
                        SecureField(placeholder, text: $text)
                            .textContentType(.password)
                    } else if isSecure {
                        TextField(placeholder, text: $text)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .textContentType(.password)
                    } else {
                        TextField(placeholder, text: $text)
                            .keyboardType(keyboardType)
                            .textInputAutocapitalization(autocapitalization)
                    }
                }
                .font(.bpBody)
                .foregroundColor(.bpInk)
                .focused($isFocused)

                if isSecure {
                    Button {
                        isPasswordVisible.toggle()
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                            .foregroundColor(.bpTextMuted)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isFocused ? Color.bpCobalt : Color.bpBorder, lineWidth: isFocused ? 1.5 : 1)
            )
        }
    }
}

// MARK: - BPCard
// Soft 12pt-rounded surface
struct BPCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.bpBorder, lineWidth: 1)
            )
    }
}

// MARK: - BPDivider
struct BPDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.bpBorder)
            .frame(height: 1)
    }
}

// MARK: - BPBadge
struct BPBadge: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color = .bpSaffron) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.bpLabel)
            .tracking(0.8)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color, lineWidth: 1)
            )
    }
}

// MARK: - BPSectionHeader
// Magazine-style section label with a rule
struct BPSectionHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title.uppercased())
                .font(.bpLabel)
                .foregroundColor(.bpTextMuted)
                .tracking(1.5)

            Rectangle()
                .fill(Color.bpBorder)
                .frame(height: 1)
        }
    }
}

// MARK: - BPEmptyState
struct BPEmptyState: View {
    let icon: String        // SF Symbol name
    let title: String
    let message: String
    var actionTitle: String? = nil
    var isLoading = false
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.bpStone)

            VStack(spacing: 8) {
                ItalicLastWord(
                    text: title,
                    font: .bpHeadline,
                    baseColor: .bpInk
                )
                .multilineTextAlignment(.center)

                Text(message)
                    .font(.bpCallout)
                    .foregroundColor(.bpTextSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            if let actionTitle, let action {
                BPButton(
                    actionTitle,
                    style: .primary,
                    isLoading: isLoading,
                    action: action
                )
                    .frame(width: 200)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - BPDestinationEyebrow
// Saffron uppercase destination label used on every editorial card / hero.
struct BPDestinationEyebrow: View {
    let destinations: [TripDestination]
    let country: String?
    let city: String?

    private var text: String {
        if !destinations.isEmpty {
            let grouped = Dictionary(grouping: destinations, by: { $0.country })
            return grouped.map { country, dests in
                let cities = dests.map { $0.city }.joined(separator: ", ")
                return "\(country): \(cities)"
            }.joined(separator: " · ")
        }
        if let c = city, let co = country {
            return "\(co): \(c)"
        }
        return country ?? city ?? ""
    }

    var body: some View {
        if !text.isEmpty {
            Text(text.uppercased())
                .font(BPFont.inter(size: 9, weight: .semibold))
                .foregroundColor(.bpSaffron)
                .tracking(1.4)
                .lineLimit(1)
        }
    }
}

// MARK: - Toast

struct BPToast: Equatable {
    let message: String
    let id = UUID()
}

struct BPToastView: View {
    let message: String

    var body: some View {
        Text(message.uppercased())
            .font(BPFont.inter(size: 11, weight: .medium))
            .tracking(0.8)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.bpPrimaryDeep)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}

struct BPToastModifier: ViewModifier {
    @Binding var toast: BPToast?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast {
                    BPToastView(message: toast.message)
                        .padding(.top, 60)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    self.toast = nil
                                }
                            }
                        }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: toast)
    }
}

extension View {
    func bpToast(_ toast: Binding<BPToast?>) -> some View {
        modifier(BPToastModifier(toast: toast))
    }
}

// MARK: - BPLoadingView
struct BPLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .bpCobalt))
                .scaleEffect(1.2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bpBackground)
    }
}

// MARK: - BPErrorView
struct BPErrorView: View {
    let message: String
    var retryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.bpError)

            Text(message)
                .font(.bpCallout)
                .foregroundColor(.bpTextSecondary)
                .multilineTextAlignment(.center)

            if let retryAction {
                BPButton("Try again", style: .secondary, action: retryAction)
                    .frame(width: 160)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - BPNavBar modifier
// Applies editorial navigation bar style
struct BPNavigationBarStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackground(Color.white, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

extension View {
    func bpNavigationStyle() -> some View {
        modifier(BPNavigationBarStyle())
    }
}

// MARK: - FollowButton
// Wraps BPButton.primary / .ghost with optimistic toggle + rollback on error.
struct FollowButton: View {
    let userId: String
    let initialIsFollowing: Bool
    var onChange: ((Bool) -> Void)? = nil

    @State private var isFollowing: Bool
    @State private var isLoading = false

    init(userId: String,
         initialIsFollowing: Bool,
         onChange: ((Bool) -> Void)? = nil) {
        self.userId = userId
        self.initialIsFollowing = initialIsFollowing
        self.onChange = onChange
        _isFollowing = State(initialValue: initialIsFollowing)
    }

    var body: some View {
        BPButton(
            isFollowing ? "Following" : "Follow",
            style: isFollowing ? .ghost : .primary,
            isLoading: isLoading
        ) {
            tap()
        }
    }

    private func tap() {
        guard !isLoading else { return }
        let previousState = isFollowing
        isFollowing.toggle()
        isLoading = true
        Task {
            do {
                let response: FollowResponse = try await APIClient.shared.request(
                    .toggleFollow(userId: userId),
                    method: .post
                )
                isFollowing = response.isFollowing
                onChange?(isFollowing)
            } catch {
                isFollowing = previousState
            }
            isLoading = false
        }
    }
}

// MARK: - SaveButton
// Icon-only bookmark toggle with optimistic UI + rollback on error.
struct SaveButton: View {
    let tripId: String
    let initialIsSaved: Bool
    var onChange: ((Bool) -> Void)? = nil

    @State private var isSaved: Bool
    @State private var isLoading = false

    init(tripId: String,
         initialIsSaved: Bool,
         onChange: ((Bool) -> Void)? = nil) {
        self.tripId = tripId
        self.initialIsSaved = initialIsSaved
        self.onChange = onChange
        _isSaved = State(initialValue: initialIsSaved)
    }

    var body: some View {
        Button(action: tap) {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(isSaved ? .bpSaffron : .bpInk)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .opacity(isLoading ? 0.7 : 1.0)
    }

    private func tap() {
        guard !isLoading else { return }
        let previousState = isSaved
        isSaved.toggle()
        isLoading = true
        Task {
            do {
                let response: SaveResponse = try await APIClient.shared.request(
                    .toggleSaveTrip(tripId: tripId),
                    method: .post
                )
                isSaved = response.isSaved
                onChange?(isSaved)
            } catch {
                isSaved = previousState
            }
            isLoading = false
        }
    }
}

// MARK: - PublicTripCardView
// Renders a PublicTripCard (the wire shape returned by /api/explore/trips,
// /api/users/{id}/trips, /api/users/me/saved). Cover photo with overlaid
// SaveButton, then title + destinations + author row.
struct PublicTripCardView: View {
    let trip: PublicTripCard
    var onSelect: (() -> Void)? = nil
    var onSavedChange: ((Bool) -> Void)? = nil

    private var destinationLine: String {
        trip.destinations
            .map { dest in
                if let city = dest.city, !city.isEmpty {
                    return "\(city), \(dest.country)"
                }
                return dest.country
            }
            .joined(separator: " · ")
    }

    private var coverURL: URL? {
        guard let s = trip.coverPhotoUrl else { return nil }
        return URL(string: s)
    }

    private var avatarURL: URL? {
        guard let s = trip.owner.avatarUrl else { return nil }
        return URL(string: s)
    }

    var body: some View {
        BPCard {
            VStack(alignment: .leading, spacing: 0) {
                // Cover photo with SaveButton overlay
                ZStack(alignment: .topTrailing) {
                    Color.clear
                        .aspectRatio(4.0/3.0, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .background(
                            Group {
                                if let url = coverURL {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .success(let img):
                                            img.resizable().scaledToFill()
                                        default:
                                            Color.bpLimestone
                                        }
                                    }
                                } else {
                                    Color.bpLimestone
                                }
                            }
                            .clipped()
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect?() }

                    SaveButton(
                        tripId: trip.id,
                        initialIsSaved: trip.isSaved,
                        onChange: onSavedChange
                    )
                    .padding(8)
                    .background(
                        Color.black.opacity(0.25)
                            .clipShape(Circle())
                            .frame(width: 44, height: 44)
                    )
                    .padding(8)
                }

                // Title + destinations
                VStack(alignment: .leading, spacing: 6) {
                    Text(trip.title)
                        .font(.bpHeadline)
                        .foregroundColor(.bpInk)
                        .lineLimit(2)

                    if !destinationLine.isEmpty {
                        Text(destinationLine)
                            .font(.bpCaption)
                            .foregroundColor(.bpTextMuted)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .contentShape(Rectangle())
                .onTapGesture { onSelect?() }

                // Author row — tappable, routes to the owner's PublicProfileView
                NavigationLink {
                    PublicProfileView(userId: trip.owner.id)
                } label: {
                    HStack(spacing: 8) {
                        AsyncImage(url: avatarURL) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            default:
                                Color.bpStone
                            }
                        }
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())

                        Text(trip.owner.fullName)
                            .font(.bpCallout)
                            .foregroundColor(.bpInk)
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Open \(trip.title), \(trip.destinationSummary)")
    }
}

// MARK: - Preview
#Preview {
    ScrollView {
        VStack(spacing: 24) {
            BPSectionHeader(title: "Buttons")

            BPButton("Start your journey") {}
            BPButton("Save draft", style: .secondary) {}
            BPButton("Follow", style: .ghost) {}
            BPButton("Delete trip", style: .destructive) {}
            BPButton("Loading...", style: .primary, isLoading: true) {}

            BPSectionHeader(title: "Text Fields")

            BPTextField(label: "Email", placeholder: "you@example.com", text: .constant(""))
            BPTextField(label: "Password", placeholder: "••••••••", text: .constant(""), isSecure: true)

            BPSectionHeader(title: "Badges")

            HStack {
                BPBadge("Editor's Pick")
                BPBadge("Draft", color: .bpTextMuted)
                BPBadge("Planning", color: .bpAzure)
            }

            BPSectionHeader(title: "Empty State")

            BPEmptyState(
                icon: "map",
                title: "No trips yet",
                message: "Start documenting your travels.",
                actionTitle: "Create your first trip",
                action: {}
            )
        }
        .padding(20)
    }
    .background(Color.bpBackground)
}

#Preview("Follow & Save") {
    ScrollView {
        VStack(spacing: 24) {
            BPSectionHeader(title: "Follow Button")

            FollowButton(
                userId: "preview-user-id",
                initialIsFollowing: false
            )

            FollowButton(
                userId: "preview-user-id",
                initialIsFollowing: true
            )

            BPSectionHeader(title: "Save Button")

            HStack(spacing: 24) {
                VStack(spacing: 6) {
                    SaveButton(
                        tripId: "preview-trip-id",
                        initialIsSaved: false
                    )
                    Text("Not saved")
                        .font(.bpCaption)
                        .foregroundColor(.bpTextMuted)
                }
                VStack(spacing: 6) {
                    SaveButton(
                        tripId: "preview-trip-id",
                        initialIsSaved: true
                    )
                    Text("Saved")
                        .font(.bpCaption)
                        .foregroundColor(.bpTextMuted)
                }
                Spacer()
            }
        }
        .padding(20)
    }
    .background(Color.bpBackground)
}
