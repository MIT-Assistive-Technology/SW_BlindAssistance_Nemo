# Nemo Architecture

This scaffold is modeled after the [thing-finder](../thing-finder/) object-detection pipeline, simplified for a blind/low-vision assistance app.

## Goals

- Keep the UI layer thin.
- Make every hardware dependency replaceable with a mock or stub for tests.
- Process frames on a background queue; publish results on the main actor for SwiftUI.
- Attach location/heading context to each frame so interpretation can be spatial.

## Layer Diagram

```
Views (SwiftUI)
  |
  v
ViewModels (ObservableObjects)
  |
  v
Services
  PerceptionPipeline          <- FrameProviderDelegate
  Speaker
  |
  +---> FramePublishers       <- CameraFrameProvider (AVFoundation)
  +---> Location              <- LocationService (CLLocationManager + CLHeading)
  +---> Perception            <- VisionObjectDetector (CoreML/Vision)
  |
  v
Core models: Frame, Detection, LocationSnapshot
```

## Responsibilities

| Layer | File(s) | What it does |
|-------|---------|--------------|
| **Core** | `Core/*.swift` | Domain value types. No UI or framework logic. |
| **FramePublishers** | `FramePublishers/*.swift` | Produces `CVPixelBuffer` frames. Today only `CameraFrameProvider` exists; a `VideoFileFrameProvider` or Meta glasses adapter can be added later. |
| **Location** | `Location/LocationService.swift` | Publishes `LocationSnapshot` (GPS + heading). |
| **Perception** | `Perception/*.swift` | Runs object detection and returns `[Detection]`. |
| **Services** | `Services/PerceptionPipeline.swift`, `Services/Speaker.swift` | Wires everything together, speaks detections, and publishes `FramePresentation` for the UI. |
| **ViewModels** | `ViewModels/CameraViewModel.swift` | Owns the live `FrameProvider` and exposes `start`/`stop`. |
| **Views** | `Views/*.swift` | SwiftUI screens and overlays. |

## Data Flow

1. `CameraFrameProvider` captures a frame on a background queue.
2. It calls `delegate?.processFrame(_:buffer:)`.
3. `PerceptionPipeline` (the delegate) runs `VisionObjectDetector` to get `[Detection]`.
4. It reads the latest `LocationSnapshot` from `LocationService`.
5. It asks `Speaker` to verbalize the top detection.
6. It publishes a `FramePresentation` on the main actor.
7. `CameraViewModel` forwards the presentation to `StatusOverlayView`.

## Concurrency Notes

- The scaffold currently dispatches frame handling to the main actor so SwiftUI updates stay safe.
- **TODO**: Move detection and interpretation off the main thread; only the final `presentation` update should be `@MainActor`.

## Extending the Scaffold

- Add a `VideoFileFrameProvider` for unit tests / simulator previews.
- Add a `MockObjectDetector` that returns canned detections.
- Add a `HapticFeedbackManager` for non-visual guidance.
- Add an image/GPS upload service for later map or Street View alignment.
