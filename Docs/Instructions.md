# Nemo Getting Started: Detect, Speak, and Locate

This scaffold gives an AT club team a starting iOS app. The goal is minimal but usable:

1. Show the live camera feed.
2. Detect objects with a CoreML model.
3. Speak the names of detected objects.
4. Record GPS + heading alongside each detection.

Later phases can send captured images to a server and align them with Google Maps / Street View, but those are not part of this first pass.

## 0. Project Setup

Before running, add permission strings to `Info.plist`. If the project uses the auto-generated `Info.plist`, add them in the target's **Info** tab or as build settings (`INFOPLIST_KEY_NSCameraUsageDescription`, etc.).

- [ ] `NSCameraUsageDescription` — why the camera is needed.
- [ ] `NSLocationWhenInUseUsageDescription` — why GPS is needed.
- [ ] (Optional) `NSLocationAlwaysAndWhenInUseUsageDescription` if you ever need background location.

## 1. Camera Stream

File: `FramePublishers/CameraFrameProvider.swift`

- [ ] Request camera permission with `AVCaptureDevice.requestAccess(for: .video)` before configuring.
- [ ] Implement `setupSession()`:
  - `captureSession.beginConfiguration()`
  - Add `AVCaptureDeviceInput` for the back camera chosen by `bestCaptureDevice()`.
  - Add `videoOutput`, set `alwaysDiscardsLateVideoFrames = true`.
  - `captureSession.commitConfiguration()`
  - Set `self` as `videoOutput` delegate on `cameraQueue`.
- [ ] Implement `captureOutput(_:didOutput:from:)`:
  - Extract `sampleBuffer.imageBuffer`.
  - Forward it to `delegate?.processFrame(_:buffer:)` on the main actor.

File: `Views/CameraView.swift`

- [ ] Replace the black background with a live camera preview. The easiest path is an `AVCaptureVideoPreviewLayer` wrapped in `UIViewRepresentable`.

## 2. GPS + Heading

File: `Location/LocationService.swift`

- [ ] Set `locationManager.desiredAccuracy = kCLLocationAccuracyBest`.
- [ ] Call `requestWhenInUseAuthorization()`.
- [ ] Start updates: `startUpdatingLocation()` and, if available, `startUpdatingHeading()`.
- [ ] In `locationManager(_:didUpdateLocations:)`, store the latest `CLLocation` coordinate, accuracy, and timestamp in `currentSnapshot`.
- [ ] In `locationManager(_:didUpdateHeading:)`, store the heading in `currentSnapshot`.
- [ ] In `stop()`, stop both updates.
- [ ] Handle `locationManager(_:didFailWithError:)` and show a permission-denied state in the UI.

## 3. Object Detection

File: `Perception/VisionObjectDetector.swift`

- [ ] Add a CoreML object-detection model (e.g. YOLOv8/YOLO11 converted with `coremltools`) to the Xcode target.
- [ ] Load the model in `init()`: `private let mlModel = try? VNCoreMLModel(for: MyModel().model)`.
- [ ] Implement `detect(_:filter:orientation:)`:
  - Create `VNCoreMLRequest(model: mlModel)` with `imageCropAndScaleOption = .scaleFill`.
  - Run it with `VNImageRequestHandler(cvPixelBuffer:orientation:)`.
  - Cast `request.results` to `[VNRecognizedObjectObservation]`.
  - Convert each to `Detection` with the existing `Detection(from:)` helper.
  - Apply the `filter` closure.
- [ ] In `PerceptionPipeline.processFrame`, change the filter to drop low-confidence detections, e.g. `detection.confidence > 0.4`.

## 4. Speak Detections

File: `Services/Speaker.swift`

- [ ] In `speak(_:)`, create an `AVSpeechUtterance`, set a voice, stop any current speech, and call `synthesizer.speak(utterance)`.
- [ ] In `stop()`, call `synthesizer.stopSpeaking(at: .immediate)`.

File: `Services/PerceptionPipeline.swift`

- [ ] Add a "chatter guard" so the same object isn't announced every frame. Ideas:
  - Track the last spoken label and only speak again after it changes or after a few seconds.
  - Or speak a short summary once per second instead of every frame.
- [ ] Speak a friendly phrase like `"I see a \(label)"` for the top detection.

## 5. UI Polish

File: `Views/StatusOverlayView.swift`

- [ ] Show the list of detected object labels.
- [ ] Show the current GPS coordinate and heading.
- [ ] Add a permission-denied message if camera or location access is missing.

File: `Views/CameraView.swift`

- [ ] Add a toggle to turn speech on/off.
- [ ] Add a button to copy the latest GPS coordinate to the clipboard.

## Recommended Order

1. Camera stream (you see pixels).
2. Location (you see GPS/heading updating).
3. Detection (you see object labels).
4. Speech (the app talks).
5. UI polish and permission handling.

## Phase 2 (not required now)

- Capture the current `CVPixelBuffer` or `CMSampleBuffer` as a JPEG.
- Send the image + GPS + heading + detected labels to a backend.
- Use the GPS/heading to align with Google Maps / Street View.
