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

## Planned layout

```
BlindAssist/
  App/        SwiftUI entry, AppIntents (Siri, Back Tap), ControlWidgets
  Features/   DestinationEntry, SavedPlaces, Settings, Session
  Core/       FeedbackKit, LocationKit, ARGuide, DoorVision, EntranceAPI, Telemetry
Tests/        XCTest + recorded GPS/heading traces
```

## Start here

See the App tasks (FE-1 to FE-14) in [`../docs/car-to-curb-plan.md#20-work-breakdown`](../docs/car-to-curb-plan.md#20-work-breakdown).
