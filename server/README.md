# Server (Entrance Resolution Service)

The server takes a destination address and returns the building's likely doors, ranked, each with a confidence score and the source it came from. It also returns path checks and side-of-street data. It knows about buildings, never about riders.

**Stack:** Python, FastAPI, Shapely, pyproj, SQLite. One container plus one worker process.

## Serves the app through one contract

The API is described in [`../docs/car-to-curb-plan.md#10-api-contract`](../docs/car-to-curb-plan.md#10-api-contract):

| Endpoint | Purpose |
|---|---|
| `POST /v1/resolve` | Resolve an address |
| `GET /v1/destinations/{id}` | Fetch a result |
| `POST /v1/destinations/{id}/feedback` | Door confirmation (v2) |
| `GET /v1/flags` | Kill switch and per-source switches |
| `GET /v1/health` | Liveness and versions |

Freeze the response shape in week 2 and publish a stub JSON file so the app team can build against it.

Rules:
- Store destinations only, never rider locations.
- API keys live in environment secrets; only `.env.example` is committed.
- The public Overpass server allows apps only about 100 queries a day, so cache everything and precompute the pilot area.

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
See the Server tasks (BE-1 to BE-10) in [`../docs/car-to-curb-plan.md#20-work-breakdown`](../docs/car-to-curb-plan.md#20-work-breakdown). The lookup ladder and OSM tag rules are in sections 8–9.
