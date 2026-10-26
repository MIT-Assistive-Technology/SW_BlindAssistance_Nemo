# Server (Entrance Resolution Service)

The server takes a destination address and returns the building's likely doors, ranked, each with a confidence score and the source it came from. It also returns path checks and side-of-street data. It knows about buildings, never about riders.

**Stack:** Python, FastAPI, Shapely, pyproj, SQLite. One container plus one worker process.

## MVP: precomputed bundles first

For the April MVP the app uses **precomputed entrance bundles** for the pilot sites: JSON in the same shape as [`../contract/resolve.example.json`](../contract/resolve.example.json), built by `scripts/build_bundles.py` into `bundles/<id>.json`. The API serves those files; it never runs the ladder or calls Overpass per request.

**MVP flow:** at setup the app downloads `GET /v1/bundles` and every bundle in it, and caches them, so guidance works with no signal at the curb. `POST /v1/resolve` is only for a destination the phone hasn't cached.

| Endpoint | Purpose |
|---|---|
| `GET /v1/bundles` | Manifest: `[{id, address, osm_id, data_version, sha256, url}]`, one per pilot bundle |
| `GET /v1/bundles/{id}` | One bundle. `ETag` is its sha256; send `If-None-Match` to get `304` when unchanged |
| `POST /v1/resolve` | Address or lat/lon → the pilot bundle for that building (≤ 3 s). Not in the pilot → `404 NOT_FOUND` |
| `GET /v1/health` | Liveness, bundle count and data version |

Settings: `BUNDLES_DIR` (default `bundles/`), `PILOT_SITES` (default `pilot_sites.json`, used for manifest addresses). Invalid bundle files are logged and skipped at startup. `DEV_EXAMPLE=1` makes `/v1/resolve` return the contract example, but only while `BUNDLES_DIR` is empty.

Errors always use `{"error": {"code", "message", "request_id"}}`.

Rules:
- Store buildings and an address hash only. Never store rider locations or an install key next to a destination.
- API keys live in environment secrets; only `.env.example` is committed.
- Public Overpass allows about 100 queries and 10 MB a day per deployment, so preload the pilot area from the Geofabrik Massachusetts extract.
- Geocode with structured Nominatim queries (`layer=address`). Free-form "77 Massachusetts Ave, Cambridge, MA" matches a bus stop.
- If the live service runs: one Fly.io machine with a volume, SQLite in WAL mode. Render's free tier has no disk.

## Layout

```
pyproject.toml     dependencies (FastAPI, Shapely, pyproj, httpx) and pytest/ruff config
.env.example       settings; copy to .env
app/
  main.py          routes and the error envelope
  bundle_store.py  loads bundles/*.json, indexes them, matches a geocoded point to a bundle
  models.py        Pydantic mirror of ../contract/resolve.example.json
  resolver.py      the lookup ladder, one function per step
  scoring.py       door scoring rules
  geo.py           side of street, photo rays, wall intersection
tests/             pytest; skipped tests are TODOs with expected values
Instructions.md    step-by-step getting started
```

## Start here

Follow [`Instructions.md`](Instructions.md). 
See the Server tasks in [`../docs/car-to-curb-plan.md#20-work-breakdown`](../docs/car-to-curb-plan.md#20-work-breakdown). The lookup ladder and OSM tag rules are in sections 8–9.
