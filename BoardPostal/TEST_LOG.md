# board_postal — TESTING_LOG.md
## Session — 2026-06-01 → 2026-06-02 · Build 1.0(1) — TestFlight

| ID | Severity | Title | Stack | Status |
|----|----------|-------|-------|--------|
| BP-002 | P1 | Calendar grid renders blank in New Trip date picker | iOS | Closed |
| BP-003 | Feature | Confirm password field on signup | iOS | Open |
| BP-004 | Feature | Allow setting cover/background during trip creation (upload or Unsplash) | Cross-platform | Closed |
| BP-005 | Feature | Profile imagery should use selectable avatars, not latest trip photo | iOS | Open |
| BP-006 | P1 | Explore search returns no results for any query | .NET API | Open |
| BP-007 | P2 | Render Unsplash attribution caption on detail views | Cross-platform | Open (Deferred v1.x) |
| BP-008 | P3 | Inconsistent card treatment between Profile tabs (full-bleed vs boxed) | iOS | Open |
| BP-009 | P2 | Entry-attached photo lands in trip gallery, not linked to the entry | iOS | Open |
| BP-010 | P1 | Adding an itinerary item fails (blank sheet + validation error) | Cross-platform | Open |
| BP-011 | P1 | Draft trip cards overlap on Trips list | iOS | Open |

---

### BP-002 — Calendar grid renders blank in New Trip date picker
**Severity:** P1 — Critical
**Discovered:** 2026-06-01 · **Fixed:** 2026-06-01
**Build:** 1.0(1)
**Device:** iPhone, iOS 18.x
**Screen:** Create Trip → Dates (optional)
**Stack:** iOS
**Frequency:** Always
**Steps to reproduce**
1. Trips → + → New trip
2. Enter a trip name, select "Planning ahead"
3. Tap the From/To dates section to open the calendar
**Expected:** Calendar shows weekday headers and legible, selectable date cells.
**Actual:** Calendar renders nearly blank — headers and most dates invisible; only isolated dates appear. Selection works blind.
**Root cause:** `.graphical` DatePicker uses semantic colors (.primary/.secondary) that invert in dark mode, painted on a hardcoded white container → invisible text. Only today/selected indicators showed (they use `.tint`).
**Fix:** Local — `.accentColor(.bpCobalt)`, `.foregroundStyle(Color.bpInk)`, `.environment(\.colorScheme, .light)` on the graphical DatePicker in CreateTrip.swift. Global — `.preferredColorScheme(.light)` on root view in BoardPostalApp.swift to clamp to light rendering until a dark-mode palette exists.
**Status:** Closed
**Owner:** Claude Agent (Xcode)

### BP-003 — Confirm password field on signup
**Type:** Feature request
**Discovered:** 2026-06-01
**Build:** 1.0(1)
**Device:** iPhone, iOS 18.x
**Screen:** Auth → Create account
**Stack:** iOS
**Frequency:** N/A
**Steps to reproduce**
1. Open Create account screen
2. Observe single password field, no confirmation
**Expected:** —
**Actual:** One password field; no confirm-password to catch typos.
**Notes / hypothesis:** Open product question from founder.
**Status:** Open
**Owner:** Claude Agent (Xcode)

### BP-004 — Allow setting cover/background during trip creation (upload or Unsplash)
**Type:** Feature request
**Discovered:** 2026-06-01 · **Fixed:** 2026-06-02
**Build:** 1.0(1)
**Screen:** Create Trip → (wizard) → Cover step
**Stack:** Cross-platform (iOS + .NET API + DB)
**Verified paths:** Library upload (Porto), Unsplash pre-seeded search (Madrid), Skip → gradient fallback (Lisbon)
**What shipped:**
- Backend: schema migration AddCoverPhotoAttribution + DTO additions
- iOS models: attribution fields on Trip/Update/Public types
- Shared MediaUploader (replaced 3 inline upload duplicates)
- Standalone reusable UnsplashPickerView with initialQuery seeding
- New Cover step in Create Trip wizard with both source options
- Cover URL + attribution persisted via existing PUT-after-POST flow
- Cover renders on trip detail hero blocks
**Deferred to v1.x:** caption rendering "Photo by X on Unsplash" (→ BP-007); cover upload in Edit Trip (currently Unsplash-only); Render DB migration (pending TestFlight rollout)
**Status:** Closed
**Owner:** Cross-stack — Claude Code (backend) + Claude Agent (iOS)

### BP-005 — Profile imagery should use selectable avatars, not latest trip photo
**Type:** Feature request
**Discovered:** 2026-06-01
**Build:** 1.0(1)
**Device:** iPhone, iOS 18.x
**Screen:** Profile (header)
**Stack:** iOS
**Frequency:** Always
**Steps to reproduce**
1. Open Profile
2. Observe header background defaults to the latest trip/entry photo
**Expected:** User-controlled identity — selectable avatars (Disney+-style picker, to be designed).
**Actual:** Profile header auto-pulls the most recent trip/entry photo.
**Notes / hypothesis:** Founder plans a curated avatar set. Open Q: header background vs avatar circle — awaiting confirmation.
**Status:** Open
**Owner:** Claude Agent (Xcode)

