# Golden locations

Golden locations are about 10 real drop-off sites where the team has measured the true door
position by hand. They are the answer key for the project (plan section 18). Everything else is
scored against them: the server's entrance bundles, OSM's entrance tags, and the app in field
trials.

| File | What it is |
|---|---|
| `locations.json` | The sites. Right now these are **templates**: every measured value is `null` with a TODO. |
| `schema.json` | JSON Schema (draft 2020-12) for one entry in `locations.json`. |
| `field-kit.md` | Printable on-site checklist, how to measure, spotter briefing card. |
| `trial-results-template.csv` | One row per field-trial run. |

`server/tests/test_golden.py` checks `locations.json` against `schema.json`, checks that ids are
unique, and checks that the scenario mix matches the plan. Run it from `server/` with `pytest`.

The file is JSON, not YAML, because PyYAML isn't a server dependency and the plan says not to add
dependencies for this.

## The site mix

| Scenario | Sites | Counts toward April? |
|---|---|---|
| `same_side` | 4 | Yes |
| `driveway` | 2 | Yes |
| `opposite_side` | 2 | Measured only |
| `campus` | 2 | Measured only |

The set must also include **one building with drop-offs on both sides** (tag `both_sides_dropoff`)
and **one site on a one-way street** (tag `one_way`). The test fails if either is missing.

The candidate addresses come from `server/tests/fixtures/nominatim/addresses.json`, so each site
also has saved geocoder responses. Every "why chosen" is a hypothesis until the site visit confirms
it. If a site turns out not to fit (no driveway, the street isn't one-way), swap it out and keep
the mix.

## Ground truth rules

1. **Never copy truth from OSM.** OSM is what's being tested. Take the `osm_snapshot` only after
   the truth is written down, and only to score OSM.
2. **Never use phone GPS.** Phone GPS error is what's being measured. Use a tape measure from a
   surveyed corner, an RTK receiver, or a survey marker (`method`).
3. **At least 2 independent measurements** per door: different reference corners, a different
   crew, or a different day. List each one in `measurements[]`. The truth `lat`/`lon` is their
   average.
4. **`spread_m`** is the largest distance between any two measurements. **If it's over 2 m, set
   `truth_uncertain: true`** and the site is excluded from scoring until it's measured again. The
   schema rejects an entry with spread over 2 m that isn't marked uncertain.
5. The door point is the middle of the doorway at the threshold, on the outside.
6. Never invent a number to make a test pass. A `null` with a TODO is the correct value until
   someone has been on site. The test fails if a `template` entry has any coordinates.
7. No people's names anywhere in this folder. Participants and spotters are codes (`P01`, `S01`).

When a site has been measured, change `status` to `measured`. The schema then requires real
coordinates, a method, dates and at least 2 measurements, and the test checks that `spread_m` and
the averaged point match the measurements.

## How the sites are used

**Scoring server bundles (M1, plan section 18).** For each site not marked `truth_uncertain`:
- *Correct building*: the bundle's top entrance is on the right building.
- *Distance error*: metres from the bundle's top entrance to `entrance_truth`.
- *Correct side*: the bundle's `door_side_of_road` matches the side the door is really on, using
  each drop-off point's `curb_side` and `side_vs_door`.
- *OSM baseline*: `osm_snapshot.distance_to_truth_m` and `has_entrance_tag` show how much the
  server adds over raw OSM.

M1 is a no-go if any site gets the wrong building.

**Scoring field trials (Phases A and B).** Each run is a row in `trial-results-template.csv`.
Final position error is the taped distance from where the rider stopped to `entrance_truth`. Only
`same_side` and `driveway` sites count toward the April gates (≥ 85% reached at same-side sites, 0
driveway or garage errors). Report n and the 95% confidence interval with every number.

**Safety replay (plan section 16).** The CI replay test uses the drop-off points and truth here to
fail if any prompt points into a roadway or driveway at a golden site.
