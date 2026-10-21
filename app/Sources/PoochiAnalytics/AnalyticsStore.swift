import AppKit
import SwiftUI
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
import PoochiCore
#endif

@MainActor
final class AnalyticsStore: ObservableObject {
    @Published var archive: AnalyticsArchive?
    @Published var isSample = false
    @Published var isBusy = false
    @Published var isLoggingIn = false
    @Published var isConnected = false
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var clientKey = UserDefaults.standard.string(forKey: "tiktok.clientKey") ?? ""
    @Published var redirectURI = UserDefaults.standard.string(forKey: "tiktok.redirectURI") ?? TikTokConfiguration.defaultRedirect
    @Published var scopeNames: Set<String> = []
    private let keychain = KeychainStore()
    private let api = TikTokClient()
    private let login = LoopbackLogin()
    private var tokens: TikTokTokens?
    private var disk: ArchiveStore?
    private var liveArchive: AnalyticsArchive?

    init() {
        disk = try? ArchiveStore()
        if ProcessInfo.processInfo.arguments.contains("--sample") {
            archive = SampleData.archive(); isSample = true
            return
        }
        do {
            disk = try ArchiveStore()
            tokens = try keychain.load(TikTokTokens.self, account: "tokens")
            archive = try disk?.load()
            if let tokens, archive?.profile.openID != tokens.openID { archive = nil }
            isConnected = tokens != nil
            scopeNames = tokens?.scopes ?? []
        } catch { errorMessage = "Saved data could not be loaded. \(error.localizedDescription)" }
    }

    var hasConfiguration: Bool { !clientKey.isEmpty }
    func savedSecret() -> String { (try? keychain.load(String.self, account: "clientSecret")) ?? "" }
    private func configuration() throws -> TikTokConfiguration {
        let config = TikTokConfiguration(clientKey: clientKey,
            clientSecret: try keychain.load(String.self, account: "clientSecret") ?? "", redirectURI: redirectURI)
        try config.validate()
        return config
    }
    func saveConfiguration(clientKey: String, secret: String, redirectURI: String) {
        guard !isConnected, !isBusy else { errorMessage = "Disconnect before changing the app credentials."; return }
        do {
            let cleanKey = clientKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanURI = redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
            let actualSecret = secret.isEmpty ? try keychain.load(String.self, account: "clientSecret") ?? "" : secret
            try TikTokConfiguration(clientKey: cleanKey, clientSecret: actualSecret, redirectURI: cleanURI).validate()
            try keychain.save(actualSecret, account: "clientSecret")
            self.clientKey = cleanKey; self.redirectURI = cleanURI
            UserDefaults.standard.set(cleanKey, forKey: "tiktok.clientKey")
            UserDefaults.standard.set(cleanURI, forKey: "tiktok.redirectURI")
            errorMessage = nil; notice = "TikTok settings saved securely. You can connect your account."
        } catch { errorMessage = error.localizedDescription }
    }

    func showSample() {
        guard !isBusy else { return }
        if !isSample { liveArchive = archive }
        archive = SampleData.archive(); isSample = true; errorMessage = nil
    }
    func leaveSample() { archive = liveArchive; liveArchive = nil; isSample = false }

    func connect() async {
        guard !isBusy else { return }
        if isSample { leaveSample() }
        isBusy = true; isLoggingIn = true; errorMessage = nil; notice = nil
        defer { isBusy = false; isLoggingIn = false }
        do {
            let config = try configuration()
            let attempt = OAuthAttempt()
            let code = try await login.authorize(attempt: attempt, configuration: config)
            isLoggingIn = false
            let newTokens = try await api.exchange(code: code, attempt: attempt, configuration: config)
            try keychain.save(newTokens, account: "tokens")
            tokens = newTokens; scopeNames = newTokens.scopes; isConnected = true
            if archive?.profile.openID != newTokens.openID {
                archive = nil
                try disk?.delete()
            }
            try await fetchFirstPage(using: newTokens)
        } catch { report(error) }
    }

