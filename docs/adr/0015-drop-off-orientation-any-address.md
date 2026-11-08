# ADR 0015: Drop-off orientation at any address

**State:** Proposed (2026-11-08). Needs team agreement before work starts.
**Changes:** ADR 0012 (precomputed pilot bundles instead of a live server) in part. Precomputed bundles stay as a cache and as test data; they stop being the only way to start a trip.

## Context

Nemo exists for the part of a trip that regular navigation apps skip. A rider is dropped off somewhere, often a parking lot or the wrong side of a building, and does not know where the building is, which side of it they face, or how to reach the entrance.

The current app can't do that yet:

- **Trips only start at the 19 pilot sites.** `PilotBundleClient` returns "not found" for every other address, and the server's `/v1/resolve` only matches pilot bundles.
- **Routes have a fixed start.** Each bundle carries one hand-placed route. Remaining distance is measured from the nearest route point and ignores how far the rider is from the route, so a rider standing in a lot can hear "The door should be close".
- **No road data stalls the walk.** With no street centerline, the session withholds direction until the side of street is known, and nothing can clear that.
- **OSM rarely has doors.** Around MIT and Kendall, 6.8% of 1,016 outlined buildings have a usable entrance (`docs/audit/pilot-entrance-coverage.md`). 13 of the 19 pilot bundles have a mapped door.

## Decision

1. **Drop-off orientation is the core feature.** When the rider gets out, Nemo works out where the building is, which side of it they are near and which way round the entrance is, and says so once. "Where am I" repeats it.
2. **Every findable address starts a trip.** The lookup returns a bundle at one of four knowledge levels: `door`, `building`, `point` or `none`. Missing data lowers the level; it never blocks the trip.
3. **Routes start where the rider actually is.** The phone plans the route after drop-off, from a walk network in the bundle, then Apple walking directions, then direction only.
4. **The server is used once, before the ride, and only receives the destination address.** The walk still works with no signal.
5. **Bundle v2** adds `knowledge` and `walk_network` and makes `building` and the path-check booleans nullable. The contract changes first, as always.

## Consequences

- A live server moves from "stretch" into scope (BE-12), with hosting, rate limits and log privacy.
- Point-level bundles made on the phone use Apple's geocoder, and walking directions send the rider's position to Apple. The privacy text should say so.
- With no road data, Nemo gives direction with a spoken warning that it doesn't know where the roads are.
- The work breakdown gains FE-15 to FE-20, BE-9 to BE-14, CV-12, CV-13, QA-9 to QA-11 and MAP-2 (plan section 20).
- If time runs short, cut BE-14, CV-13 and Apple walking routes first. Protect QA-9, FE-16, FE-17, FE-18 and FE-19.

## Open questions

- How far does server coverage reach first: Massachusetts only, with point level elsewhere?
