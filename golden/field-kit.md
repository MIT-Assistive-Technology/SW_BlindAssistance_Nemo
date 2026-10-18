# Golden site field kit

Print this. One copy per person. Fill one site sheet per site, then type it into
`golden/locations.json` the same day.

---

## 1. Before you go

- [ ] **Two people.** One measures, one watches traffic and records. Nobody works alone.
- [ ] **Daylight only**, dry weather. Plan to be packed up an hour before sunset. In winter, check
      the sunset time and the forecast the night before.
- [ ] **Permission.** On campus or private property (malls, museums, hotels), ask building
      management or campus facilities before measuring or photographing. Carry the email.
      Public sidewalks need no permission, but don't block them.
- [ ] Read the site's entry in `locations.json`: the TODOs say what this visit must answer.
- [ ] Charge the RTK receiver (if using one) and check its fix mode shows "RTK fixed" at home.

**Kit:** 30 m (100 ft) fiberglass tape · 5 m pocket tape · chalk or painter's tape (no marks
that stay) · high-visibility vests for both · clipboard, this sheet, pencil · phone for photos ·
RTK receiver if available · traffic cone or two.

## 2. Safety first (both people read this)

- Stay on the sidewalk. **Never stand in a travel lane, bike lane or driveway apron to measure.**
  If a measurement needs that, skip it and write down why.
- The recorder watches traffic, bikes and people at all times and calls "stop" for any of them.
  "Stop" means drop the tape and step back. No arguing.
- Keep the tape off the ground across walkways while people pass. Let them through first.
- Don't measure in a driveway while a car is waiting or moving. Wait, or come back.
- If security or staff ask you to stop, stop, explain politely, and leave if asked.
- Vests on the whole time.

## 3. Pick the reference point

Ground truth starts from a point whose coordinates are known **without phone GPS and without
OSM**:

1. **RTK fix** on a building corner (best): hold the receiver on the corner, wait for "RTK fixed"
   and horizontal accuracy under 5 cm, average for 60 s, write down lat/lon.
2. **Survey marker** (a brass disc in the sidewalk) with published coordinates from the city or
   state. Write down the marker ID.
3. **City survey** corner coordinates from the city GIS (not OSM). Write down the source and layer.

Record which, in `reference_point.source`. Measure from **two different reference points** if you
can; that makes the two measurements independent.

## 4. Tape from the corner and convert to lat/lon

You need: the reference corner's lat/lon, the **facade bearing** (the compass direction you walk
along the wall from the corner toward the door), the distance **along** the wall, and the
distance **out** from the wall.

1. Hook the tape on the corner. Run it straight along the wall to the middle of the doorway.
   That's `along_m`.
2. The door point is the middle of the doorway at the outside threshold. If the door is recessed,
   measure out from the wall line to the threshold: `offset_m` (positive toward the street,
   negative into a recess).
3. **Facade bearing:** compute it from two surveyed corners on the same wall (best), or from the
   wall line in the city's survey data. **Don't use the phone compass.** A 10° compass error over
   30 m of tape is 5 m of error, more than the whole tolerance.

Then, with θ = facade bearing (degrees clockwise from north) and lat0/lon0 = the reference corner:

```
north = along_m * cos(θ) - offset_m * sin(θ)        # offset points 90° to the right of θ;
east  = along_m * sin(θ) + offset_m * cos(θ)        # flip the sign of offset_m if the street is on the left
lat   = lat0 + north / 111320
lon   = lon0 + east  / (111320 * cos(lat0))
```

Worked example (made-up numbers, for checking your arithmetic only): θ = 90° (wall runs east),
along 20.00 m, offset 0 → north = 0, east = 20.00 m. At lat0 = 42.36°, 111320 × cos(42.36°) ≈
82,270 m per degree, so lon = lon0 + 0.000243°.

Write the raw `along_m`, `offset_m` and `facade_bearing_deg` into each `measurements[]` entry, not
just the result, so anyone can redo the conversion.

**Second measurement:** repeat from the other reference point, or have the other person repeat
from the same one. Compute `spread_m` = the largest distance between any two measured points. **If
spread is over 2 m, set `truth_uncertain: true`** and plan a re-measure.

## 5. Record the drop-off points

