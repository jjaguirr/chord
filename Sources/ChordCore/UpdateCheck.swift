/// A release version: one to four dot-separated decimal numbers with an
/// optional leading `v` (`0.2.0`, `v0.2.0`, `1`). Pre-release suffixes, build
/// metadata, empty parts, and signs are not release versions and do not parse.
public struct ReleaseVersion: Comparable, Sendable, CustomStringConvertible {
  public let components: [Int]

  public init?(_ text: String) {
    let body = text.hasPrefix("v") ? text.dropFirst() : Substring(text)
    let parts = body.split(separator: ".", omittingEmptySubsequences: false)
    guard (1...4).contains(parts.count) else { return nil }
    var values: [Int] = []
    for part in parts {
      guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }),
        let value = Int(part)
      else { return nil }
      values.append(value)
    }
    components = values
  }

  /// Missing trailing components count as zero, so `0.2` equals `0.2.0`.
  public static func == (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
    !(lhs < rhs) && !(rhs < lhs)
  }

  public static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
    let count = max(lhs.components.count, rhs.components.count)
    for index in 0..<count {
      let left = index < lhs.components.count ? lhs.components[index] : 0
      let right = index < rhs.components.count ? rhs.components[index] : 0
      if left != right { return left < right }
    }
    return false
  }

  public var description: String {
    components.map(String.init).joined(separator: ".")
  }
}

public enum UpdateVerdict: Equatable, Sendable {
  case upToDate
  case available
  /// One side is not a release version. The offending text is carried for the log line.
  case unparseable(String)
}

public enum UpdateCheck {
  /// Compares the running bundle version with the latest release tag.
  public static func evaluate(current: String, latestTag: String) -> UpdateVerdict {
    guard let installed = ReleaseVersion(current) else { return .unparseable(current) }
    guard let latest = ReleaseVersion(latestTag) else { return .unparseable(latestTag) }
    return latest > installed ? .available : .upToDate
  }
}
public enum UpdateSchedule {
  private static let backgroundCheckInterval: Double = 86_400

  public static func isBackgroundCheckDue(lastAttemptAt: Double?, now: Double) -> Bool {
    guard let lastAttemptAt else { return true }
    return now < lastAttemptAt || now - lastAttemptAt >= backgroundCheckInterval
  }
}
