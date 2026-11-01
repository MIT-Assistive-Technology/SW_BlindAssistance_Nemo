//  PilotBundleClient.swift
//  nemo-software
//
//  The pilot entrance bundles shipped inside the app (plan section 2: "served as static
//  files or shipped in the app"). Built by Minh's server/scripts/build_bundles.py from
//  OpenStreetMap, copied from the `pilot-bundles` branch into Resources/PilotBundles.
//
//  An address that isn't a pilot site is "not found", never the made-up example
//  bundle: guiding a rider to a fake door is worse than saying there's no data.
//  `StubEntranceClient` still returns the example, for tests and previews.
//

import Foundation

nonisolated public final class PilotBundleClient: EntranceClient {
  public struct Site: Decodable, Sendable {
    public let id: String
    public let address: String
    public let name: String?
  }

  private struct SiteList: Decodable {
    let sites: [Site]
  }

  public let sites: [Site]
  private let bundle: Bundle

  public init(bundle: Bundle = .main) {
    self.bundle = bundle
    if let url = bundle.url(forResource: "pilot_sites", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let list = try? JSONDecoder().decode(SiteList.self, from: data)
    {
      sites = list.sites
    } else {
      sites = []
    }
  }

  public func resolve(address: String) async throws -> ResolveResult {
    guard let site = Self.match(address, in: sites),
      let url = bundle.url(forResource: site.id, withExtension: "json")
    else {
      throw EntranceError.service(
        code: "NOT_FOUND", message: "Not a pilot site: \(address)", requestId: nil,
        httpStatus: 404)
    }
    let data = try Data(contentsOf: url)
    return try JSONDecoder.entrance.decode(ResolveResult.self, from: data)
  }

  /// "77 Mass Ave", "77 Massachusetts Avenue, Cambridge" and "Building 7" style lookups.
  /// House number plus the first word of the street wins; otherwise a name match.
  static func match(_ query: String, in sites: [Site]) -> Site? {
    let q = normalize(query)
    guard !q.isEmpty else { return nil }
    let qWords = q.split(separator: " ").map(String.init)

    for site in sites {
      let streetPart = normalize(String(site.address.split(separator: ",").first ?? ""))
      let words = streetPart.split(separator: " ").map(String.init)
      guard words.count >= 2, let number = words.first, number.first?.isNumber == true else {
        continue
      }
      if qWords.first == number, qWords.count >= 2, qWords[1] == words[1] { return site }
    }
    // Name match only for queries long enough to mean something ("student center").
    guard q.count >= 4 else { return nil }
    return sites.first { site in
      guard let name = site.name.map(normalize) else { return false }
      return name.contains(q) || q.contains(name)
    }
  }

  static func normalize(_ text: String) -> String {
    let lowered = text.lowercased()
      .replacingOccurrences(of: "[.'’]", with: "", options: .regularExpression)
    let short: [String: String] = [
      "massachusetts": "mass", "avenue": "ave", "av": "ave", "street": "st",
      "place": "pl", "drive": "dr", "road": "rd",
    ]
    return lowered
      .split { !$0.isLetter && !$0.isNumber }
      .map { short[String($0)] ?? String($0) }
      .joined(separator: " ")
  }
}
