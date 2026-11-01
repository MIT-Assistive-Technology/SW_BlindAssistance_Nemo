//  RideViewModelTests.swift
//  nemo-softwareTests
//
//  The wiring between the sensors, the bundle and FeedbackKit: load a destination
//  (FE-11), feed the location updates a ride would produce, and check the app says the
//  right thing when the car stops (FE-13).
//
//  CoreLocation is driven through the delegate methods directly, so no car is involved.
//

import CoreLocation
import XCTest

@testable import nemo_software

@MainActor
final class RideViewModelTests: XCTestCase {

  private final class RecordingSpeaker: SpeechOutput {
    var spoken: [String] = []
    func speak(_ text: String) { spoken.append(text) }
    func stop() {}
  }

  private var speaker: RecordingSpeaker!
  private var location: LocationService!
  private var viewModel: RideViewModel!
  private var store: BundleStore!
  private let address = "77 Example Avenue"

  override func setUp() async throws {
    try await super.setUp()
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("RideViewModelTests-\(UUID().uuidString)", isDirectory: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

    speaker = RecordingSpeaker()
    store = BundleStore(directory: directory)
    // A fresh manager, so the app's shared service isn't disturbed.
    location = LocationService(locationManager: CLLocationManager())
    // These tests replay a whole ride in milliseconds, so the chatter guard would
    // swallow prompts that are minutes apart in reality. It has its own test.
    let channel = SpeechChannel(speaker: speaker)
    channel.repeatGuard = 0
    viewModel = RideViewModel(
      location: location,
      feedback: FeedbackKit(channels: [channel]),
      client: CachingEntranceClient(upstream: StubEntranceClient(), store: store))
    viewModel.address = address
  }

  /// A location as a moving (or stopped) car would report it, on the example bundle's
  /// centerline. Timestamps are "seconds ago" against the real clock, because the stop
  /// and staleness rules are measured against `Date()` in the app.
  private func carLocation(
    secondsAgo: TimeInterval, course: Double, speed: Double, lat: Double = 42.3592,
    lon: Double = -71.0928
  ) -> CLLocation {
    CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
      altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
      course: course, courseAccuracy: 5, speed: speed, speedAccuracy: 1,
      timestamp: Date().addingTimeInterval(-secondsAgo))
  }

  private func send(_ locations: [CLLocation]) {
    for location in locations {
      self.location.locationManager(CLLocationManager(), didUpdateLocations: [location])
    }
  }

  // MARK: The destination (FE-11)

  func testLoadingSpeaksTheBriefAndSavesTheBundle() async {
    await viewModel.load()
    XCTAssertEqual(viewModel.bundle?.destinationId, "dst_example")
    XCTAssertEqual(viewModel.status, "Main entrance")
    XCTAssertNotNil(store.cached(for: address))
    XCTAssertNotNil(viewModel.cacheNote)
    // The brief names the band, the street and the door facts, and is spoken after the
    // "looking up" acknowledgement.
    XCTAssertEqual(
      speaker.spoken.last,
      Phrases.destinationBrief(
        DestinationBrief(
          band: "main", entranceStreet: "Example Avenue", streetSideDescription: "west",
          housenumber: "77", door: "hinged", automaticDoor: "button", stepCount: 3)))
    XCTAssertEqual(viewModel.briefText, speaker.spoken.last)
  }

  func testASecondLoadWorksFromThePhonesCopy() async {
    await viewModel.load()
    // Same store, no upstream: this is the walk after drop-off, with no signal.
    let offline = RideViewModel(
      location: location,
      feedback: FeedbackKit(channels: [SpeechChannel(speaker: speaker)]),
      client: CachingEntranceClient(upstream: NoSignalClient(), store: store))
    offline.address = address
    await offline.load()
    XCTAssertEqual(offline.bundle?.destinationId, "dst_example")
    XCTAssertEqual(offline.status, "Using the copy saved on this phone.")
  }

