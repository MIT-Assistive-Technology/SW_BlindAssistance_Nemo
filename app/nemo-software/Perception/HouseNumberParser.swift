//  HouseNumberParser.swift
//  nemo-software
//
//  Pulls a street or building number out of one OCR line. A line counts only
//  when it is itself a number ("77", "#12B", "123-125"), so a poster or a
//  storefront sentence is not read aloud as the address.
//

import Foundation

nonisolated enum HouseNumberParser {
  private static let pattern =
    #"^(?:#|no\.?\s*)?(\d{1,6}(?:\s*[-\u{2013}]\s*\d{1,6})?[A-Za-z]?)\.?$"#

  private static let expression: NSRegularExpression? = try? NSRegularExpression(
    pattern: pattern,
    options: [.caseInsensitive]
  )

  /// The number plaque in `text`, or nil when the line is not just a number.
  static func houseNumber(in text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let expression else { return nil }
    let range = NSRange(trimmed.startIndex..., in: trimmed)
    guard
      let match = expression.firstMatch(in: trimmed, range: range),
      match.numberOfRanges > 1,
      let tokenRange = Range(match.range(at: 1), in: trimmed)
    else { return nil }

    return trimmed[tokenRange]
      .replacingOccurrences(of: " ", with: "")
      .replacingOccurrences(of: "\u{2013}", with: "-")
  }
}
