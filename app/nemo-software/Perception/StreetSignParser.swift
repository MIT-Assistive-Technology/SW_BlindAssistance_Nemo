//  StreetSignParser.swift
//  nemo-software
//
//  A line counts as a street-name sign only when it is a name plus a street
//  suffix ("Massachusetts Ave", "Main St"). Storefront sentences and house
//  numbers are left to the number reader.
//

import Foundation

nonisolated enum StreetSignParser {
  private static let pattern =
    #"^(?:(?:north|south|east|west|n|s|e|w|ne|nw|se|sw)\.?\s+)?[A-Za-z0-9][A-Za-z0-9.'’\-]{0,24}(?:\s+[A-Za-z0-9][A-Za-z0-9.'’\-]{0,24}){0,5}\s+(?:street|st|avenue|ave|av|road|rd|boulevard|blvd|drive|dr|lane|ln|way|place|pl|court|ct|terrace|ter|parkway|pkwy|highway|hwy|circle|cir)\.?$"#

  private static let expression: NSRegularExpression? = try? NSRegularExpression(
    pattern: pattern,
    options: [.caseInsensitive]
  )

  /// The street name in `text`, or nil when the line is not a street sign.
  static func streetName(in text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let expression else { return nil }
    let range = NSRange(trimmed.startIndex..., in: trimmed)
    guard expression.firstMatch(in: trimmed, range: range) != nil else { return nil }
    return trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
  }
}
