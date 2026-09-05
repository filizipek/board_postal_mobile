# Explore API fixtures

`explore-page-one.json` wraps the canonical backend fixture from
`board_postal/docs/testing/fixtures/api/public-trip-card.json` in the actual
`GET /api/explore/trips` envelope. The remaining files are deterministic local
variants for pagination, nullability, empty results, and malformed responses.

These are copies in the iOS test bundle. The Xcode project has no path or build
dependency on the backend repository.
