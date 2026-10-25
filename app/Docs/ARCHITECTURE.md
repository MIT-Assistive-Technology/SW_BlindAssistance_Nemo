# App Architecture

This is the starting structure for the iOS side of Car to Curb. The full system design is in [`../../docs/car-to-curb-plan.md`](../../docs/car-to-curb-plan.md); this page covers only how the app's code is organized.

## Goals

- Keep the UI layer thin. The real interface is sound, speech and vibration, and the screens are VoiceOver-first.
- Make every hardware dependency replaceable with a mock or a recorded replay for tests (camera, location, detector, server).
- Process frames off the main thread. Publish results on the main actor for SwiftUI.
- Attach location and heading to each frame so detections can be placed in space.
- Keep everything on the phone. No camera frames or live location leave it.

## Layer diagram

```
Views (SwiftUI, VoiceOver-first)
  ContentView                hub: Ride, Walk, Heading, Camera (debug)
  |
ViewModels / Session
  RideViewModel              destination bundle + ride tracking + side of street
  GuidanceViewModel          feeds positions and heading into the state machine
  HeadingViewModel           live true heading, announcement throttling
  CameraViewModel            debug camera screen
  NavigationSession          trip state machine, Setup → Riding → Arrival → Orient →
                             Guide → Confirm → Arrived, with Lost; breadcrumbs, the
                             first-steps check, and resume-after-relaunch via SessionStore
  |
Services
  AppServices                composition root (sensors, feedback, bundle cache)
  PerceptionPipeline         frames → detections (+ location)
  FeedbackKit                events → speech / beacon / haptics   (Speaker is the speech channel)
  |
  +--> FramePublishers       CameraFrameProvider (AVFoundation); later ARFrameProvider (ARKit)
  +--> Location              LocationService (CLLocationManager + true heading + car course)
  +--> LocationKit           pure math and rules: Geo, HeadingReadout, CarCourseTrack,
  |                          SideOfStreetResolver
  +--> Perception            VisionObjectDetector (Core ML / Vision); later text recognition
  +--> EntranceAPI           EntranceClient (stub JSON, live server, caching wrapper) +
  |                          BundleStore (on-phone cache)
  |
Core models: Frame, Detection, LocationSnapshot · EntranceModels (server contract)
Phrases: Feedback/Phrases.swift — every spoken string, checked by SAFE-1
```

## Responsibilities

| Folder | What it does | Plan tasks |
|---|---|---|
| `Core/` | Value types with no UI or framework logic | — |
| `FramePublishers/` | Produces `CVPixelBuffer` frames behind the `FrameProvider` protocol | FE-12 (ARKit adapter) |
| `Location/` | Publishes `LocationSnapshot` (GPS + true heading) and records the car's course for the ride | FE-3, FE-13 |
| `LocationKit/` | Geometry math and the rules built on it, unit-tested, no CoreLocation | FE-2, FE-3, FE-13 |
| `Perception/` | Object detection to `[Detection]`, later building text check | CV-8, CV-9 |
| `EntranceAPI/` | Server contract types, clients (stub / live / caching) and the on-phone `BundleStore` | FE-11 |
| `Feedback/` | `FeedbackKit`, its channels and the `Phrases` table; the only place that makes sound or vibration | FE-4, FE-5, FE-6 |
| `Session/` | `NavigationSession` trip state machine and `SessionStore` (resume after relaunch). Takes value types in through `update(position:heading:)`, emits `FeedbackEvent`s — no CoreLocation, so a recorded trace replays headless | FE-10 |
| `Services/` | `PerceptionPipeline` wiring, `Speaker` (speech) | — |
| `ViewModels/`, `Views/` | SwiftUI screens; the camera screen is a debug view | FE-7, FE-9 |

## Data flow (perception)

1. `CameraFrameProvider` captures a frame on a background queue.
2. It calls `delegate?.processFrame(_:buffer:)`.
3. `PerceptionPipeline` runs `VisionObjectDetector` to get `[Detection]`.
4. It reads the latest `LocationSnapshot` from `LocationService`.
5. It emits a feedback event (today it speaks via `Speaker`; move this to `FeedbackKit`).
6. It publishes a `FramePresentation` on the main actor for the debug overlay.

## Rules

- **The contract is shared.** `EntranceAPI/EntranceModels.swift` mirrors `contract/resolve.example.json`. Change the contract first, then the Swift models and `server/app/models.py`. Keep `Resources/resolve.example.json` identical to `contract/resolve.example.json`; a server test checks this.
- **ARKit owns the camera.** ARKit and `AVCaptureSession` can't run together. When guidance moves to ARKit (FE-12), add an `ARFrameProvider` that forwards `ARFrame.capturedImage` through `FrameProvider`, so the pipeline doesn't change.
- **No certainty words** for doors the camera hasn't confirmed (SAFE-1).
- **Imagery:** OSM and Mapillary only. Google Street View's terms ban ML on its images.

## Concurrency

The project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so **every type is main-actor isolated unless it says otherwise**. Plan section 11 says that must not cover the data types or the perception path.

- Pure math, rules, contract models and the bundle cache are marked `nonisolated`: `Geo`, `HeadingReadout`, `CarCourseTrack`, `SideOfStreetResolver`, `Phrases`, `EntranceModels`, the entrance clients, `BundleStore`, `LocationSnapshot`, `FeedbackEvent`. Mark new ones the same way, or they can only be used from the main thread — and the unit tests, which are not main-actor isolated, won't compile against them.
- View models, views, `LocationService` and the feedback channels stay main-actor isolated on purpose.
- **TODO:** `Core/Frame.swift`, `Core/Detection.swift` and `PerceptionPipeline` are still main-actor isolated. Move detection and interpretation onto one serial background queue, keeping only the final `presentation` update on `@MainActor`.

## Extending

- `VideoFileFrameProvider` for Simulator runs and tests.
- `MockObjectDetector` that returns canned detections.
- `ReplayLocationProvider` that plays back a recorded GPS/heading trace (QA-4).
- `BeaconChannel` and `HapticsChannel` in `Feedback/`.
