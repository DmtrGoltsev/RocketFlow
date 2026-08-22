import Combine
import Foundation

@MainActor
final class AppStore: ObservableObject, AuthSubmitting {
    enum State: Equatable {
        case launching
        case signedOut
        case authenticated(UserDTO)
        case offline(UserDTO)
    }

    @Published private(set) var state: State = .launching
    private let authSession: AuthSession
    private var didRestore = false

    init(authSession: AuthSession) {
        self.authSession = authSession
    }

    func restoreIfNeeded() async {
        guard !didRestore else { return }
        didRestore = true
        switch await authSession.restore() {
        case .signedOut:
            state = .signedOut
        case let .authenticated(user):
            state = .authenticated(user)
        case let .offline(user):
            state = .offline(user)
        }
    }

    func login(email: String, password: String) async throws {
        let user = try await authSession.login(email: email, password: password)
        state = .authenticated(user)
    }

    func register(
        email: String,
        password: String,
        displayName: String,
        timezone: String,
        language: AppLanguage
    ) async throws {
        let user = try await authSession.register(
            email: email,
            password: password,
            displayName: displayName,
            timezone: timezone,
            language: language
        )
        state = .authenticated(user)
    }

    func logout() async {
        await authSession.logout()
        state = .signedOut
    }
}
