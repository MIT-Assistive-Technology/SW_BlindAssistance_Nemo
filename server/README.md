# Server (Entrance Resolution Service)

The server takes a destination address and returns the building's likely doors, ranked, each with a confidence score and the source it came from. It also returns path checks and side-of-street data. It knows about buildings, never about riders.

**Stack:** Python, FastAPI, Shapely, pyproj, SQLite. One container plus one worker process.

## MVP: precomputed bundles first

For the April MVP the app uses **precomputed entrance bundles** for the pilot sites: static JSON in the same shape as [`../contract/resolve.example.json`](../contract/resolve.example.json), built by a Python script from an OSM extract. The live service below is a stretch goal.

| Endpoint (stretch) | Purpose |
|---|---|
| `POST /v1/resolve` | Resolve an address from the cache (≤ 3 s, no live Overpass/Nominatim calls); `status: "partial"` when weak |
| `GET /v1/health` | Liveness and data version |

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
  main.py          routes (returns the contract example until the ladder works)
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