  func testLoadingAnUnknownAddressWithNoCacheSaysSoOutLoud() async {
    let failing = RideViewModel(
      location: location,
      feedback: FeedbackKit(channels: [SpeechChannel(speaker: speaker)]),
      client: CachingEntranceClient(upstream: NoSignalClient(), store: store))
    failing.address = "somewhere new"
    await failing.load()
    XCTAssertNil(failing.bundle)
    // A failure left on screen is a failure a blind rider never learns about.
    XCTAssertEqual(failing.status, Phrases.lookupFailed(.other))
    XCTAssertTrue(speaker.spoken.contains(Phrases.lookupFailed(.other)), "said: \(speaker.spoken)")
  }

  func testEveryLoadIsAcknowledgedOutLoud() async {
    await viewModel.load()
    // The lookup can take seconds; the rider hears that the tap registered.
    XCTAssertEqual(speaker.spoken.first, Phrases.lookingUpEntrance)
  }

  func testRepeatingTheBriefIsNeverSwallowed() async {
    await viewModel.load()
    let spokenBefore = speaker.spoken.count
    viewModel.speakBrief(force: true)
    XCTAssertEqual(speaker.spoken.count, spokenBefore + 1)
  }

  func testAskingWithNoDestinationSaysSoInsteadOfAnUnanswerableQuestion() {
    // No bundle loaded: "which side of the street are you on?" would be meaningless.
    viewModel.confirmOutOfCar()
    XCTAssertNil(viewModel.sideAnswer)
    XCTAssertTrue(
      speaker.spoken.contains(Phrases.noDestinationLoaded), "said: \(speaker.spoken)")
  }

  // MARK: The ride (FE-13)

  func testAStopOnlyAsksAndNeverDecidesOnItsOwn() async {
    await viewModel.load()
    viewModel.startRide()
    XCTAssertTrue(location.isTrackingRide)

    // Driving south along the centerline, then stopping.
    send([
      carLocation(secondsAgo: 60, course: 182, speed: 12),
      carLocation(secondsAgo: 55, course: 182, speed: 12),
      carLocation(secondsAgo: 50, course: 182, speed: 0.1),
    ])
    XCTAssertTrue(viewModel.isAskingIfOutOfCar)
    XCTAssertTrue(speaker.spoken.contains { $0.hasPrefix("It looks like the car has stopped") }, "said: \(speaker.spoken)")
    // Nothing is decided and no instruction is given until the rider says they're out:
    // this stop could be a red light with the car still in traffic.
    XCTAssertNil(viewModel.sideAnswer)
    XCTAssertFalse(viewModel.isOutOfCar)
    XCTAssertFalse(speaker.spoken.contains(Phrases.exitCurbSide), "said: \(speaker.spoken)")
  }

  func testTheSameStopIsOnlyRaisedOnce() async {
    await viewModel.load()
    viewModel.startRide()
    send([
      carLocation(secondsAgo: 100, course: 182, speed: 12),
      carLocation(secondsAgo: 90, course: 182, speed: 0.1),
    ])
    viewModel.stillInCar()
    // More slow samples at the same stop: no nagging.
    send([
      carLocation(secondsAgo: 85, course: 182, speed: 0.1),
      carLocation(secondsAgo: 80, course: 182, speed: 0.2),
    ])
    XCTAssertFalse(viewModel.isAskingIfOutOfCar)
    XCTAssertEqual(speaker.spoken.filter { $0.hasPrefix("It looks like the car has stopped") }.count, 1)
  }

  func testARedLightDoesNotBurnTheRealDropOff() async {
    await viewModel.load()
    viewModel.startRide()
    // Stopped at a light...
    send([
      carLocation(secondsAgo: 200, course: 182, speed: 12),
      carLocation(secondsAgo: 190, course: 182, speed: 0.1),
    ])
    XCTAssertTrue(viewModel.isAskingIfOutOfCar)
    viewModel.stillInCar()
    // ...then driving on, and stopping again at the real drop-off.
    send([
      carLocation(secondsAgo: 100, course: 182, speed: 11),
      carLocation(secondsAgo: 60, course: 182, speed: 12),
      carLocation(secondsAgo: 50, course: 182, speed: 0.1),
    ])
    XCTAssertTrue(viewModel.isAskingIfOutOfCar, "the second stop must be raised too")
    XCTAssertEqual(speaker.spoken.filter { $0.hasPrefix("It looks like the car has stopped") }.count, 2)

    viewModel.confirmOutOfCar()
    XCTAssertEqual(viewModel.sideAnswer, .sameSide)
  }

