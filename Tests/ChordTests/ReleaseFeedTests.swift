import Foundation
import Testing
@testable import Chord

@Suite("GitHub release feed parsing (offline)")
struct ReleaseFeedTests {
    private static func release(
        tag: String = "v0.2.0", url: String = "https://github.com/jjaguirr/chord/releases/tag/v0.2.0",
        prerelease: Bool = false, draft: Bool = false
    ) -> Data {
        Data("""
        {
          "url": "https://api.github.com/repos/jjaguirr/chord/releases/1",
          "id": 1,
          "tag_name": "\(tag)",
          "name": "Chord \(tag)",
          "draft": \(draft),
          "prerelease": \(prerelease),
          "html_url": "\(url)",
          "body": "notes",
          "assets": []
        }
        """.utf8)
    }

    @Test("a stable release yields its tag and https github.com page")
    func parsesStableRelease() throws {
        let parsed = try ReleaseFeed.parse(Self.release())
        #expect(parsed.tag == "v0.2.0")
        #expect(parsed.pageURL.absoluteString == "https://github.com/jjaguirr/chord/releases/tag/v0.2.0")
    }

    @Test("extra fields in the response are ignored")
    func ignoresUnknownFields() throws {
        let body = Data(#"{"tag_name":"v1.0.0","html_url":"https://github.com/a/b","prerelease":false,"draft":false,"published_at":"2025-01-01T00:00:00Z","author":{"login":"x"}}"#.utf8)
        #expect(try ReleaseFeed.parse(body).tag == "v1.0.0")
    }

    @Test("a pre-release or draft is never offered as the latest stable release")
    func rejectsPrereleaseAndDraft() {
        #expect(throws: UpdateCheckError.stableReleaseMissing) {
            try ReleaseFeed.parse(Self.release(prerelease: true))
        }
        #expect(throws: UpdateCheckError.stableReleaseMissing) {
            try ReleaseFeed.parse(Self.release(draft: true))
        }
    }

    @Test("a page URL that is not https github.com is refused")
    func rejectsUntrustedPageURL() {
        for url in [
            "http://github.com/jjaguirr/chord/releases/tag/v0.2.0",
            "https://example.com/jjaguirr/chord/releases/tag/v0.2.0",
            "https://github.com.evil.example/x",
            "javascript:alert(1)",
            "",
        ] {
            #expect(throws: UpdateCheckError.untrustedPageURL) {
                try ReleaseFeed.parse(Self.release(url: url))
            }
        }
    }

    @Test("malformed bodies are errors, not guesses")
    func rejectsMalformedBodies() {
        let bodies = [
            "",
            "not json",
            "[]",
            "null",
            #"{"message":"Not Found","documentation_url":"https://docs.github.com"}"#,
            #"{"tag_name":"","html_url":"https://github.com/a/b","prerelease":false,"draft":false}"#,
            #"{"tag_name":7,"html_url":"https://github.com/a/b","prerelease":false,"draft":false}"#,
            #"{"tag_name":"v1.0.0","html_url":"https://github.com/a/b","draft":false}"#,
            #"{"tag_name":"v1.0.0","html_url":"https://github.com/a/b","prerelease":"no","draft":false}"#,
        ]
        for body in bodies {
            #expect(throws: UpdateCheckError.malformedResponse) {
                try ReleaseFeed.parse(Data(body.utf8))
            }
        }
    }

    @Test("a build without a bundle version fails without touching the network")
    func buildWithoutVersionFailsWithoutNetwork() async {
        let result = await UpdateChecker.run(currentVersion: nil)
        #expect(result == .failed("this build has no bundle version; check from the packaged app"))
    }
}
