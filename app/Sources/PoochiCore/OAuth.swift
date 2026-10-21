import Foundation
import CryptoKit

public enum PoochiError: LocalizedError, Equatable {
    case configuration, invalidCallback, stateMismatch, accessDenied, missingCode
    case unauthorized, rateLimited, http(Int), api(String), malformedResponse, insecureStorage(Int32)
    case listener(String), cancelled
    public var errorDescription: String? {
        switch self {
        case .configuration: return "Enter your TikTok client key and secret in Settings. Use an HTTP redirect on 127.0.0.1 with a port and a callback path."
        case .invalidCallback: return "The login response did not match this app's callback address. Start the connection again."
        case .stateMismatch: return "The login response could not be verified. Start the connection again."
        case .accessDenied: return "TikTok access was declined. You can connect again whenever you're ready."
        case .missingCode: return "TikTok did not return an authorization code. Try connecting again."
        case .unauthorized: return "Your TikTok connection has expired or was revoked. Please reconnect."
        case .rateLimited: return "TikTok is limiting requests. Wait a minute, then refresh."
        case .http(let code): return "TikTok returned HTTP \(code). Try again later."
        case .api(let code): return "TikTok could not complete the request (\(code)). Check the app's sandbox access and permissions."
        case .malformedResponse: return "TikTok returned an incomplete response. Your last saved data is still available."
        case .insecureStorage: return "macOS could not access the secure Keychain. Check Keychain access and try again."
        case .listener(let message): return message
        case .cancelled: return "The connection was cancelled."
        }
    }
}

public struct TikTokConfiguration: Sendable {
    public static let requestedScopes = ["user.info.basic", "user.info.profile", "user.info.stats", "video.list"]
    public static let defaultRedirect = "http://127.0.0.1:8787/callback/"
    public var clientKey: String
    public var clientSecret: String
    public var redirectURI: String
    public init(clientKey: String, clientSecret: String, redirectURI: String = Self.defaultRedirect) {
        self.clientKey = clientKey; self.clientSecret = clientSecret; self.redirectURI = redirectURI
    }
    public func validate() throws {
        guard !clientKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !clientSecret.isEmpty, let url = URLComponents(string: redirectURI),
              url.scheme == "http", url.host == "127.0.0.1", let port = url.port,
              (1024...65535).contains(port), !url.path.isEmpty, url.query == nil,
              url.fragment == nil, url.user == nil, url.password == nil else { throw PoochiError.configuration }
    }
}

public struct OAuthAttempt: Sendable {
    public let state: String
    public let verifier: String
    public init() {
        state = Self.randomString(); verifier = Self.randomString()
    }
    public init(state: String, verifier: String) { self.state = state; self.verifier = verifier }
    private static func randomString() -> String {
        var random = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &random) }
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    // TikTok Desktop requires a hexadecimal SHA-256 challenge, not base64url.
    public var challenge: String { SHA256.hash(data: Data(verifier.utf8)).map { String(format: "%02x", $0) }.joined() }
    public func authorizationURL(configuration: TikTokConfiguration) throws -> URL {
        try configuration.validate()
        var components = URLComponents(string: "https://www.tiktok.com/v2/auth/authorize/")!
        components.queryItems = [
            .init(name: "client_key", value: configuration.clientKey), .init(name: "response_type", value: "code"),
            .init(name: "scope", value: TikTokConfiguration.requestedScopes.joined(separator: ",")),
            .init(name: "redirect_uri", value: configuration.redirectURI), .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256")
        ]
        guard let url = components.url else { throw PoochiError.configuration }
        return url
    }
    public func authorizationCode(from callback: URL, redirectURI: String) throws -> String {
        guard let actual = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let expected = URLComponents(string: redirectURI), actual.scheme == expected.scheme,
              actual.host == expected.host, actual.port == expected.port, actual.path == expected.path,
              actual.user == nil, actual.password == nil, actual.fragment == nil else { throw PoochiError.invalidCallback }
        let items = actual.queryItems ?? []
        func single(_ name: String) -> String? {
            let values = items.filter { $0.name == name }
            return values.count == 1 ? values.first?.value : nil
        }
        guard let returnedState = single("state"), Self.constantTimeEqual(state, returnedState) else { throw PoochiError.stateMismatch }
        if items.contains(where: { $0.name == "error" }) { throw PoochiError.accessDenied }
        guard let code = single("code"), !code.isEmpty else { throw PoochiError.missingCode }
        return code
    }
    private static func constantTimeEqual(_ left: String, _ right: String) -> Bool {
        let a = Array(left.utf8), b = Array(right.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

public struct TikTokTokens: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var openID: String
    public var scope: String
    public var accessExpiresAt: Date
    public var refreshExpiresAt: Date
    public var scopes: Set<String> { Set(scope.split(separator: ",").map(String.init)) }
    public init(accessToken: String, refreshToken: String, openID: String, scope: String,
                accessExpiresAt: Date, refreshExpiresAt: Date) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.openID = openID
        self.scope = scope; self.accessExpiresAt = accessExpiresAt; self.refreshExpiresAt = refreshExpiresAt
    }
    public func needsRefresh(at date: Date = Date()) -> Bool { accessExpiresAt <= date.addingTimeInterval(120) }
}

public enum FormEncoding {
    public static func encode(_ values: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let body = values.keys.sorted().map { key in
            let value = values[key]!
            return key.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" + value.addingPercentEncoding(withAllowedCharacters: allowed)!
        }.joined(separator: "&")
        return Data(body.utf8)
    }
}
