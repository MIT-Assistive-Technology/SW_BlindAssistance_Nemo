# App (iOS)

The iPhone app: everything that happens on the rider's phone. That covers positioning, side-of-street detection, the camera building and door checks, and audio/haptic/voice feedback.

**Stack:** Swift / SwiftUI, Apple frameworks only to start (ARKit, CoreLocation, Core ML, Vision, Core Haptics, AVAudioEngine).
**Needs:** a Mac with Xcode. LiDAR iPhones are optional for testing.

## Talks to the server through one contract

The app calls the server once per trip, before arrival, and caches the result. Until the server is running, build against a stub JSON file that matches the contract in [`../docs/car-to-curb-plan.md#10-api-contract`](../docs/car-to-curb-plan.md#10-api-contract).

Rules:
- Send only the destination address, never the rider's live location.
- No camera frames leave the phone.
- No server API keys in the app.

## Layout

Based on the `tagem-scaffold` branch, adapted to this plan.

```
nemo-software.xcodeproj
nemo-software/
  Core/             Frame, Detection, LocationSnapshot
  FramePublishers/  FrameProvider protocol, CameraFrameProvider
  Location/         LocationService (GPS + true heading)
  LocationKit/      Geo math (distance, bearing, side of street)
  Perception/       ObjectDetector protocol, VisionObjectDetector
  EntranceAPI/      Server contract models, Stub/Live clients
  Feedback/         FeedbackKit and channels
  Session/          NavigationSession state machine
  Services/         PerceptionPipeline, Speaker
  ViewModels/ Views/
  Resources/        resolve.example.json (copy of ../contract/)
Docs/
  ARCHITECTURE.md   how the code is organized
  Instructions.md   step-by-step getting started
```

## Start here

Follow [`Docs/Instructions.md`](Docs/Instructions.md). 
See the App tasks (FE-1 to FE-14) in [`../docs/car-to-curb-plan.md#20-work-breakdown`](../docs/car-to-curb-plan.md#20-work-breakdown).
