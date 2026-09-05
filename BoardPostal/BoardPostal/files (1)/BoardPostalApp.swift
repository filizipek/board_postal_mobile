import SwiftUI

// MARK: - BoardPostalApp

@main
struct BoardPostalApp: App {
    @StateObject private var authStore = AuthStore()

    init() {
        let isFirstLaunch = !UserDefaults.standard.bool(forKey: "bp_launched_before")
        if isFirstLaunch {
            KeychainService.shared.clearAll()
            UserDefaults.standard.set(true, forKey: "bp_launched_before")
        }

        // Verify that Inter / Playfair Display variable fonts loaded.
        for family in UIFont.familyNames.sorted() {
            for font in UIFont.fontNames(forFamilyName: family) {
                if font.contains("Inter") || font.contains("Playfair") {
                    print("✓ Font loaded: \(font)")
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authStore)
                .preferredColorScheme(.light)
        }
    }
}

// MARK: - RootView
// Gates the app: auth flow or main tab experience.

struct RootView: View {
    @EnvironmentObject var authStore: AuthStore

    var body: some View {
        Group {
#if DEBUG
            if let scenario = TripsVisualVerificationScenario.current {
                NavigationStack {
                    TripsVisualVerificationView(scenario: scenario)
                }
            } else {
                authenticatedContent
            }
#else
            authenticatedContent
#endif
        }
        .animation(.easeInOut(duration: 0.25), value: authStore.isAuthenticated)
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        if authStore.isAuthenticated {
            RootTabView()
                .transition(.opacity)
        } else {
            AuthFlowView()
                .transition(.opacity)
        }
    }
}

// MARK: - RootTabView
// 4-tab structure with a floating capture FAB centered above the tab bar:
// Trips / Explore / Map / Profile

struct RootTabView: View {
    @State private var selectedTab: Tab = .trips

    enum Tab: Int {
        case trips, explore, map, profile
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TripsListView()
            }
            .tabItem {
                Label("Trips", systemImage: selectedTab == .trips ? "suitcase.fill" : "suitcase")
            }
            .tag(Tab.trips)

            NavigationStack {
                ExploreView()
            }
            .tabItem {
                Label("Explore", systemImage: selectedTab == .explore ? "safari.fill" : "safari")
            }
            .tag(Tab.explore)

            NavigationStack {
                WorldMapView()
            }
            .tabItem {
                Label("Map", systemImage: selectedTab == .map ? "map.fill" : "map")
            }
            .tag(Tab.map)

            NavigationStack {
                ProfileView()
            }
            .tabItem {
                Label("Profile", systemImage: selectedTab == .profile ? "person.fill" : "person")
            }
            .tag(Tab.profile)
        }
        .tint(.bpCobalt)
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .white
            appearance.shadowColor = UIColor(Color.gray.opacity(0.2))

            // Remove selection indicator pill
            appearance.selectionIndicatorTintColor = .clear

            // Icon colors
            let cobalt = UIColor(Color(hex: "#1B4FDB"))
            let muted = UIColor(Color(hex: "#8E9AAB"))

            appearance.stackedLayoutAppearance.selected.iconColor = cobalt
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                .foregroundColor: cobalt,
                .font: UIFont.systemFont(ofSize: 10, weight: .medium)
            ]
            appearance.stackedLayoutAppearance.normal.iconColor = muted
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                .foregroundColor: muted,
                .font: UIFont.systemFont(ofSize: 10, weight: .regular)
            ]

            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
            UITabBar.appearance().tintColor = cobalt

            // Suppress iOS 26 pill indicator
            UITabBar.appearance().isSpringLoaded = false
        }
    }
}

// MARK: - AuthFlowView
// Lands on login, can navigate to register.

struct AuthFlowView: View {
    @State private var showRegister = false

    var body: some View {
        NavigationStack {
            LoginView(showRegister: $showRegister)
                .navigationDestination(isPresented: $showRegister) {
                    RegisterView()
                }
        }
    }
}

// MARK: - Feature views (implemented in dedicated files)
// ExploreView — implemented in Explore.swift
// WorldMapView — implemented in WorldMap.swift
// ProfileView — implemented in Profile.swift
// QuickCaptureView — implemented in QuickCapture.swift
