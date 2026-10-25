# App: Getting Started

A step-by-step path from an empty scaffold to the first working guidance. Each step names the file to open and the task ID from [`docs/car-to-curb-plan.md`](../../docs/car-to-curb-plan.md#20-work-breakdown). Pick an unchecked step, open a branch (`yourname/FE-2-geo-math`), and send a small PR.

## 0. Project setup

- [x] Open `app/nemo-software.xcodeproj` in Xcode on a Mac.
- [x] Under **Signing & Capabilities**, choose your own team. The repo leaves it blank on purpose.
- [x] Camera and location permission text is already set in the build settings (`INFOPLIST_KEY_NSCameraUsageDescription`, `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription`). Only "while using" location; never ask for "Always" in the MVP.
- [x] The `audio` and `location` background modes are in `app/Info.plist` (outside the synced folder on purpose). The target is iPhone-only.
- [x] Build for an iPhone Simulator. It should launch without a camera; the camera code skips setup when no device exists.
- [x] New files go inside `nemo-software/`. The project syncs that folder automatically, so you don't need to add files to the target by hand.

## Running the tests

Everything below that can be tested without a car or a walk is covered by the
`nemo-softwareTests` target. In Xcode press **⌘U**, or from the repo root:

```bash
xcodebuild -project app/nemo-software.xcodeproj -scheme nemo-software \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Use a simulator name from `xcrun simctl list devices available`, and open Simulator
first: a cold device sometimes fails to launch the test host on the first run.

## 1. Camera stream

File: `FramePublishers/CameraFrameProvider.swift`

- [ ] Request permission with `AVCaptureDevice.requestAccess(for: .video)` before configuring.
- [ ] Implement `setupSession()`:
  - Return early if `captureDevice` is nil (Simulator, CI).
  - `captureSession.beginConfiguration()`.
  - Add `AVCaptureDeviceInput` for `captureDevice`.
  - Add `videoOutput` with `alwaysDiscardsLateVideoFrames = true`.
  - `commitConfiguration()`.
  - Set `self` as the sample-buffer delegate on `cameraQueue`.
- [ ] Implement `captureOutput(_:didOutput:from:)`: take `sampleBuffer.imageBuffer` and pass it to `delegate?.processFrame(_:buffer:)`.

File: `Views/CameraView.swift`

- [ ] Replace the black background with an `AVCaptureVideoPreviewLayer` in a `UIViewRepresentable`. This is a debug screen; riders won't rely on it.

## 2. GPS and heading (FE-3)

File: `Location/LocationService.swift`

- [x] Set `desiredAccuracy = kCLLocationAccuracyBest`, request when-in-use authorization, and start location and heading updates.
- [x] In `didUpdateLocations`, store the newest coordinate, `horizontalAccuracy` and timestamp in `currentSnapshot`.
- [x] In `didUpdateHeading`, use **`trueHeading`**, not `magneticHeading`, and skip readings with negative `headingAccuracy`.
- [x] In `stop()`, stop both updates.
- [x] Add an "I'm in the car" action that starts background updates while the app is open (`allowsBackgroundLocationUpdates` or `CLBackgroundActivitySession`). It records the car's course for side-of-street detection.
- [x] Handle `didFailWithError`, and announce a permission-denied state by voice, not just on screen.
- [x] Heading readout screen: `LocationKit/HeadingReadout.swift` (pure: compass points, the 20° calibration threshold, announcement throttling), `ViewModels/HeadingViewModel.swift` and `Views/HeadingView.swift`. Tests: `HeadingReadoutTests`.
- [ ] Field check still to do: compare the readout with a surveyed street bearing at the golden sites (task R1), and run the screen with VoiceOver on and the screen rotated.
- [ ] Stop detection currently uses speed only, so it can't tell a red light from a drop-off; that's why it only ever asks (see 3b). Core Motion's "walking" report would let the prompt be trusted more, but it needs an `NSMotionUsageDescription` key and a privacy-label entry, so it's left as a separate step. One good option when it's picked up: instead of streaming activity updates for the whole ride, call `CMMotionActivityManager.queryActivityStarting(from:to:)` **after** a stop to read the last minute of history — same permission, far less battery, and it still works if the app was backgrounded. `CMMotionActivityManager.isActivityAvailable()` is false in the Simulator, so it needs a mockable provider.

## 3. Geometry math (FE-2)

File: `LocationKit/Geo.swift`

- [x] Implement `distanceMeters`, `bearingDegrees`, `relativeAngle`, `side`, `sameSide` and `photoRayBearing`.
- [x] Add XCTest cases from the plan's worked examples (`nemo-softwareTests/GeoTests.swift`, run with ⌘U):
  - side of street: road bearing 90°, door "right", course 92° → `true`; course 268° → `false`; one-way → `nil`
  - left/right of walking direction: direction (1, 0), point at (30, −10) → `.right`
  - relative angle: heading 350°, target 10° → +20°
- [x] Polyline helpers for the road's direction and the car's distance from its centerline: `Geo.polylineBearingDegrees`, `Geo.distanceToPolylineMeters` (`GeoPolylineTests`).

## 3b. Side of street at the drop-off (FE-13)

Files: `LocationKit/CarCourseTrack.swift`, `LocationKit/SideOfStreet.swift`, `ViewModels/RideViewModel.swift`, `Views/RideView.swift`

`Geo.sameSide` is the geometry; these decide **whether the app is allowed to answer at
all**. A wrong call sends a rider across a road, so every case in the plan's section 6
list comes back `.unknown(reason)` and the rider is asked instead.

- [x] Record `CLLocation.course`, `courseAccuracy` and `speed` between "I'm in the car" and the stop (`CarCourseTrack`), keeping only courses above 3 m/s with accuracy ≤ 20°.
- [x] Refuse to answer on a one-way street, after a turn in the last 10 s, with a stale or poor course, with no tracked ride, or when the stop was more than 30 m from the matched centerline.
- [x] **The rider says when they're out of the car.** Nothing in the sensors can tell a red light from a drop-off — the GPS speed trace is identical — so a detected stop only ever asks: *"It looks like the car has stopped, about 40 feet from your entrance. If this is your drop-off, exit on the curb side, then tell me when you're out of the car."* `confirmOutOfCar()` is the authoritative signal and works any time during the ride. The cycle is: **detect → ask once → "not yet" → re-arm when the car moves → ask again at the next stop**, repeating until the rider confirms.
  - Each move-and-stop cycle produces a new stop timestamp, which is what allows the question to be asked again; `stopDetected` anchors on the last sample where the car **moved at all** (≥ 1 m/s), not the last good driving course, so a car creeping forward in traffic still re-arms it.
  - Stops further than `maxPromptDistanceMeters` (150 m) from the entrance don't raise the question. It's the only filter the sensors allow, and without it a 20-minute ride would prompt at every light. The distance is quoted in the question because it's what lets a rider who can't look out of the window judge the answer. When the distance is unknown the question is still asked — it's a question, not an instruction — and "I'm out of the car" works anywhere regardless.
- [x] Speak the result, and ask "are you on the sidewalk, with the building side to your right?" whenever it's unknown. The rider's answer wins.
- [x] Tests: `CarCourseTrackTests`, `SideOfStreetTests` (including the plan's 92° / 268° example and the real `resolve.example.json` centerline).
- [ ] **Not done, and it's the task's definition of done:** replay the R5 logged rides through `SideOfStreetResolver` and count correct / unknown / wrong. The rule is only trustworthy once "wrong" is 0 on real data.

## 4. Server data with the stub (FE-11)

Files: `EntranceAPI/EntranceModels.swift`, `EntranceAPI/EntranceClient.swift`, `EntranceAPI/BundleStore.swift`

- [x] Call `StubEntranceClient().resolve(address:)` and check that `Resources/resolve.example.json` decodes. If decoding fails, the Swift models and the contract disagree; fix the model, not the JSON.
- [x] Cache bundles on the phone and restore them on relaunch: `BundleStore` writes one JSON file per destination in Application Support, keyed by a normalized address, with `fetchedAt`. `CachingEntranceClient` saves every fresh result and falls back to the stored one when the network fails, so the walk works with no signal.
- [x] Implement `LiveEntranceClient`: `POST /v1/resolve` with `X-Install-Key` (a per-install UUID, `InstallKey`), `200` decoded with `JSONDecoder.entrance`, and the error envelope from the plan's section 10 surfaced as `EntranceError.service`. Note there is **no 202 and no polling**: a weak result is `200` with `status: "partial"` (the older TODO in the file said otherwise; the contract wins).
- [x] Tests: `BundleStoreTests`, `EntranceClientTests` (the live client is tested against a stubbed `URLProtocol`, not a server).
- [ ] Still to do: run it against the real server once BE-6 writes bundles for the pilot sites, and decide when a cached bundle is too old to use.

## 4b. What the camera tells navigation (CV-9 → FE-10)

Files: `Core/BuildingSighting.swift`, `Session/NavigationSession.swift` (`observe(_:)`)

GPS and the compass can't find a door: the anchor is 5–15 m off and the compass 10–20°,
which is 7–14 m sideways at 40 m. **The camera is the only thing that can correct that**,
so navigation is built to take corrections from it — the seam exists and is tested, and
the perception side can be written against it.

- [x] `BuildingSighting` is the one message from perception to navigation: the matched text, the true bearing it was read in, and a confidence. There's an initializer that turns a bounding box's pixel column into a bearing with `Geo.photoRayBearing`, the same pinhole model the server uses on street photos.
- [x] `NavigationSession.observe(_:)` checks the sighting **before** believing it: the direction has to agree with the building outline from the bundle (within 25°, since the compass itself is only 10–20° out). Agreement corrects a `headingBiasDegrees` that every direction in the app then goes through, so one sighting improves orienting, guiding, the off-route check and the first-steps check at once. Disagreement is spoken as *"I see 77, but it may not be your building"* and changes nothing.
- [x] The correction is damped (half of each new error), capped at 25°, re-learned for each new walk, and low-confidence results are ignored.
- [x] Never certainty: *"That looks like your building."* `isBuildingConfirmed` lets the camera stop once it has agreed, which is where its battery cost is.
- [x] A check that can't run says so: `cameraCheckUnavailable(.lowLight)`.
- [ ] **The camera side itself (CV-9).** Vision text recognition on frames, matched against `recognize.text`, correct orientation, one request at a time on a background queue. The hook is marked in `PerceptionPipeline.processFrame`.
- [ ] Position re-anchoring (moving the target rather than correcting the heading) needs ARKit's relative tracking to be meaningful — FE-12.

**What the camera is not for in this MVP.** The plan is explicit, and it matters for safety:
the camera *confirms the map*, it never decides which door is the entrance (order of trust:
surveyed OSM door → other tags → outline → street photos). Obstacle detection is v2 — the
cane does obstacles, and an app that implies otherwise is dangerous. Telling a rider when
it's safe to cross is on the "not doing" list.

## 5. Object detection (CV-8)

File: `Perception/VisionObjectDetector.swift`

- [ ] **First benchmark iOS Magnifier's Door Detection at the test sites (CV-11).** The custom detector is an optional, parallel track.
- [ ] Add a Core ML detector to the target. Check the license first (ADR 0007): Ultralytics YOLO is AGPL-3.0, so prototype with it if you like, but plan to ship an Apache-2.0 model such as RF-DETR.
- [ ] Load it in `init()` as a `VNCoreMLModel`.
- [ ] Implement `detect(_:filter:orientation:)` with `VNCoreMLRequest` (`.scaleFill`) and `VNImageRequestHandler`, converting results with `Detection(from:)` and applying `filter`.
- [ ] In `PerceptionPipeline.processFrame`, drop low-confidence detections (start at `confidence > 0.4`), and only count a door once it appears in 5 of the last 8 frames.

## 6. Feedback (FE-4 to FE-6)

Files: `Feedback/FeedbackKit.swift`, `Services/Speaker.swift`

- [x] Implement `Speaker.speak(_:)` with `AVSpeechUtterance`, and `stop()` with `stopSpeaking(at: .immediate)`. Set `prefersAssistiveTechnologySettings = true` so it uses the rider's VoiceOver voice.
- [ ] Move announcements out of `PerceptionPipeline` and into `FeedbackKit.emit(_:)` events.
- [x] Add a **chatter guard**: don't repeat the same phrase within a few seconds (`SpeechChannel.repeatGuard`).
- [x] Started the phrase table in `Feedback/Phrases.swift`: every heading, side-of-street and destination-brief phrase lives there, `SpeechChannel` maps events to it, and `PhrasesTests` runs the SAFE-1 certainty-word scan over `Phrases.all`. The guidance-core events (`arrival`, `lost`, `bearingLock`, `landmark`, `doorDetected`) still have no words on purpose — add them here, and to `Phrases.all`, or SAFE-1 can't see them.
- [ ] Add `BeaconChannel` (HRTF tone at the door) and `HapticsChannel` (AHAP patterns).

## 7. Trip state machine (FE-10)

Files: `Session/NavigationSession.swift`, `Session/SessionStore.swift`, `ViewModels/GuidanceViewModel.swift`, `Views/GuidanceView.swift`

- [x] Implement the transitions listed in the file header, driven by `update(position:heading:)`: Setup → Riding → Arrival → Orient → Guide → Confirm → Arrived, with Guide/Confirm → Lost → Orient.
- [x] Test by replaying a recorded GPS trace, not by walking. `NavigationSessionTests` replays a full trip, a lost-and-recover trip, a failed first-steps check and a relaunch, all from synthetic positions.
- [x] Thresholds live in one struct, `GuidanceThresholds`: 15° held for 1 s to lock on, 10 m to enter Confirm, 3 m to Arrived, 60° for 5 s to be Lost, the first-steps check after 5 m with a 30° tolerance, breadcrumbs every 5 m, spoken distances at 60 ft and 30 ft. The plan fixes most of these; **they are starting points, not measured facts**, and belong in the codesigner sessions.
- [x] Never guide across a roadway: with the door on the far side, `startGuidance()` refuses and says it's waiting until the rider says they're across. An unknown side asks instead of guessing.
- [x] Lost re-anchors at the **last breadcrumb**, not the door — somewhere the rider has actually stood — and recovers when they turn back towards it for 2 s.
- [x] Guidance never ends silently: every exit from the walk speaks, and "Where am I" (`repeatGuidance()`) says something in every state, forced past the chatter guard.
- [x] Relaunch mid-trip (`SessionStore` + `resume(from:bundle:)`): during the **ride**, the car track is gone so the side of street reverts to unknown and the rider is asked again; during the **walk**, the old heading lock can't be trusted, so it re-anchors and returns to Orient rather than pretending to still be on course.
- [ ] Still missing, and it's what makes the walk usable: a continuous directional signal. Speech every few metres is not navigation — the beacon (FE-4) and haptics (FE-5) are the real output, and ARKit (FE-12) is what keeps the anchor honest between GPS fixes.
- [ ] Not implemented: following `route` waypoints (straight-line only), announcing `landmarks`, the camera building check, and Back Tap as the start/repeat gesture.

## 8. Accessibility (QA-5)

- [ ] Every control has a label, a hint and the right trait. Test with VoiceOver on.
- [ ] Add an XCUITest target that runs `performAccessibilityAudit()` on every screen.

### Rules the code already follows

The rider can't see the screen, so these aren't polish — they're the difference between
a working app and a broken one. Keep them when you add a screen:

- **Nothing important is screen-only.** Every status, failure and prompt that matters is emitted as a `FeedbackEvent` and spoken, not just rendered. A load failure, a denied location permission and a bundle that couldn't be saved for offline use are all spoken.
- **Every action makes a sound.** Tapping "Load entrance details" says "Looking up the entrance" straight away, because a network call that takes seconds is otherwise indistinguishable from a tap that didn't register.
- **Never promise what the app can't deliver.** "I'm in the car" doesn't announce that it's tracking the ride unless location is actually authorised; if it's denied, it says so instead.
- **Repeat must always work.** `FeedbackKit.emit(_:force:)` bypasses the chatter guard. A "repeat" tap that stays silent because the same phrase was said 3 seconds ago reads as a broken app to someone who can't see the screen.
- **The rider decides, the phone suggests.** Anything the sensors can't be sure of is a question, not an action — the drop-off (FE-13) and the side of street both work this way, and the rider's answer overrides the guess.
- **Questions have to be answerable without sight.** "Are you on the sidewalk, with the building side to your right?" can be answered by cane; it also names the street and compass side so the rider can match it against what the driver said.
- **No dead ends.** "Your entrance is across the street" always continues with what to do, even when the bundle has no marked crossing.
- **Screen text matches the speech.** `sideText` is generated from the same phrase table that was spoken, so what VoiceOver reads can't drift from what was said. Developer detail (the "unknown" reason, the raw track summary) is kept in a separate, clearly labelled place.
- **Controls stay put.** "I'm out of the car" is in the same position for the whole ride, so it can be found by swiping rather than by looking.
- **No fixed font sizes**, so Dynamic Type up to AX5 works for riders with some remaining sight.

### Open questions that need a real VoiceOver user

- **Our speech versus VoiceOver's.** `AVSpeechSynthesizer` and VoiceOver can talk at the same time, and two voices at once means neither is understood. The alternatives are routing announcements through `UIAccessibility.post(notification: .announcement)` (queues politely behind VoiceOver, but announcements can be dropped during screen changes — bad for safety-critical prompts) or keeping the synthesizer (always plays, may overlap). **This has not been tested and should not be guessed at**; it belongs with the audio-session task, measured with VoiceOver on, Music playing and an active Uber trip.
- **Answering by gesture rather than by button.** The plan wants Back Tap for "repeat / where am I" and a tap / double-tap answer at the door. Until that lands, every prompt also has an on-screen button.
- **Verbosity.** Some prompts are long for a rider stepping out of a car into traffic. Two verbosity levels are part of the settings screen.

## Recommended order

1. Project setup and camera stream (you see pixels).
2. Location and geometry math (you see heading and get correct bearings).
3. Stub server data (the app knows where the door is).
4. Feedback: speech, then beacon and haptics (the app guides).
5. Session state machine (a full trip from a recorded trace).
6. Detection (the camera confirms the door).

## Not now

- ARKit tracking (FE-12) and text recognition for the building check (CV-9) come after the steps above. Text recognition reads 15–30 cm numbers at about 10–20 m on normal frames (20–35 m with high-res stills plus a crop), not 50 m. ARKit drifts 1–3 m over 50 m, and the GPS starting point can be 5–15 m off, so the app keeps re-anchoring.
- Sending images anywhere. Frames never leave the phone.
