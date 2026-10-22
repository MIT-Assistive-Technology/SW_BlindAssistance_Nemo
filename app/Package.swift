// swift-tools-version: 5.10
// Pure-Swift guidance logic (nemo-software/Logic), built and tested on its own so it runs on
// Linux in CI and Docker. The iOS app compiles the same files directly, with no import.
import PackageDescription

let package = Package(
  name: "CarToCurbLogic",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [
    .library(name: "CarToCurbLogic", targets: ["CarToCurbLogic"])
  ],
  targets: [
    .target(name: "CarToCurbLogic", path: "nemo-software/Logic"),
    .testTarget(
      name: "CarToCurbLogicTests",
      dependencies: ["CarToCurbLogic"],
      path: "Tests/CarToCurbLogicTests"
    ),
  ]
)
