# Server: Getting Started

A step-by-step path from this skeleton to a working entrance lookup. Each step names the file and the task ID from [`docs/car-to-curb-plan.md`](../docs/car-to-curb-plan.md#20-work-breakdown). Pick an unchecked step, open a branch (`yourname/BE-4-scoring`), and send a small PR.

## 0. Setup

```bash
cd server
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -e ".[dev]"
cp .env.example .env               # fill in; never commit .env
pytest                             # 7 pass, 10 skipped (the skipped ones are your TODOs)
uvicorn app.main:app --reload      # http://127.0.0.1:8000/docs
```

`POST /v1/resolve` already returns `contract/resolve.example.json`, so the app team can build against the real endpoint shape while you fill in the lookup.

## How the code is laid out

| File | What it is | Task |
|---|---|---|
| `app/models.py` | Pydantic mirror of the API contract | — (change the contract first) |
| `app/main.py` | FastAPI routes | BE-1, BE-6, BE-8 |
| `app/resolver.py` | The lookup ladder, one function per step | BE-2 to BE-6 |
| `app/scoring.py` | Door scoring rules and tables | BE-4 |
| `app/geo.py` | Side of street, photo rays, wall intersection | BE-5, CV-5 |
| `tests/` | pytest; skipped tests hold the expected values for each TODO | — |

## 1. Scoring (BE-4)

File: `app/scoring.py`

- [ ] Implement `score_door` and `combine` following the steps in their docstrings.
- [ ] Remove the `@todo` skip marker in `tests/test_scoring.py` and make the tests pass.

## 2. Geometry (BE-5, CV-5)

File: `app/geo.py`

- [ ] `side_of`: the sign of the cross product.
- [ ] `photo_ray_bearing` and `ray_hits_outline` with shapely.
- [ ] Unskip `tests/test_geo.py`. Its expected values come from the plan's worked examples.

## 3. Geocoder (BE-2)

File: `app/resolver.py` → `geocode`

- [ ] Call Nominatim with httpx, at most 1 request/s, with `USER_AGENT` from `.env`.
- [ ] Save real responses for 20 Cambridge/Boston addresses under `tests/fixtures/`, and test against those. **Tests never call live services.**

## 4. Overpass (BE-3)

File: `app/resolver.py` → `find_building`

- [ ] Use the query in plan section 9, with the `OVERPASS_URL` endpoint (`/api/interpreter`, not the homepage).
- [ ] Cache responses for 7 days. The public server allows apps only about 100 queries a day across all users.
- [ ] Write a script that precomputes the pilot area (MIT and Kendall).

## 5. Entrances, fallback and the full ladder (BE-4 to BE-7)

- [ ] `read_entrances`: use way membership (`node(w)`), `score_door`, and stop if any candidate is ≥ 0.75.
- [ ] `facade_fallback` and the `street_side` block.
- [ ] Path checks: crosses a road, passes through the building, footway to the entrance.
- [ ] `resolve`: merge candidates within ~4 m, sort best first, return the top 5. Then delete the stub fallback in `main.py`.
- [ ] Store results in SQLite (`DATABASE_PATH`), using the schema in plan section 8.

## 6. Flags (BE-8)

- [ ] Serve `/v1/flags` from config, so a bad data source can be turned off without a deploy.

## Rules

- **The contract is shared.** Change `contract/resolve.example.json` first, then `app/models.py`, then the app's Swift models. `tests/test_contract.py` fails if they drift, or if the app's bundled copy differs.
- Store destinations only, never rider locations. Don't log request bodies.
- API keys stay in `.env` and host secrets, never in the app or the repo.
- Imagery is OSM and Mapillary only. Google Street View's terms ban ML on its images.
