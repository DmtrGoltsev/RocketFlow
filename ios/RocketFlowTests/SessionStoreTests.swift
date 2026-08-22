import Foundation
import Security
import XCTest
@testable import RocketFlow

final class SessionStoreTests: XCTestCase {
    func testInMemoryStoreCompareAndSwapProtectsNewSession() async throws {
        let old = fixtureSession(id: UUID(), accessToken: "old-access", refreshToken: "old-refresh")
        let new = fixtureSession(id: UUID(), accessToken: "new-access", refreshToken: "new-refresh")
        let store = InMemorySessionStore(session: old)

        try await store.save(new)
        let oldReplace = try await store.replace(old, matching: old.id)
        let oldClear = try await store.clear(matching: old.id)
        let stored = try await store.load()

        XCTAssertFalse(oldReplace)
        XCTAssertFalse(oldClear)
        XCTAssertEqual(stored, new)
    }

    func testKeychainContractUsesDeviceOnlyAfterFirstUnlock() {
        let attributes = KeychainSessionStore.addAttributes(
            service: "com.rocketflow.test",
            account: "session"
        )

        XCTAssertEqual(attributes[kSecClass] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(
            attributes[kSecAttrAccessible] as? String,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
        XCTAssertNil(attributes[kSecAttrSynchronizable])
        XCTAssertNil(attributes[kSecAttrAccessGroup])
    }

    func testSessionEnvelopeRoundTripsUserTokensAndMetadata() throws {
        let session = fixtureSession(id: UUID(), accessToken: "access", refreshToken: "refresh")

        let data = try WireJSON.encoder().encode(session)
        let decoded = try WireJSON.decoder().decode(SessionSnapshot.self, from: data)

        XCTAssertEqual(decoded, session)
    }
}

private func fixtureSession(
    id: UUID,
    accessToken: String,
    refreshToken: String
) -> SessionSnapshot {
    SessionSnapshot(
        id: id,
        user: UserDTO(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            email: "user@example.com",
            displayName: "User",
            timezone: "Europe/Moscow",
            language: .ru,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ),
        tokens: TokensDTO(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        ),
        storedAt: Date(timeIntervalSince1970: 1_700_000_100)
    )
}
