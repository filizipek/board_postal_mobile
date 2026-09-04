import SwiftUI
import Combine

// MARK: - AuthStore
// Global auth state. Injected as @EnvironmentObject throughout the app.
// Listens for force-logout notifications from APIClient.

@MainActor
final class AuthStore: ObservableObject {
    @Published var currentUser: AuthResponse? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let keychain = KeychainService.shared
    private let api = APIClient.shared

    var isAuthenticated: Bool { currentUser != nil }
    var isAdmin: Bool { false } // will come from JWT later

    init() {
        listenForForcedLogout()
        Task { await restoreSession() }
    }

    // MARK: - Session restore on launch
    private func restoreSession() async {
        guard keychain.isLoggedIn,
              let userId = keychain.userId,
              let email = keychain.email,
              let access = keychain.accessToken,
              let refresh = keychain.refreshToken
        else { return }

        // Restore currentUser optimistically so UI shows immediately
        currentUser = AuthResponse(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: nil,
            userId: userId,
            email: email
        )

        // Validate token silently — if this fails APIClient will
        // auto-refresh or trigger logout, both handled automatically
        // No action needed here — the middleware handles it
    }

    // MARK: - Login
    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let body = LoginRequest(email: email, password: password)
            let response: AuthResponse = try await api.request(.login, method: .post, body: body, requiresAuth: false)
            keychain.saveTokens(
                access: response.accessToken,
                refresh: response.refreshToken,
                userId: response.userId,
                email: response.email
            )
            currentUser = response
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Register
    func register(email: String, password: String, fullName: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let body = RegisterRequest(email: email, password: password, fullName: fullName)
            let response: AuthResponse = try await api.request(.register, method: .post, body: body, requiresAuth: false)
            keychain.saveTokens(
                access: response.accessToken,
                refresh: response.refreshToken,
                userId: response.userId,
                email: response.email
            )
            currentUser = response
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Avatar update (local state)
    // Caller performs the network round-trip (PUT /api/users/me); this
    // mirrors the new avatarId into currentUser so the rest of the app
    // observes the change without re-fetching. AuthResponse.avatarId is
    // a `var`, so mutating it through the optional-chained @Published
    // currentUser triggers the republish that observers (Profile hero,
    // PublicProfileView's own-profile check, etc.) listen on.
    func updateAvatarId(_ newAvatarId: String?) {
        currentUser?.avatarId = newAvatarId
    }

    // MARK: - Logout
    func logout() async {
        // Best-effort revoke on backend
        struct RevokeRequest: Encodable {
            let refreshToken: String
        }
        if let token = keychain.refreshToken {
            try? await api.requestVoid(
                .revoke,
                method: .post,
                body: RevokeRequest(refreshToken: token)
            )
        }
        keychain.clearAll()
        currentUser = nil
    }

    // MARK: - Force logout listener (401 from APIClient)
    private func listenForForcedLogout() {
        NotificationCenter.default.addObserver(
            forName: .bpForceLogout,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.currentUser = nil
            self?.errorMessage = nil
        }
    }
}