### BP-006 — Explore search returns no results for any query
**Severity:** P1 — Critical
**Discovered:** 2026-06-01
**Build:** 1.0(1)
**Device:** iPhone, iOS 18.x
**Screen:** Explore → Search
**Stack:** .NET API
**Frequency:** Always
**Steps to reproduce**
1. Explore → tap search bar
2. Type an exact trip title or destination from the feed (e.g. "Agalarla Bosna", "Sarajevo", "madrid")
3. Submit / observe results
**Expected:** Matching trips/destinations returned — at minimum exact matches visible in the feed.
**Actual:** "No results" for every query, including exact matches currently shown on Explore.
**Notes / hypothesis:** Records exist in feed but don't surface, pointing to the search endpoint returning empty/mismatched (wrong field, case/diacritic handling, or query not applied). Founder also wants partial + diacritic-aware (Turkish) matching.
**Status:** Open
**Owner:** Claude Code (.NET)

### BP-007 — Render Unsplash attribution caption on detail views
**Severity:** P2 — Major (compliance / attribution)
**Discovered:** 2026-06-01
**Build:** 1.0(1)
**Device:** iPhone, iOS 18.x
**Screen:** Trip Detail (own + public) hero block
**Stack:** Cross-platform (iOS + web)
**Frequency:** Always
**Steps to reproduce**
1. Set an Unsplash cover (attribution now persists per BP-004)
2. View the trip detail hero block
**Expected:** Visible "Photo by [name] on Unsplash" caption, hotlinked to the photographer's profile and to Unsplash, with UTM params per guidelines.
**Actual:** Attribution is stored but not displayed anywhere.
**Notes / hypothesis:** Save-side defect resolved in BP-004; this is the display half. Deferred to v1.x but required for Unsplash API compliance before public launch.
**Status:** Open (Deferred v1.x)
**Owner:** Cross-stack — Claude Agent (iOS) + Claude Code (web)

### BP-008 — Inconsistent card treatment between Profile tabs (full-bleed vs boxed)
**Severity:** P3 — Minor
**Discovered:** 2026-06-01
**Build:** 1.0(1)
**Device:** iPhone, iOS 18.x
**Screen:** Profile → Trips / Saved tabs
**Stack:** iOS
**Frequency:** Always
**Steps to reproduce**
1. Profile → Trips tab — cards render full-bleed
2. Profile → Saved tab — items render in contained boxes
3. Compare
**Expected:** Consistent card treatment across Profile tabs.
**Actual:** Trips full-bleed; Saved boxed. Founder prefers boxed.
**Notes / hypothesis:** Likely standardize on boxed. Pending: scope (Profile-only vs app-wide incl. Explore) and corner treatment (must stay sharp per design system).
**Status:** Open
**Owner:** Claude Agent (Xcode)

### BP-009 — Entry-attached photo lands in trip gallery, not linked to the entry
**Severity:** P2 — Major
**Discovered:** 2026-06-01
**Build:** 1.0(1)
**Device:** iPhone, iOS 18.x
**Screen:** Trip Detail → Journal → Entry composer
**Stack:** iOS
**Frequency:** Always
**Steps to reproduce**
1. Trip Detail → Journal → Write/edit entry → attach a photo in the composer
2. Save the entry
3. Open the entry and check the Photos tab
**Expected:** Photo linked to that specific entry (via `trip_entry_media`) and shown with it; also surfaced in the trip gallery.
**Actual:** Photo appears only in the trip-wide gallery; no entry association.
**Notes / hypothesis:** Backend `trip_entry_media` join table exists, but the iOS save path writes only the trip-level media link, not the entry↔media relation.
**Status:** Open
**Owner:** Claude Agent (Xcode)

### BP-010 — Adding an itinerary item fails (blank sheet + validation error)
**Severity:** P1 — Critical
**Discovered:** 2026-06-01
**Build:** 1.0(1) — TestFlight
**Device:** iPhone, iOS 18.x
**Screen:** Trip Detail → Itinerary → Add item
**Stack:** Cross-platform (iOS + .NET API)
**Frequency:** Always
**Steps to reproduce**
1. Open a trip → Itinerary tab → expand Day 1
2. Tap "Add item"
3. A blank/black sheet appears
4. Attempt to add / dismiss → "ONE OR MORE VALIDATION ERRORS OCCURRED." toast on Day 1
**Expected:** Add-item form renders; item saves to the day.
**Actual:** Add-item sheet renders blank/black; the add fails with the raw .NET validation message.
**Notes / hypothesis:** Blank sheet is iOS (form not rendering). The toast is the default ASP.NET ModelState error shown raw — backend rejecting the create-itinerary-item request, likely a missing/wrong-shaped field from the client. iOS should also surface a friendly error instead of the raw message.
**Status:** Open
**Owner:** Cross-stack — Claude Agent (iOS) + Claude Code (.NET)

### BP-011 — Draft trip cards overlap on Trips list
**Severity:** P1 — Critical
**Discovered:** 2026-06-01
**Build:** 1.0(1) — TestFlight
**Device:** iPhone, iOS 18.x
**Screen:** Trips → Drafts
**Stack:** iOS
**Frequency:** Always
**Steps to reproduce**
1. Have 2+ draft trips
2. Open the Trips tab
3. Observe the İzmir card clipped and the Ordu card overlapping it (persists)
**Expected:** Cards stack with proper spacing, no overlap.
**Actual:** Draft trip cards consistently overlap/clip each other.
**Notes / hypothesis:** Likely SwiftUI layout — fixed card heights or negative/insufficient spacing in the list/stack causing overlap.
**Status:** Open
**Owner:** Claude Agent (Xcode)
