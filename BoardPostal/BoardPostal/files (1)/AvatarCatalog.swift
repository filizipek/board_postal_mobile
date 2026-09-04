import SwiftUI

// MARK: - Avatar

/// One entry in the curated avatar set. Stable string `id` is what
/// persists to the backend's User.AvatarId column; the rest is
/// presentation.
struct Avatar: Identifiable, Hashable {
    let id: String              // e.g. "avatar_photographer"
    let displayName: String     // e.g. "Photographer"
    let imageName: String       // e.g. "Avatar_Photographer" (asset catalog name)
    let gradientStart: Color    // brand palette color
    let gradientEnd: Color      // brand palette color

    /// Gradient driven by this avatar — used for profile hero
    /// background, top-leading to bottom-trailing direction.
    var gradient: LinearGradient {
        LinearGradient(
            colors: [gradientStart, gradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - AvatarCatalog

/// The curated set of 6 avatars. Source of truth for IDs, display
/// names, asset names, and gradient mappings.
enum AvatarCatalog {

    static let all: [Avatar] = [
        Avatar(
            id: "avatar_photographer",
            displayName: "Photographer",
            imageName: "Avatar_Photographer",
            gradientStart: .bpSaffron,
            gradientEnd: .bpInk
        ),
        Avatar(
            id: "avatar_foodie",
            displayName: "Foodie",
            imageName: "Avatar_Foodie",
            gradientStart: .bpAzure,
            gradientEnd: .bpSaffron
        ),
        Avatar(
            id: "avatar_collectioner",
            displayName: "Collectioner",
            imageName: "Avatar_Collectioner",
            gradientStart: .bpSaffron,
            gradientEnd: .bpCobalt
        ),
        Avatar(
            id: "avatar_follower",
            displayName: "Follower",
            imageName: "Avatar_Follower",
            gradientStart: .bpCobalt,
            gradientEnd: .bpAzure
        ),
        Avatar(
            id: "avatar_wanderer",
            displayName: "Wanderer",
            imageName: "Avatar_Wanderer",
            gradientStart: .bpCobalt,
            gradientEnd: .bpInk
        ),
        Avatar(
            id: "avatar_local",
            displayName: "Local",
            imageName: "Avatar_Local",
            gradientStart: .bpCobalt,
            gradientEnd: .bpSaffron
        )
    ]

    /// Lookup an avatar by its stable ID. Returns nil if the ID is
    /// unknown (e.g., the user has an avatarId that points to an
    /// avatar that was removed from the set — defensive default).
    static func avatar(for id: String?) -> Avatar? {
        guard let id = id else { return nil }
        return all.first { $0.id == id }
    }

    /// Default gradient when the user has not selected an avatar yet.
    /// Uses the existing user-ID-driven gradient from Phase A
    /// (Profile.swift Phase A used LinearGradient.bpCoverGradient(for:))
    /// — this static helper just delegates to that for consistency.
    ///
    /// Callers should pass the user's stable ID (e.g.,
    /// authStore.currentUser?.userId) when no avatar is selected.
    static func defaultGradient(for userId: String) -> LinearGradient {
        LinearGradient.bpCoverGradient(for: userId)
    }
}