  func testTheRiderConfirmingTheDropOffDecidesTheSide() async {
    await viewModel.load()
    viewModel.startRide()
    send([
      carLocation(secondsAgo: 60, course: 182, speed: 12),
      carLocation(secondsAgo: 55, course: 182, speed: 12),
      carLocation(secondsAgo: 50, course: 182, speed: 0.1),
    ])
    viewModel.confirmOutOfCar()
    XCTAssertTrue(viewModel.isOutOfCar)
    XCTAssertFalse(viewModel.isAskingIfOutOfCar)
    XCTAssertEqual(viewModel.sideAnswer, .sameSide)
    XCTAssertTrue(
      speaker.spoken.contains { $0.hasPrefix("Your entrance should be on this side") },
      "said: \(speaker.spoken)")
    // Background location stops with the ride.
    XCTAssertFalse(location.isTrackingRide)
  }

  func testTheRiderCanSayTheyAreOutBeforeThePhoneNotices() async {
    await viewModel.load()
    viewModel.startRide()
    // Only one driving sample: no stop detected yet, but the rider is already on the
    // pavement and says so.
    send([carLocation(secondsAgo: 10, course: 2, speed: 12)])
    XCTAssertFalse(viewModel.isAskingIfOutOfCar)
    viewModel.confirmOutOfCar()
    XCTAssertEqual(viewModel.sideAnswer, .acrossStreet)
    XCTAssertTrue(
      speaker.spoken.contains { $0.hasPrefix("Your entrance is across the street") },
      "said: \(speaker.spoken)")
  }

  func testAnUntrackedRideAsksTheRiderInstead() async {
    await viewModel.load()
    // No "I'm in the car", so there is no course to read.
    viewModel.confirmOutOfCar()
    XCTAssertEqual(viewModel.sideAnswer, .unknown(.noCarTrack))
    // The question names the street, which is what makes it answerable without sight.
    XCTAssertTrue(
      speaker.spoken.contains {
        $0.hasSuffix(Phrases.askSideOfStreet) && $0.contains("west side of Example Avenue")
      }, "said: \(speaker.spoken)")
    // And the screen says exactly what was spoken, with the reason kept separate.
    XCTAssertEqual(viewModel.sideText, speaker.spoken.last)
    XCTAssertEqual(viewModel.sideReason, "noCarTrack")
    XCTAssertTrue(viewModel.needsSideAnswerFromRider)
  }

  func testRepeatSaysTheAnswerAgain() async {
    await viewModel.load()
    viewModel.confirmOutOfCar()
    let spokenBefore = speaker.spoken.count
    viewModel.repeatSideAnswer()
    XCTAssertEqual(speaker.spoken.count, spokenBefore + 1)
    XCTAssertEqual(speaker.spoken.last, speaker.spoken[spokenBefore - 1])
  }

  func testStartingARideWithLocationOffDoesNotClaimToBeTracking() async {
    await viewModel.load()
    viewModel.startRide()
    // The Simulator and a fresh install are both "not determined": iOS is showing its
    // own prompt, so the app must not announce success it can't deliver.
    if !location.isAuthorized {
      XCTAssertFalse(
        speaker.spoken.contains(Phrases.rideTrackingStarted), "said: \(speaker.spoken)")
    }
  }

  func testTheRidersAnswerOverridesTheGuess() async {
    await viewModel.load()
    viewModel.checkSideOfStreet()
    XCTAssertFalse(viewModel.sideAnswer?.isKnown ?? true)

    viewModel.answerSideQuestion(sameSide: false)
    XCTAssertEqual(viewModel.sideAnswer, .acrossStreet)
    XCTAssertEqual(viewModel.riderSaysSameSide, false)
  }

