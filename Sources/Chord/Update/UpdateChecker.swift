import ChordCore
import Foundation

/// The fields of a GitHub release that the update check reads.
struct LatestRelease: Equatable, Sendable {
    let tag: String
    /// The release page on github.com: release notes and the download.
    let pageURL: URL
}

enum UpdateCheckError: LocalizedError, Equatable, Sendable {
    case malformedResponse
    case stableReleaseMissing
    case untrustedPageURL
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .malformedResponse: "GitHub's response was not a release"
        case .stableReleaseMissing: "the latest release is a pre-release or draft"
        case .untrustedPageURL: "the release page is not an https github.com URL"
        case .httpStatus(let code): "GitHub returned HTTP \(code)"
        }
    }
}

enum ReleaseFeed {
    static let latestURL = URL(string: "https://api.github.com/repos/jjaguirr/chord/releases/latest")!

    private struct Payload: Decodable {
        let tagName: String
        let htmlURL: String
        let prerelease: Bool
        let draft: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case prerelease
            case draft
        }
    }

    /// Parses a `GET /releases/latest` body. Any missing field, wrong type, pre-release,
    /// draft, or non-https / non-github.com page URL is an error; nothing is guessed.
    static func parse(_ data: Data) throws -> LatestRelease {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw UpdateCheckError.malformedResponse
        }
        guard !payload.tagName.isEmpty else { throw UpdateCheckError.malformedResponse }
        guard !payload.prerelease, !payload.draft else { throw UpdateCheckError.stableReleaseMissing }
        guard let url = URL(string: payload.htmlURL), url.scheme == "https", url.host() == "github.com"
        else { throw UpdateCheckError.untrustedPageURL }
        return LatestRelease(tag: payload.tagName, pageURL: url)
    }
}

enum UpdateCheckResult: Equatable, Sendable {
    case upToDate
    case available(LatestRelease)
    case failed(String)
}

enum UpdateChecker {
    /// One GET to the GitHub Releases API, no identifiers, cookies, or caching. Never throws:
    /// every failure is a `.failed` result the caller can log or show.
    static func run(currentVersion: String?) async -> UpdateCheckResult {
        guard let currentVersion else {
            return .failed("this build has no bundle version; check from the packaged app")
        }
        do {
            let release = try await fetchLatest(currentVersion: currentVersion)
            switch UpdateCheck.evaluate(current: currentVersion, latestTag: release.tag) {
            case .upToDate: return .upToDate
            case .available: return .available(release)
            case .unparseable(let text): return .failed("'\(text)' is not a release version")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func fetchLatest(currentVersion: String) async throws -> LatestRelease {
        var request = URLRequest(
            url: ReleaseFeed.latestURL, cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub requires a User-Agent. It carries the app name and version and nothing else.
        request.setValue("Chord/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateCheckError.httpStatus(http.statusCode)
        }
        return try ReleaseFeed.parse(data)
    }
}
