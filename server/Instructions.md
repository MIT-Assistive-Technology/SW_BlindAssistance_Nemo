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

`POST /v1/resolve` already returns `contract/resolve.example.json`, so the app team can build against the real shape while you fill in the lookup. For the MVP, the same JSON ships as precomputed bundles for the pilot sites (step 6); the live endpoint is a stretch goal.

## How the code is laid out

| File | What it is | Task |
|---|---|---|
| `app/models.py` | Pydantic mirror of the API contract | — (change the contract first) |
| `app/main.py` | FastAPI routes and the error envelope | BE-1, BE-6 |
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

- [ ] `door_side_of_road`: the sign of the cross product between the road direction and the road-to-door vector (server only; the phone uses the car's course).
- [ ] `photo_ray_bearing` and `ray_hits_outline` with shapely.
- [ ] Unskip `tests/test_geo.py`. Its expected values come from the plan's worked examples.

## 3. Geocoder (BE-2)

File: `app/resolver.py` → `geocode`

- [ ] Call Nominatim with httpx using a **structured** query (`street=`, `city=`, `layer=address`, `entrances=1`), at most 1 request/s process-wide, with `USER_AGENT` from `.env`. Free-form text matches things like bus stops named after addresses.
- [ ] Save real responses for 20 Cambridge/Boston addresses under `tests/fixtures/`, and test against those. **Tests never call live services.**

## 4. Overpass (BE-3)

File: `app/resolver.py` → `find_building`

- [ ] Use the corrected query in plan section 9 (multipolygon outers, `door=*` nodes, site relations, footways, nearby roads). Keep the tag rules in Python.
- [ ] Load the pilot area once from the Geofabrik Massachusetts extract (or one bbox pull from `OVERPASS_URL`, `/api/interpreter`). Public Overpass allows about 100 queries and 10 MB a day per deployment.

## 5. Entrances, fallback and the full ladder (BE-4 to BE-7)

- [ ] `read_entrances`: use way membership (`node(w)`) and `score_door`. Combine agreeing evidence with `combine` (best score plus one step, not noisy-OR).
- [ ] `facade_fallback` and the `street_side` block.
- [ ] Path checks: crosses a road, passes through the building, footway to the entrance.
- [ ] `resolve`: merge candidates within ~4 m, sort best first, return the top 5. Then delete the stub fallback in `main.py`.
- [ ] Stretch: store results in SQLite (`DATABASE_PATH`, WAL mode) keyed by building and address hash, never with an install key.

## 6. Pilot bundles (the MVP deliverable)

- [ ] Write `scripts/build_bundles.py`: for each pilot site, run the ladder on preloaded OSM data and write one JSON bundle in the contract's shape to `bundles/<site>.json`.
- [ ] Validate every bundle with `ResolveResult.model_validate` in a test.
- [ ] OSM entrance coverage is low (about 10% of MIT/Kendall buildings, 1.8% of Cambridge). Before building bundles, survey the pilot entrances on site and add them to OSM by hand, with changeset comments like "Add main entrance to … based on survey".

## Rules

- **The contract is shared.** Change `contract/resolve.example.json` first, then `app/models.py`, then the app's Swift models. `tests/test_contract.py` fails if they drift, or if the app's bundled copy differs.
- Store destinations only, never rider locations. Don't log request bodies.
- API keys stay in `.env` and host secrets, never in the app or the repo.
- Imagery is OSM and Mapillary only. Google Street View's terms ban ML on its images.
