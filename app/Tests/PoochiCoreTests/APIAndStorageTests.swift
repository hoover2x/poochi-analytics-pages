import XCTest
@testable import PoochiCore

private actor StubTransport: HTTPTransport {
    var requests: [URLRequest] = []
    let body: Data
    let status: Int
    init(_ body: String, status: Int = 200) { self.body = Data(body.utf8); self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    func last() -> URLRequest? { requests.last }
}

final class APIAndStorageTests: XCTestCase {
    private var token: TikTokTokens {
        .init(accessToken: "test-access", refreshToken: "test-refresh", openID: "account-1", scope: "user.info.basic,video.list",
              accessExpiresAt: Date().addingTimeInterval(3600), refreshExpiresAt: Date().addingTimeInterval(86400))
    }
    func testProfileRequestsOnlyGrantedFields() async throws {
        let transport = StubTransport(#"{"data":{"user":{"open_id":"account-1","display_name":"Poochi"}},"error":{"code":"ok"}}"#)
        let profile = try await TikTokClient(transport: transport).profile(tokens: token)
        XCTAssertNil(profile.followerCount)
        let request = await transport.last()
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer test-access")
        XCTAssertFalse(request!.url!.absoluteString.contains("follower_count"))
        XCTAssertFalse(request!.url!.absoluteString.contains("username"))
    }
    func testProfileForAnotherAccountIsRejected() async {
        let transport = StubTransport(#"{"data":{"user":{"open_id":"other-account"}},"error":{"code":"ok"}}"#)
        do { _ = try await TikTokClient(transport: transport).profile(tokens: token); XCTFail("Mixed account data") }
        catch { XCTAssertEqual(error as? PoochiError, .malformedResponse) }
    }
    func testVideoPaginationUsesIntegerCursorAndTwentyItems() async throws {
        let transport = StubTransport(#"{"data":{"videos":[{"id":"v","view_count":123}],"cursor":1700000000123,"has_more":true},"error":{"code":"ok"}}"#)
        let page = try await TikTokClient(transport: transport).videos(tokens: token, cursor: 1700000000999)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.videos.first?.viewCount, 123)
        let request = await transport.last()
        XCTAssertEqual(request?.httpMethod, "POST")
        let body = try JSONDecoder().decode([String: Int64].self, from: request!.httpBody!)
        XCTAssertEqual(body["max_count"], 20)
        XCTAssertEqual(body["cursor"], 1700000000999)
    }
    func testRepeatedCursorCannotCausePaginationLoop() async {
        let transport = StubTransport(#"{"data":{"videos":[],"cursor":123,"has_more":true},"error":{"code":"ok"}}"#)
        do { _ = try await TikTokClient(transport: transport).videos(tokens: token, cursor: 123); XCTFail("Repeated cursor accepted") }
        catch { XCTAssertEqual(error as? PoochiError, .malformedResponse) }
    }
    func testOAuthExchangeIncludesVerifierAndPreservesReplacementTokens() async throws {
        let transport = StubTransport(#"{"access_token":"new-access","refresh_token":"rotated-refresh","open_id":"account-1","scope":"user.info.basic,video.list","expires_in":86400,"refresh_expires_in":31536000,"token_type":"Bearer"}"#)
        let config = TikTokConfiguration(clientKey: "key", clientSecret: "secret")
        let result = try await TikTokClient(transport: transport).exchange(code: "a+b", attempt: .init(state: "x", verifier: "verifier"), configuration: config, now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(result.refreshToken, "rotated-refresh")
        XCTAssertEqual(result.accessExpiresAt, Date(timeIntervalSince1970: 86400))
        let request = await transport.last()
        let body = String(decoding: request!.httpBody!, as: UTF8.self)
        XCTAssertTrue(body.contains("code=a%2Bb"))
        XCTAssertTrue(body.contains("code_verifier=verifier"))
        XCTAssertFalse(request!.url!.absoluteString.contains("secret"))
    }
    func testRateLimitIsActionableAndDoesNotLeakResponse() async {
        let transport = StubTransport("PRIVATE TOKEN SHOULD NOT APPEAR", status: 429)
        do { _ = try await TikTokClient(transport: transport).profile(tokens: token); XCTFail("Rate limit accepted") }
        catch { XCTAssertEqual(error as? PoochiError, .rateLimited); XCTAssertFalse(error.localizedDescription.contains("PRIVATE")) }
    }
    func testAPIErrorWithEmptyDataIsRecognized() async {
        let transport = StubTransport(#"{"data":{},"error":{"code":"access_token_invalid"}}"#)
        do { _ = try await TikTokClient(transport: transport).profile(tokens: token); XCTFail("Expired token accepted") }
        catch { XCTAssertEqual(error as? PoochiError, .unauthorized) }
    }
    func testArchiveRoundTripPermissionsAndDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ArchiveStore(directory: directory)
        XCTAssertNil(try store.load())
        try store.save(SampleData.archive(now: Date(timeIntervalSince1970: 1700000000)))
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.profile.openID, "sample-account")
        XCTAssertEqual(loaded.videos.count, 8)
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("analytics.json").path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        try store.delete()
        XCTAssertNil(try store.load())
    }
}
