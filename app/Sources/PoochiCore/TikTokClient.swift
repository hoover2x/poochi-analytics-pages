import Foundation

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public final class TikTokTransport: NSObject, HTTPTransport, URLSessionTaskDelegate, @unchecked Sendable {
    public override init() { super.init() }
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw PoochiError.malformedResponse }
        return (data, response)
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward authorization headers or token request bodies to redirects.
        completionHandler(nil)
    }
}

public struct TikTokClient: Sendable {
    private let transport: any HTTPTransport
    public init(transport: any HTTPTransport = TikTokTransport()) { self.transport = transport }

    public func exchange(code: String, attempt: OAuthAttempt, configuration: TikTokConfiguration,
                         now: Date = Date()) async throws -> TikTokTokens {
        try configuration.validate()
        return try await tokenRequest([
            "client_key": configuration.clientKey, "client_secret": configuration.clientSecret,
            "grant_type": "authorization_code", "code": code, "code_verifier": attempt.verifier,
            "redirect_uri": configuration.redirectURI
        ], now: now)
    }

    public func refresh(tokens: TikTokTokens, configuration: TikTokConfiguration,
                        now: Date = Date()) async throws -> TikTokTokens {
        guard tokens.refreshExpiresAt > now else { throw PoochiError.unauthorized }
        let refreshed = try await tokenRequest([
            "client_key": configuration.clientKey, "client_secret": configuration.clientSecret,
            "grant_type": "refresh_token", "refresh_token": tokens.refreshToken
        ], now: now)
        guard refreshed.openID == tokens.openID else { throw PoochiError.malformedResponse }
        return refreshed
    }

    public func revoke(tokens: TikTokTokens, configuration: TikTokConfiguration) async throws {
        let request = formRequest(path: "oauth/revoke/", values: [
            "client_key": configuration.clientKey, "client_secret": configuration.clientSecret,
            "token": tokens.accessToken
        ])
        let (data, response) = try await transport.send(request)
        try check(data: data, response: response)
        if let error = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data), error.error != nil {
            throw PoochiError.api(safeCode(error.error ?? "revoke_failed"))
        }
    }

    public func profile(tokens: TikTokTokens) async throws -> TikTokProfile {
        var fields = ["open_id", "display_name", "avatar_url"]
        if tokens.scopes.contains("user.info.profile") { fields += ["username", "bio_description", "profile_deep_link"] }
        if tokens.scopes.contains("user.info.stats") { fields += ["follower_count", "following_count", "likes_count", "video_count"] }
        let request = apiRequest(path: "user/info/", fields: fields, token: tokens.accessToken)
        let response: UserData = try await api(request)
        guard response.user.openID == tokens.openID else { throw PoochiError.malformedResponse }
        return response.user
    }

    public func videos(tokens: TikTokTokens, cursor: Int64? = nil) async throws -> VideoPage {
        guard tokens.scopes.contains("video.list") else { return VideoPage(videos: []) }
        let fields = ["id", "create_time", "title", "video_description", "cover_image_url", "share_url",
                      "duration", "view_count", "like_count", "comment_count", "share_count"]
        var request = apiRequest(path: "video/list/", fields: fields, token: tokens.accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Int64] = ["max_count": 20]
        if let cursor { body["cursor"] = cursor }
        request.httpBody = try JSONEncoder().encode(body)
        let page: VideoPage = try await api(request)
        guard !page.hasMore || (page.cursor != nil && page.cursor != cursor) else { throw PoochiError.malformedResponse }
        return page
    }

    private func apiRequest(path: String, fields: [String], token: String) -> URLRequest {
        var url = URLComponents(string: "https://open.tiktokapis.com/v2/\(path)")!
        url.queryItems = [.init(name: "fields", value: fields.joined(separator: ","))]
        var request = URLRequest(url: url.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        return request
    }
    private func formRequest(path: String, values: [String: String]) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://open.tiktokapis.com/v2/\(path)")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.httpBody = FormEncoding.encode(values)
        return request
    }
    private func tokenRequest(_ values: [String: String], now: Date) async throws -> TikTokTokens {
        let (data, response) = try await transport.send(formRequest(path: "oauth/token/", values: values))
        try check(data: data, response: response)
        if let failure = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data), let code = failure.error {
            if ["invalid_grant", "invalid_token"].contains(code) { throw PoochiError.unauthorized }
            throw PoochiError.api(safeCode(code))
        }
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: data),
              !token.accessToken.isEmpty, !token.refreshToken.isEmpty, !token.openID.isEmpty,
              token.expiresIn > 0, token.refreshExpiresIn > 0,
              token.scope.split(separator: ",").contains("user.info.basic") else { throw PoochiError.malformedResponse }
        return .init(accessToken: token.accessToken, refreshToken: token.refreshToken, openID: token.openID,
                     scope: token.scope, accessExpiresAt: now.addingTimeInterval(token.expiresIn),
                     refreshExpiresAt: now.addingTimeInterval(token.refreshExpiresIn))
    }
    private func api<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await transport.send(request)
        try check(data: data, response: response)
        if let error = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?.error, error.code != "ok" {
            if ["access_token_invalid", "access_token_expired", "invalid_token"].contains(error.code) { throw PoochiError.unauthorized }
            if error.code == "rate_limit_exceeded" { throw PoochiError.rateLimited }
            throw PoochiError.api(safeCode(error.code))
        }
        guard let envelope = try? JSONDecoder().decode(APIEnvelope<T>.self, from: data) else { throw PoochiError.malformedResponse }
        guard let result = envelope.data else { throw PoochiError.malformedResponse }
        return result
    }
    private func check(data: Data, response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300: break
        case 401: throw PoochiError.unauthorized
        case 429: throw PoochiError.rateLimited
        default: throw PoochiError.http(response.statusCode)
        }
    }
    private func safeCode(_ code: String) -> String {
        // Never echo arbitrary server text, URLs, codes, secrets, or request bodies.
        let known = ["invalid_request", "invalid_client", "invalid_scope", "scope_not_authorized", "scope_permission_missed",
                     "scope_permission_mismatch", "permission_denied", "server_error", "invalid_grant", "revoke_failed"]
        return known.contains(code) ? code : "request_failed"
    }
}

private struct UserData: Decodable { var user: TikTokProfile }
private struct APIEnvelope<T: Decodable>: Decodable { var data: T?; var error: APIErrorBody? }
private struct APIErrorBody: Decodable { var code: String }
private struct APIErrorEnvelope: Decodable { var error: APIErrorBody? }
private struct OAuthErrorResponse: Decodable { var error: String? }
private struct TokenResponse: Decodable {
    var accessToken: String; var refreshToken: String; var openID: String; var scope: String
    var expiresIn: TimeInterval; var refreshExpiresIn: TimeInterval
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", refreshToken = "refresh_token", openID = "open_id", scope
        case expiresIn = "expires_in", refreshExpiresIn = "refresh_expires_in"
    }
}
