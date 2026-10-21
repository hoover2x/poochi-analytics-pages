import XCTest
@testable import PoochiCore

final class OAuthAndAnalyticsTests: XCTestCase {
    private let config = TikTokConfiguration(clientKey: "test-key", clientSecret: "test-secret")
    func testTikTokPKCEUsesHexSHA256() {
        let attempt = OAuthAttempt(state: "state", verifier: "abc")
        XCTAssertEqual(attempt.challenge, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
    func testFreshAttemptHasHighEntropyUnreservedVerifier() {
        let a = OAuthAttempt(), b = OAuthAttempt()
        XCTAssertEqual(a.verifier.count, 43)
        XCTAssertNotEqual(a.verifier, b.verifier)
        XCTAssertNotEqual(a.state, b.state)
        XCTAssertTrue(a.verifier.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-._~".contains($0)) })
    }
    func testAuthorizationContainsOnlyReadScopesAndNoSecret() throws {
        let url = try OAuthAttempt().authorizationURL(configuration: config)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(values["code_challenge_method"], "S256")
        XCTAssertEqual(values["redirect_uri"], TikTokConfiguration.defaultRedirect)
        XCTAssertEqual(Set(values["scope"]!.split(separator: ",").map(String.init)), Set(TikTokConfiguration.requestedScopes))
        XCTAssertNil(values["client_secret"])
        XCTAssertFalse(url.absoluteString.contains("test-secret"))
    }
    func testValidCallbackDecodesCodeOnce() throws {
        let attempt = OAuthAttempt(state: "safe-state", verifier: "verifier")
        let url = URL(string: config.redirectURI + "?state=safe-state&code=a%2Bb%25c")!
        XCTAssertEqual(try attempt.authorizationCode(from: url, redirectURI: config.redirectURI), "a+b%c")
    }
    func testForgedAndDuplicateStateAreRejected() {
        let attempt = OAuthAttempt(state: "expected", verifier: "verifier")
        for query in ["state=wrong&code=x", "state=expected&state=wrong&code=x", "code=x"] {
            XCTAssertThrowsError(try attempt.authorizationCode(from: URL(string: config.redirectURI + "?" + query)!, redirectURI: config.redirectURI)) {
                XCTAssertEqual($0 as? PoochiError, .stateMismatch)
            }
        }
    }
    func testWrongOriginPathPortAndDuplicateCodeAreRejected() {
        let attempt = OAuthAttempt(state: "expected", verifier: "verifier")
        for uri in ["http://127.0.0.1:9999/callback/", "http://localhost:8787/callback/", "http://127.0.0.1:8787/other/", "https://evil.example/callback/"] {
            XCTAssertThrowsError(try attempt.authorizationCode(from: URL(string: uri + "?state=expected&code=x")!, redirectURI: config.redirectURI))
        }
        XCTAssertThrowsError(try attempt.authorizationCode(from: URL(string: config.redirectURI + "?state=expected&code=a&code=b")!, redirectURI: config.redirectURI))
    }
    func testDeniedLoginRequiresValidState() {
        let attempt = OAuthAttempt(state: "expected", verifier: "verifier")
        XCTAssertThrowsError(try attempt.authorizationCode(from: URL(string: config.redirectURI + "?state=expected&error=access_denied")!, redirectURI: config.redirectURI)) {
            XCTAssertEqual($0 as? PoochiError, .accessDenied)
        }
    }
    func testConfigurationOnlyAllowsExplicitLoopbackPorts() {
        for uri in ["http://0.0.0.0:8787/callback/", "http://127.0.0.1/callback/", "http://127.0.0.1:80/callback/",
                    "http://127.0.0.1:8787/callback/?token=x", "https://example.com:8787/callback/", "http://user@127.0.0.1:8787/callback/"] {
            XCTAssertThrowsError(try TikTokConfiguration(clientKey: "a", clientSecret: "b", redirectURI: uri).validate())
        }
        XCTAssertNoThrow(try config.validate())
    }
    func testFormEncodingProtectsPlusPercentAndAmpersand() {
        let body = String(decoding: FormEncoding.encode(["secret": "a+b &c=%"]), as: UTF8.self)
        XCTAssertEqual(body, "secret=a%2Bb%20%26c%3D%25")
    }
    func testMissingStatsAndZeroViewsRemainUnavailable() {
        XCTAssertNil(TikTokVideo(id: "a", viewCount: 200).engagementRate)
        XCTAssertNil(TikTokVideo(id: "a", viewCount: 0, likeCount: 1, commentCount: 0, shareCount: 0).engagementRate)
        XCTAssertNil(VideoSummary(videos: []).views)
        XCTAssertNil(VideoSummary(videos: [.init(id: "a", viewCount: 20), .init(id: "b")]).views)
    }
    func testAggregateEngagementIsWeightedByViews() {
        let videos = [TikTokVideo(id: "a", viewCount: 100, likeCount: 10, commentCount: 0, shareCount: 0),
                      TikTokVideo(id: "b", viewCount: 900, likeCount: 9, commentCount: 0, shareCount: 0)]
        XCTAssertEqual(VideoSummary(videos: videos).engagementRate!, 0.019, accuracy: 0.000001)
    }
    func testCSVQuotesLinesAndNeutralizesFormulas() {
        XCTAssertEqual(CSVExport.escape("Hello, \"Poochi\"\nWorld"), "\"Hello, \"\"Poochi\"\"\nWorld\"")
        XCTAssertEqual(CSVExport.escape("  =HYPERLINK(\"bad\")"), "\"'  =HYPERLINK(\"\"bad\"\")\"")
        let csv = CSVExport.videos([.init(id: "a", title: "test")], observedAt: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(csv.contains("observed_at"))
        XCTAssertTrue(csv.contains("1970-01-01T00:00:00Z"))
    }
    func testSameDayObservationReplacesRatherThanInventsHistory() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = Date(timeIntervalSince1970: 1_700_006_400)
        var archive = AnalyticsArchive(profile: .init(openID: "a", followerCount: 10), videos: [])
        archive.recordObservation(at: start, calendar: calendar)
        archive.profile.followerCount = 12
        archive.recordObservation(at: start.addingTimeInterval(60), calendar: calendar)
        XCTAssertEqual(archive.observations.count, 1)
        XCTAssertEqual(archive.observations.first?.followers, 12)
        archive.recordObservation(at: start.addingTimeInterval(86400), calendar: calendar)
        XCTAssertEqual(archive.observations.count, 2)
    }
    func testTokenRefreshStartsBeforeExpiry() {
        let now = Date()
        let token = TikTokTokens(accessToken: "a", refreshToken: "b", openID: "c", scope: "user.info.basic",
                                accessExpiresAt: now.addingTimeInterval(119), refreshExpiresAt: now.addingTimeInterval(86400))
        XCTAssertTrue(token.needsRefresh(at: now))
    }
}
