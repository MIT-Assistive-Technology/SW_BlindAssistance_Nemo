import Foundation
import XCTest

@testable import CarToCurbLogic

/// The contract example, read from the repo (app/Tests/CarToCurbLogicTests -> repo root).
enum Fixtures {
  static var exampleURL: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // CarToCurbLogicTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // app
      .deletingLastPathComponent()  // repo root
      .appendingPathComponent("contract/resolve.example.json")
  }

  static func example() throws -> ResolveResult {
    try JSONDecoder.entrance.decode(ResolveResult.self, from: Data(contentsOf: exampleURL))
  }
}
