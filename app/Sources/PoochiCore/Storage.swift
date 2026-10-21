import Foundation
import Security

public struct KeychainStore {
    private let service: String
    public init(service: String = "com.hoover2x.PoochiAnalytics") { self.service = service }
    public func save<T: Encodable>(_ value: T, account: String) throws {
        let data = try JSONEncoder().encode(value)
        let query = baseQuery(account: account)
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let status = SecItemAdd(item as CFDictionary, nil)
            guard status == errSecSuccess else { throw PoochiError.insecureStorage(status) }
        } else if updated != errSecSuccess { throw PoochiError.insecureStorage(updated) }
    }
    public func load<T: Decodable>(_ type: T.Type, account: String) throws -> T? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw PoochiError.insecureStorage(status) }
        return try JSONDecoder().decode(type, from: data)
    }
    public func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw PoochiError.insecureStorage(status) }
    }
    private func baseQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
}

public struct ArchiveStore {
    public let directory: URL
    public init(directory: URL? = nil) throws {
        if let directory { self.directory = directory }
        else {
            self.directory = try FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("PoochiAnalytics", isDirectory: true)
        }
    }
    private var file: URL { directory.appendingPathComponent("analytics.json") }
    public func save(_ archive: AnalyticsArchive) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(archive).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    public func load() throws -> AnalyticsArchive? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AnalyticsArchive.self, from: Data(contentsOf: file))
    }
    public func delete() throws {
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}
