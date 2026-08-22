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
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var fieldErrors: [String: String] = [:]

    private let submitter: any AuthSubmitting

    init(submitter: any AuthSubmitting) {
        self.submitter = submitter
    }

    func submit() async {
        guard !isLoading else { return }
        clearErrors()

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        validate(email: normalizedEmail, password: password, displayName: normalizedName)
        guard fieldErrors.isEmpty else {
            errorMessage = "Проверьте заполненные поля."
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            switch mode {
            case .login:
                try await submitter.login(email: normalizedEmail, password: password)
            case .register:
                let language: AppLanguage = Locale.preferredLanguages.first?.hasPrefix("ru") == true ? .ru : .en
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
            errorMessage = "Не удалось связаться с сервером. Попробуйте ещё раз."
        }
    }

    private func validate(email: String, password: String, displayName: String) {
        if email.isEmpty || !email.contains("@") || email.count > 320 {
            fieldErrors["email"] = "Введите корректный адрес электронной почты."
        }
        if password.isEmpty {
            fieldErrors["password"] = "Введите пароль."
        } else if mode == .register && !(8...200).contains(password.count) {
            fieldErrors["password"] = "Пароль должен содержать от 8 до 200 символов."
        }
        if mode == .register {
            if displayName.isEmpty {
                fieldErrors["displayName"] = "Введите имя."
            } else if displayName.count > 120 {
                fieldErrors["displayName"] = "Имя не должно превышать 120 символов."
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
            case "email": result[entry.key] = "Проверьте адрес электронной почты."
            case "password": result[entry.key] = "Проверьте пароль."
            case "displayName": result[entry.key] = "Проверьте имя."
            default: break
            }
        }

        switch (error.statusCode, error.code) {
        case (_, "authentication_failed"), (_, "unauthorized"):
            errorMessage = "Неверная электронная почта или пароль."
        case (409, _):
            errorMessage = "Аккаунт с такой электронной почтой уже существует."
        case (_, "validation_error"):
            errorMessage = "Проверьте заполненные поля."
        default:
            errorMessage = "Не удалось выполнить запрос. Попробуйте ещё раз."
        }
    }
}