For each place a car would realistically stop (the site's `drop_off_points`):

- [ ] **Position:** RTK at the curb face, or tape from the same reference corner.
- [ ] **Street name** as on the street sign.
- [ ] **Curb side:** stand at the stop and face the direction the street's OSM centerline runs
      (first point to last; the bundle shows it). Is the curb on your `left` or `right`?
      If you can't tell the centerline direction on site, write down the compass direction the
      traffic in that lane travels, and fill `curb_side` in afterwards.
- [ ] **Same or opposite** side as the door (`side_vs_door`).
- [ ] **One-way?** Check the signs. Write `true` or `false`.
- [ ] Anything between the car and the door: bike lane, driveway, garage opening, plaza, steps.

## 6. Photos

No faces, no license plates, no people if you can wait for them to pass. Name files
`<site-id>_<what>_<yyyy-mm-dd>.jpg`.

- [ ] The door straight on, from the sidewalk.
- [ ] The door from each drop-off point (what the rider faces after getting out).
- [ ] Door hardware: handle, push plate, automatic door button, revolving door.
- [ ] Steps, ramp, handrails.
- [ ] The address number and any building sign.
- [ ] The reference corner or survey marker, with the tape hooked on it.
- [ ] Street signs (name and one-way) at each drop-off point.
- [ ] The curb at each drop-off point, and every driveway or garage opening nearby.

## 7. Site sheet (one per site)

```
Site id: ______________________   Date: ____-__-__   Start time: ____   Weather: __________
Crew codes: ____ ____            Permission from (role, not name): ______________________

Reference point A: ____________________  source: rtk / survey_marker / city_survey
   lat ____________  lon ____________
Reference point B: ____________________  source: rtk / survey_marker / city_survey
   lat ____________  lon ____________
Facade bearing θ: _______°  from: two corners / city survey

Measurement 1: ref __  along ______ m  offset ______ m  -> lat ____________ lon ____________
Measurement 2: ref __  along ______ m  offset ______ m  -> lat ____________ lon ____________
Measurement 3: ref __  along ______ m  offset ______ m  -> lat ____________ lon ____________
Spread: ______ m     > 2 m?  Y / N  (Y = truth_uncertain)

Drop-off 1 id ________  street __________  curb L / R  same / opposite  one-way Y / N
   lat ____________ lon ____________  between car and door: _________________________
Drop-off 2 id ________  street __________  curb L / R  same / opposite  one-way Y / N
   lat ____________ lon ____________  between car and door: _________________________

Entrance: main Y / N   steps ___   ramp Y / N   revolving Y / N   automatic Y / N
Notes (locked hours, construction, other doors): ______________________________________
Photos taken (count): ____
```

---

## 8. Trial results CSV

Use `golden/trial-results-template.csv`. One row per run. Participant and spotter are **codes**,
never names.

| Column | What to write |
|---|---|
| `trial_id` | `<site-id>-<yyyymmdd>-<nn>` |
| `date` | `yyyy-mm-dd` |
| `site_id` | id from `locations.json` |
| `phase` | `A` (blindfolded sighted teammate) or `B` (codesigner) |
| `participant_code`, `spotter_code` | e.g. `P01`, `S01` |
| `condition` | `app` or `baseline` (their current tool) |
| `drop_off_point_id` | id from the site's `drop_off_points` |
| `car_final_course_deg` | from the trip log |
| `matched_road` | street the course was matched to |
| `stop_type` | `curb` or `lane` |
| `exit_side` | `curb` or `street` (which car door the rider used) |
| `reached_door` | `Y` / `N`: correct door, no sighted help, within 3 min |
| `sighted_help` | `Y` / `N` |
| `wrong_door_confident` | `Y` if the app named a wrong door without saying it was unsure |
| `final_error_m` | taped distance from where the rider stopped to `entrance_truth` |
| `error_basis` | `camera_confirmed` or `gps_arkit_only` |
| `time_s` | Back Tap (or app start) to hand on the door |
| `corrections` | times the rider had to re-orient or was told "I'm not sure" |
| `safety_stops` | times the spotter stopped the run |
| `sus` | System Usability Scale, 0–100 |
| `nasa_tlx` | NASA-TLX raw score, 0–100 |
| `notes` | short, factual; interview notes go in the separate notes file |

Skip a run at a site marked `truth_uncertain` for error scoring: record it, but leave
`final_error_m` blank and say why in `notes`.

---

## 9. Spotter briefing card

Cut this out. The spotter reads it aloud to the participant before the first run, and keeps it.

> **I am your spotter. My only job is your safety.**
>
> - I stay within arm's reach of you the whole time.
> - If I say **"Stop"**, stop where you are. I'll tell you why.
> - I won't help you navigate unless you ask or it's unsafe. If you ask for help, that's fine; it
>   just gets noted.
> - **You will not cross any street on your own** during this test. If the app says the entrance
>   is across the street, we stop that run there.
> - Your cane or guide dog comes first. The app is an extra, never a replacement.
> - You can stop or skip any run, or end the session, at any time, without a reason.

**The spotter ends the run immediately when:**
- the participant heads into a travel lane, bike lane, driveway or parking aisle;
- the app points toward a roadway or driveway (log it: this is a no-go finding);
- a vehicle, bike or crowd makes the path unsafe;
- the participant is distressed, cold, tired or asks to stop;
- the phone says "Guidance paused" and doesn't recover within 30 s.

**After any stop:** note the time, the site, what happened and the last thing the app said in
`safety_stops` and `notes`. Any contact with a vehicle, fall or near miss is an **incident**: end
the session, tell the team lead the same day, and don't run that site again until the cause is
found and Phase A is re-run (plan section 18, M4).

**Spotter rules:** one spotter per participant, daylight only, vest on, phone on silent, no
headphones.
