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
  |
ViewModels / Session
  CameraViewModel            debug camera screen
  NavigationSession          trip state machine (Setup → Arrival → Orient → Guide → Confirm)
  |
Services
  PerceptionPipeline         frames → detections (+ location)
  FeedbackKit                events → speech / beacon / haptics   (Speaker is the speech channel)
  |
  +--> FramePublishers       CameraFrameProvider (AVFoundation); later ARFrameProvider (ARKit)
  +--> Location              LocationService (CLLocationManager + true heading)
  +--> LocationKit           Geo: distance, bearing, relative angle, side of street (pure math)
  +--> Perception            VisionObjectDetector (Core ML / Vision); later text recognition
  +--> EntranceAPI           EntranceClient (stub JSON now, live server later)
  |
Core models: Frame, Detection, LocationSnapshot · EntranceModels (server contract)
```

## Responsibilities

| Folder | What it does | Plan tasks |
|---|---|---|
| `Core/` | Value types with no UI or framework logic | — |
| `FramePublishers/` | Produces `CVPixelBuffer` frames behind the `FrameProvider` protocol | FE-12 (ARKit adapter) |
| `Location/` | Publishes `LocationSnapshot` (GPS + true heading) | FE-3 |
| `LocationKit/` | Geometry math, unit-tested | FE-2, FE-13 |
| `Perception/` | Object detection to `[Detection]`, later building text check | CV-8, CV-9 |
| `EntranceAPI/` | Server contract types and client; stub loads `Resources/resolve.example.json` | FE-11 |
| `Feedback/` | `FeedbackKit` and its channels; the only place that makes sound or vibration | FE-4, FE-5, FE-6 |
| `Session/` | `NavigationSession` trip state machine | FE-10 |
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

- Frame handling is currently dispatched to the main actor so SwiftUI updates stay safe.
- **TODO:** move detection and interpretation off the main thread, keeping only the final `presentation` update on `@MainActor`.

## Extending

- `VideoFileFrameProvider` for Simulator runs and tests.
- `MockObjectDetector` that returns canned detections.
- `ReplayLocationProvider` that plays back a recorded GPS/heading trace (QA-4).
- `BeaconChannel` and `HapticsChannel` in `Feedback/`.
