import Combine
import Foundation

enum AuthMode: String, CaseIterable, Identifiable {
    case login
    case register

    var id: String { rawValue }
}

@MainActor
protocol AuthSubmitting: AnyObject {
    func login(email: String, password: String) async throws
    func register(
        email: String,
        password: String,
        displayName: String,
        timezone: String,
        language: AppLanguage
    ) async throws
}

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var mode: AuthMode = .login {
        didSet { clearErrors() }
    }
    @Published var email = ""
    @Published var password = ""
    @Published var displayName = ""
    @Published private(set) var language: AppLanguage
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var fieldErrors: [String: String] = [:]

    private let submitter: any AuthSubmitting

    init(
        submitter: any AuthSubmitting,
        language: AppLanguage = .deviceFallback()
    ) {
        self.submitter = submitter
        self.language = language
    }

    var copy: AuthCopy { AuthCopy(language: language) }

    func setLanguage(_ language: AppLanguage) {
        guard self.language != language else { return }
        self.language = language
        clearErrors()
    }

    func submit() async {
        guard !isLoading else { return }
        clearErrors()

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        validate(email: normalizedEmail, password: password, displayName: normalizedName)
        guard fieldErrors.isEmpty else {
            errorMessage = copy.checkFields
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            switch mode {
            case .login:
                try await submitter.login(email: normalizedEmail, password: password)
            case .register:
                try await submitter.register(
                    email: normalizedEmail,
                    password: password,
                    displayName: normalizedName,
                    timezone: TimeZone.current.identifier,
                    language: language
                )
            }
        } catch let error as APIError {
            apply(error)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = copy.serverUnavailable
        }
    }

    private func validate(email: String, password: String, displayName: String) {
        if email.isEmpty || !email.contains("@") || email.count > 320 {
            fieldErrors["email"] = copy.invalidEmail
        }
        if password.isEmpty {
            fieldErrors["password"] = copy.emptyPassword
        } else if mode == .register && !(8...200).contains(password.count) {
            fieldErrors["password"] = copy.invalidPasswordLength
        }
        if mode == .register {
            if displayName.isEmpty {
                fieldErrors["displayName"] = copy.emptyDisplayName
            } else if displayName.count > 120 {
                fieldErrors["displayName"] = copy.invalidDisplayNameLength
            }
        }
    }

    private func clearErrors() {
        errorMessage = nil
        fieldErrors = [:]
    }

    private func apply(_ error: APIError) {
        fieldErrors = error.fieldErrors.reduce(into: [String: String]()) { result, entry in
            switch entry.key {
            case "email": result[entry.key] = copy.checkEmail
            case "password": result[entry.key] = copy.checkPassword
            case "displayName": result[entry.key] = copy.checkDisplayName
            default: break
            }
        }

        switch (error.statusCode, error.code) {
        case (_, "authentication_failed"), (_, "unauthorized"):
            errorMessage = copy.authenticationFailed
        case (409, _):
            errorMessage = copy.accountExists
        case (_, "validation_error"):
            errorMessage = copy.checkFields
        default:
            errorMessage = copy.requestFailed
        }
    }
}