    func cancelLogin() { login.cancel() }

    private func validTokens(forceRefresh: Bool = false) async throws -> TikTokTokens {
        guard let current = tokens else { throw PoochiError.unauthorized }
        if !forceRefresh && !current.needsRefresh() { return current }
        let refreshed = try await api.refresh(tokens: current, configuration: configuration())
        // Persist the replacement refresh token before making another request.
        try keychain.save(refreshed, account: "tokens")
        tokens = refreshed; scopeNames = refreshed.scopes
        return refreshed
    }

    func refresh() async {
        guard !isBusy, !isSample else { return }
        isBusy = true; errorMessage = nil; notice = nil
        defer { isBusy = false }
        do {
            let current = try await validTokens()
            do { try await fetchFirstPage(using: current) }
            catch PoochiError.unauthorized { try await fetchFirstPage(using: validTokens(forceRefresh: true)) }
        } catch { report(error) }
    }

    private func fetchFirstPage(using tokens: TikTokTokens) async throws {
        let profile = try await api.profile(tokens: tokens)
        let page = try await api.videos(tokens: tokens)
        let old = archive?.profile.openID == profile.openID ? archive?.observations ?? [] : []
        var fresh = AnalyticsArchive(profile: profile, videos: deduplicate(page.videos), observations: old,
            cursor: page.cursor, hasMore: page.hasMore)
        fresh.recordObservation(at: fresh.updatedAt)
        try disk?.save(fresh)
        archive = fresh
        notice = "Updated from TikTok. \(page.videos.count) videos loaded."
    }

    func loadMore() async {
        guard !isBusy, !isSample, let old = archive, old.hasMore, let cursor = old.cursor else { return }
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        do {
            let current = try await validTokens()
            let page: VideoPage
            do { page = try await api.videos(tokens: current, cursor: cursor) }
            catch PoochiError.unauthorized { page = try await api.videos(tokens: validTokens(forceRefresh: true), cursor: cursor) }
            var updated = old
            updated.videos = deduplicate(old.videos + page.videos)
            updated.cursor = page.cursor; updated.hasMore = page.hasMore
            try disk?.save(updated); archive = updated
        } catch { report(error) }
    }

    func disconnect() async {
        guard !isBusy, !isSample else { return }
        isBusy = true; errorMessage = nil; notice = nil
        defer { isBusy = false }
        do {
            if let tokens {
                do { try await api.revoke(tokens: tokens, configuration: configuration()) }
                catch PoochiError.unauthorized { /* Already revoked or expired. */ }
            }
            try clearLocalData()
            notice = "Disconnected from TikTok. Saved account data has been deleted."
        } catch { report(error) }
    }

    func forgetLocalData() {
        guard !isBusy else { return }
        do {
            if isSample { leaveSample() }
            try clearLocalData()
            notice = "Local account data removed. If TikTok was offline, revoke access in TikTok's app permissions as well."
        } catch { report(error) }
    }
    private func clearLocalData() throws {
        try keychain.delete(account: "tokens")
        tokens = nil; isConnected = false; scopeNames = []
        try disk?.delete()
        archive = nil; liveArchive = nil
    }

    func exportCSV(_ videos: [TikTokVideo]) {
        guard let archive else { return }
        let panel = NSSavePanel()
        panel.title = "Export video analytics"
        panel.nameFieldStringValue = isSample ? "Poochi-SAMPLE-videos.csv" : "Poochi-videos.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try CSVExport.videos(videos, observedAt: archive.updatedAt).write(to: url, atomically: true, encoding: .utf8) }
        catch { errorMessage = "The export could not be saved. \(error.localizedDescription)" }
    }
    private func deduplicate(_ videos: [TikTokVideo]) -> [TikTokVideo] {
        var seen = Set<String>()
        return videos.filter { seen.insert($0.id).inserted }
    }
    private func report(_ error: Error) {
        if error as? PoochiError == .unauthorized { notice = "Reconnect to restore access. Your saved analytics are still available." }
        errorMessage = error.localizedDescription
    }
}
