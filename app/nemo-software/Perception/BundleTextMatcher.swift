//  BundleTextMatcher.swift
//  nemo-software
//
//  Matches a camera read to a string the entrance bundle already contains.
//  Jing's building check only speaks bundle text (`recognize.text`, the
//  entrance street, the building name). "Mass Ave" and "Massachusetts Avenue"
//  do not match; "Example Ave" and "Example Avenue" do.
//

import Foundation

nonisolated enum BundleTextMatcher {
  private static let suffixes: [String: String] = [
    "st": "street", "street": "street",
    "ave": "avenue", "avenue": "avenue", "av": "avenue",
    "rd": "road", "road": "road",
    "blvd": "boulevard", "boulevard": "boulevard",
    "dr": "drive", "drive": "drive",
    "ln": "lane", "lane": "lane",
    "way": "way",
    "pl": "place", "place": "place",
    "ct": "court", "court": "court",
    "ter": "terrace", "terrace": "terrace",
    "pkwy": "parkway", "parkway": "parkway",
    "hwy": "highway", "highway": "highway",
    "cir": "circle", "circle": "circle",
  ]

  /// The expected string `read` refers to, preserving the bundle's spelling.
  static func match(read: String, expected: [String]) -> String? {
    let key = canonical(read)
    guard !key.isEmpty else { return nil }
    return expected.first { canonical($0) == key }
  }

  static func canonical(_ text: String) -> String {
    let folded = text.lowercased()
      .replacingOccurrences(of: "[.'’]", with: "", options: .regularExpression)
    let parts = folded.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    guard !parts.isEmpty else { return "" }
    var words = parts
    if let last = words.last, let full = suffixes[last] {
      words[words.count - 1] = full
    }
    return words.joined(separator: " ")
  }
}