  func testStartingAFreshRideClearsTheOldAnswer() async {
    await viewModel.load()
    viewModel.answerSideQuestion(sameSide: true)
    viewModel.startRide()
    XCTAssertNil(viewModel.sideAnswer)
    XCTAssertNil(viewModel.riderSaysSameSide)
    XCTAssertFalse(viewModel.isOutOfCar)
    XCTAssertFalse(viewModel.isAskingIfOutOfCar)
    XCTAssertTrue(location.carTrack.samples.isEmpty)
    viewModel.stopRide()
    XCTAssertFalse(location.isTrackingRide)
  }

  func testTheQuestionIsAskedAgainAtEveryStopUntilTheRiderConfirms() async {
    await viewModel.load()
    viewModel.startRide()
    // Three stops in traffic, each with a crawl between them. Every one is raised once.
    send([
      carLocation(secondsAgo: 300, course: 182, speed: 12),
      carLocation(secondsAgo: 290, course: 182, speed: 0.1),
    ])
    XCTAssertTrue(viewModel.isAskingIfOutOfCar)
    viewModel.stillInCar()

    send([
      carLocation(secondsAgo: 250, course: 182, speed: 2),  // crawling, not driving
      carLocation(secondsAgo: 240, course: 182, speed: 0.1),
    ])
    XCTAssertTrue(viewModel.isAskingIfOutOfCar, "a crawl then a stop is a new stop")
    viewModel.stillInCar()

    send([
      carLocation(secondsAgo: 200, course: 182, speed: 11),
      carLocation(secondsAgo: 190, course: 182, speed: 0.1),
    ])
    XCTAssertTrue(viewModel.isAskingIfOutOfCar)
    XCTAssertEqual(
      speaker.spoken.filter { $0.hasPrefix("It looks like the car has stopped") }.count, 3)

    // Only the rider ends the cycle.
    viewModel.confirmOutOfCar()
    XCTAssertTrue(viewModel.isOutOfCar)
    XCTAssertFalse(viewModel.isAskingIfOutOfCar)
  }

  func testTheQuestionSaysHowFarTheEntranceIs() async {
    await viewModel.load()
    viewModel.startRide()
    send([
      carLocation(secondsAgo: 60, course: 182, speed: 12),
      carLocation(secondsAgo: 50, course: 182, speed: 0.1),
    ])
    // The car is about 15 m from the example bundle's door, which is how a rider who
    // can't look out of the window judges whether this is the drop-off.
    XCTAssertTrue(
      speaker.spoken.contains { $0.contains("feet from your entrance") },
      "said: \(speaker.spoken)")
    XCTAssertEqual(viewModel.dropOffPrompt, speaker.spoken.last)
  }

  func testAStopFarFromTheDestinationIsNotRaised() async {
    await viewModel.load()
    viewModel.startRide()
    // Stopped over a kilometre away: a light on the way, not the drop-off.
    send([
      carLocation(secondsAgo: 60, course: 182, speed: 12, lat: 42.3700),
      carLocation(secondsAgo: 50, course: 182, speed: 0.1, lat: 42.3700),
    ])
    XCTAssertFalse(viewModel.isAskingIfOutOfCar)
    XCTAssertFalse(
      speaker.spoken.contains { $0.hasPrefix("It looks like the car has stopped") },
      "said: \(speaker.spoken)")
    // But the rider can still say they're out, wherever the driver stopped.
    viewModel.confirmOutOfCar()
    XCTAssertTrue(viewModel.isOutOfCar)
    XCTAssertNotNil(viewModel.sideAnswer)
  }

  func testLocationUpdatesFeedTheSnapshotAndTheTrackSummary() async {
    viewModel.startRide()
    send([carLocation(secondsAgo: 5, course: 182, speed: 12)])
    XCTAssertEqual(location.currentSnapshot.coordinate?.latitude ?? 0, 42.3592, accuracy: 1e-6)
    XCTAssertEqual(location.currentSnapshot.courseDegrees ?? -1, 182, accuracy: 1e-6)
    XCTAssertEqual(location.currentSnapshot.speedMetersPerSecond ?? -1, 12, accuracy: 1e-6)
    XCTAssertTrue(viewModel.trackSummary.contains("course 182°"), viewModel.trackSummary)
  }
}

private final class NoSignalClient: EntranceClient {
  func resolve(address: String) async throws -> ResolveResult {
    throw URLError(.notConnectedToInternet)
  }
}
