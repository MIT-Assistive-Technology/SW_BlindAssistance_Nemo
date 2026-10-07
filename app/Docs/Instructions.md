# App: Getting Started

A step-by-step path from an empty scaffold to the first working guidance. Each step names the file to open and the task ID from [`docs/car-to-curb-plan.md`](../../docs/car-to-curb-plan.md#20-work-breakdown). Pick an unchecked step, open a branch (`yourname/FE-2-geo-math`), and send a small PR.

## 0. Project setup

- [ ] Open `app/nemo-software.xcodeproj` in Xcode on a Mac.
- [ ] Under **Signing & Capabilities**, choose your own team. The repo leaves it blank on purpose.
- [ ] Camera and location permission text is already set in the build settings (`INFOPLIST_KEY_NSCameraUsageDescription`, `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription`). Only "while using" location; never ask for "Always" in the MVP.
- [ ] Build for an iPhone Simulator. It should launch without a camera; the camera code skips setup when no device exists.
- [ ] New files go inside `nemo-software/`. The project syncs that folder automatically, so you don't need to add files to the target by hand.

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

- [ ] Set `desiredAccuracy = kCLLocationAccuracyBest`, request when-in-use authorization, and start location and heading updates.
- [ ] In `didUpdateLocations`, store the newest coordinate, `horizontalAccuracy` and timestamp in `currentSnapshot`.
- [ ] In `didUpdateHeading`, use **`trueHeading`**, not `magneticHeading`, and skip readings with negative `headingAccuracy`.
- [ ] In `stop()`, stop both updates.
- [ ] Handle `didFailWithError`, and announce a permission-denied state by voice, not just on screen.

## 3. Geometry math (FE-2)

File: `LocationKit/Geo.swift`

- [ ] Implement `distanceMeters`, `bearingDegrees`, `relativeAngle` and `side`.
- [ ] Add XCTest cases from the plan's worked examples:
  - side of street: direction (1, 0), door at (30, −10) → `.right`; door at (30, 20) → `.left`
  - relative angle: heading 350°, target 10° → +20°

## 4. Server data with the stub (FE-11)

Files: `EntranceAPI/EntranceModels.swift`, `EntranceAPI/EntranceClient.swift`

- [ ] Call `StubEntranceClient().resolve(address:)` and check that `Resources/resolve.example.json` decodes. If decoding fails, the Swift models and the contract disagree; fix the model, not the JSON.
- [ ] Later: implement `LiveEntranceClient` against the running server, with on-phone caching.

## 5. Object detection (CV-8)

File: `Perception/VisionObjectDetector.swift`

- [ ] Add a Core ML detector to the target. Check the license first (ADR 0007): Ultralytics YOLO is AGPL-3.0, so prototype with it if you like, but plan to ship an Apache-2.0 model such as RF-DETR.
- [ ] Load it in `init()` as a `VNCoreMLModel`.
- [ ] Implement `detect(_:filter:orientation:)` with `VNCoreMLRequest` (`.scaleFill`) and `VNImageRequestHandler`, converting results with `Detection(from:)` and applying `filter`.
- [ ] In `PerceptionPipeline.processFrame`, drop low-confidence detections (start at `confidence > 0.4`), and only count a door once it appears in 5 of the last 8 frames.

## 6. Feedback (FE-4 to FE-6)

Files: `Feedback/FeedbackKit.swift`, `Services/Speaker.swift`

- [ ] Implement `Speaker.speak(_:)` with `AVSpeechUtterance`, and `stop()` with `stopSpeaking(at: .immediate)`. Set `prefersAssistiveTechnologySettings = true` so it uses the rider's VoiceOver voice.
- [ ] Move announcements out of `PerceptionPipeline` and into `FeedbackKit.emit(_:)` events.
- [ ] Add a **chatter guard**: don't repeat the same phrase within a few seconds.
- [ ] Add `BeaconChannel` (HRTF tone at the door) and `HapticsChannel` (AHAP patterns).

## 7. Trip state machine (FE-10)

File: `Session/NavigationSession.swift`

- [ ] Implement the transitions listed in the file header, driven by `update(position:heading:)`.
- [ ] Test by replaying a recorded GPS trace, not by walking.

## 8. Accessibility (QA-5)

- [ ] Every control has a label, a hint and the right trait. Test with VoiceOver on.
- [ ] Add an XCUITest target that runs `performAccessibilityAudit()` on every screen.

## Recommended order

1. Project setup and camera stream (you see pixels).
2. Location and geometry math (you see heading and get correct bearings).
3. Stub server data (the app knows where the door is).
4. Feedback: speech, then beacon and haptics (the app guides).
5. Session state machine (a full trip from a recorded trace).
6. Detection (the camera confirms the door).

## Not now

- ARKit tracking (FE-12) and text recognition for the building check (CV-9) come after the steps above.
- Sending images anywhere. Frames never leave the phone.
