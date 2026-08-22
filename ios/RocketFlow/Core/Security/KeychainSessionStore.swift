import Foundation
import Security

enum KeychainSessionStoreError: Error, Equatable, Sendable {
    case unexpectedStatus(OSStatus)
    case invalidData
}

actor KeychainSessionStore: SessionStore {
    private let service: String
    private let account: String

    init(
        service: String = "com.rocketflow.companion.ios.session",
        account: String = "authenticated-session"
    ) {
        self.service = service
        self.account = account
    }

    func load() throws -> SessionSnapshot? {
        try loadStoredSession()
    }

    func save(_ session: SessionSnapshot) throws {
        try saveStoredSession(session)
    }

    func replace(_ session: SessionSnapshot, matching sessionID: UUID) throws -> Bool {
        guard try loadStoredSession()?.id == sessionID else { return false }
        try saveStoredSession(session)
        return true
    }

    func clear(matching sessionID: UUID?) throws -> Bool {
        if let sessionID, try loadStoredSession()?.id != sessionID {
            return false
        }

        let status = SecItemDelete(matchQuery() as CFDictionary)
        switch status {
        case errSecSuccess: return true
        case errSecItemNotFound: return false
        default: throw KeychainSessionStoreError.unexpectedStatus(status)
        }
    }

    nonisolated static func addAttributes(service: String, account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
    }

    private func matchQuery() -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }

    private func loadStoredSession() throws -> SessionSnapshot? {
        var query = matchQuery()
        query[kSecReturnData] = kCFBooleanTrue
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecItemNotFound:
            return nil
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainSessionStoreError.invalidData
            }
            do {
                return try WireJSON.decoder().decode(SessionSnapshot.self, from: data)
            } catch {
                throw KeychainSessionStoreError.invalidData
            }
        default:
            throw KeychainSessionStoreError.unexpectedStatus(status)
        }
    }

    private func saveStoredSession(_ session: SessionSnapshot) throws {
        let data = try WireJSON.encoder().encode(session)
        var attributes = Self.addAttributes(service: service, account: account)
        attributes[kSecValueData] = data

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecSuccess {
            return
        }
        guard status == errSecDuplicateItem else {
            throw KeychainSessionStoreError.unexpectedStatus(status)
        }

        let update: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(matchQuery() as CFDictionary, update as CFDictionary)
        guard updateStatus == errSecSuccess else {
            throw KeychainSessionStoreError.unexpectedStatus(updateStatus)
        }
    }
}
