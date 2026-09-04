import SwiftUI

// MARK: - AvatarPickerView

/// Curated avatar picker (Phase B4). Presentation-only — the parent
/// injects `onSave` (which handles the backend round-trip) and
/// `onDismiss` (which dismisses the sheet). Tapping a tile sets local
/// selection state; nothing persists until the user taps Save.
///
/// The view dynamically iterates `AvatarCatalog.all` — the six entries
/// live in one place (Phase B3) and this picker never hardcodes them.
struct AvatarPickerView: View {
    let initialSelection: String?
    let onSave: @MainActor (String) async throws -> Void
    let onDismiss: () -> Void

    @State private var selection: String?
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    init(
        initialSelection: String?,
        onSave: @MainActor @escaping (String) async throws -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.initialSelection = initialSelection
        self.onSave = onSave
        self.onDismiss = onDismiss
        _selection = State(initialValue: initialSelection)
    }

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    /// Save is enabled only when the user has actually changed their
    /// pick AND we have a non-nil selection to send AND we aren't
    /// already mid-save.
    private var canSave: Bool {
        selection != initialSelection
            && selection != nil
            && !isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Magazine header — Playfair title + Inter subtitle
                    Text("Choose your traveller")
                        .font(BPFont.playfair(size: 28, weight: .bold))
                        .foregroundColor(.bpInk)
                        .padding(.top, 16)

                    Text("Your avatar shapes how board_postal sees you — and the gradient on your profile.")
                        .font(.bpBody)
                        .foregroundColor(.bpTextMuted)

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(AvatarCatalog.all) { avatar in
                            tile(for: avatar)
                                .onTapGesture {
                                    guard !isSaving else { return }
                                    selection = avatar.id
                                }
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }

            saveBar
        }
        .background(Color.bpLimestone)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { onDismiss() }
                    .foregroundColor(.bpCobalt)
                    .disabled(isSaving)
            }
        }
        .alert(
            "Couldn't save avatar",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ),
            presenting: errorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
    }

    // MARK: - Tile

    @ViewBuilder
    private func tile(for avatar: Avatar) -> some View {
        let isSelected = selection == avatar.id

        VStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                // Sharp-cornered gradient block — the gradient itself
                // doubles as a live preview of the profile hero a user
                // would see if they pick this avatar.
                ZStack {
                    avatar.gradient

                    Image(avatar.imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 108, height: 108)
                        .clipShape(Circle())
                }
                .frame(height: 160)
                .overlay(
                    Rectangle()
                        .stroke(
                            isSelected ? Color.bpCobalt : Color.bpStone,
                            lineWidth: isSelected ? 3 : 1
                        )
                )

                // Selected indicator: small sharp-cornered saffron
                // square with a checkmark, top-trailing.
                if isSelected {
                    ZStack {
                        Rectangle()
                            .fill(Color.bpSaffron)
                            .frame(width: 28, height: 28)
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.bpInk)
                    }
                    .padding(8)
                }
            }

            Text(avatar.displayName)
                .font(.bpBody)
                .foregroundColor(.bpInk)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Save bar

    private var saveBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.bpStone)
                .frame(height: 1)

            Button {
                Task { await performSave() }
            } label: {
                HStack(spacing: 10) {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(
                                CircularProgressViewStyle(tint: .bpLimestone)
                            )
                            .scaleEffect(0.85)
                    }
                    Text(isSaving ? "Saving…" : "Save")
                        .font(BPFont.inter(size: 16, weight: .semibold))
                        .foregroundColor(.bpLimestone)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(canSave ? Color.bpCobalt : Color.bpStone)
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.bpLimestone)
    }

    @MainActor
    private func performSave() async {
        guard let id = selection, canSave else { return }
        isSaving = true
        do {
            try await onSave(id)
            // Success — hand control back to the parent, which closes
            // the sheet. onDismiss is the parent's single "we're done"
            // hook (covers both cancel-button and save-success paths).
            onDismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AvatarPickerView(
            initialSelection: "avatar_photographer",
            onSave: { _ in
                // Stub network: pretend we PUT and round-tripped.
                try await Task.sleep(nanoseconds: 600_000_000)
            },
            onDismiss: {
                // In preview the parent doesn't exist — no-op.
            }
        )
    }
}
