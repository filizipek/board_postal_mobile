# BoardPostal for iOS

**A native travel journal and trip planner built with SwiftUI.** BoardPostal brings trip planning, saved places, photos, and travel stories into one iPhone app. This repository contains the **iOS client**; it communicates with a separate API.

## What you can do

- **Plan a trip:** create trips with destinations and covers, organize days and itinerary items, and manage places.
- **Capture memories:** add journal entries and photos, including a quick capture flow with location support.
- **See your travels:** browse trips on a map and export a trip overview, itinerary, journal, and places as a PDF.
- **Explore and connect:** discover public trips, view profiles, follow users, save trips, and invite collaborators.
- **Manage access:** sign in, edit your profile, and control trip visibility.

## iOS engineering highlights

| Area | Implementation |
| --- | --- |
| UI | SwiftUI screens, reusable components, custom typography, and loading/empty/error states |
| Networking | `URLSession` API client with `Codable` models, JWT attachment, token refresh, and request retry |
| Authentication | Access and refresh tokens stored in the iOS Keychain |
| Native features | MapKit, Core Location, camera/photo selection, and on-device PDF generation |
| Verification | XCTest coverage for API contracts, view models, itinerary flows, navigation, and regressions |

## Project structure

```text
BoardPostal/
├── BoardPostal.xcodeproj/       Xcode project and shared scheme
├── BoardPostal/                 SwiftUI app, models, API client, assets, configuration
└── BoardPostalTests/            Unit and contract tests with JSON fixtures
```

The app starts in `BoardPostalApp.swift` and presents four primary tabs: **Trips, Explore, Map, and Profile**. Feature views and view models live in the app source directory; `APIClient.swift` and `Endpoints.swift` handle communication with the backend.

## Run locally

1. Open `BoardPostal/BoardPostal.xcodeproj` in Xcode on a Mac.
2. Set `API_BASE_URL` in `BoardPostal/BoardPostal/Config/Debug.xcconfig` to a reachable BoardPostal API. The app requires the separate backend for account and trip data.
3. Select the **BoardPostal** scheme and an iPhone simulator or device, then run.
4. Run the **BoardPostal** test action in Xcode to execute the iOS test target.

The app target is configured for **iOS 17.6+**. A local build requires Xcode with an SDK and simulator compatible with the project settings. Some flows need an account and access to the configured API.

## About this repository

This repository showcases the mobile side of BoardPostal: a native iOS experience, its integration with the API, and the tests around key user flows. The backend and web app are separate from this repository.
