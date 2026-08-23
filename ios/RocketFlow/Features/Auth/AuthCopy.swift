import Foundation

struct AuthCopy: Equatable, Sendable {
    let loginSubtitle: String
    let registerSubtitle: String
    let mode: String
    let login: String
    let register: String
    let displayName: String
    let displayNamePlaceholder: String
    let email: String
    let password: String
    let language: String
    let russian: String
    let english: String
    let submitLogin: String
    let submitRegister: String
    let done: String
    let errorAccessibilityPrefix: String

    let checkFields: String
    let invalidEmail: String
    let emptyPassword: String
    let invalidPasswordLength: String
    let emptyDisplayName: String
    let invalidDisplayNameLength: String
    let checkEmail: String
    let checkPassword: String
    let checkDisplayName: String
    let authenticationFailed: String
    let accountExists: String
    let serverUnavailable: String
    let requestFailed: String

    init(language: AppLanguage) {
        switch language {
        case .ru:
            loginSubtitle = "Войдите в своё пространство"
            registerSubtitle = "Создайте аккаунт"
            mode = "Режим авторизации"
            login = "Вход"
            register = "Регистрация"
            displayName = "Имя"
            displayNamePlaceholder = "Как к вам обращаться"
            email = "Электронная почта"
            password = "Пароль"
            self.language = "Язык"
            russian = "Русский"
            english = "English"
            submitLogin = "Войти"
            submitRegister = "Создать аккаунт"
            done = "Готово"
            errorAccessibilityPrefix = "Ошибка"
            checkFields = "Проверьте заполненные поля."
            invalidEmail = "Введите корректный адрес электронной почты."
            emptyPassword = "Введите пароль."
            invalidPasswordLength = "Пароль должен содержать от 8 до 200 символов."
            emptyDisplayName = "Введите имя."
            invalidDisplayNameLength = "Имя не должно превышать 120 символов."
            checkEmail = "Проверьте адрес электронной почты."
            checkPassword = "Проверьте пароль."
            checkDisplayName = "Проверьте имя."
            authenticationFailed = "Неверная электронная почта или пароль."
            accountExists = "Аккаунт с такой электронной почтой уже существует."
            serverUnavailable = "Не удалось связаться с сервером. Попробуйте ещё раз."
            requestFailed = "Не удалось выполнить запрос. Попробуйте ещё раз."
        case .en:
            loginSubtitle = "Sign in to your workspace"
            registerSubtitle = "Create an account"
            mode = "Authentication mode"
            login = "Sign in"
            register = "Register"
            displayName = "Name"
            displayNamePlaceholder = "How should we address you?"
            email = "Email"
            password = "Password"
            self.language = "Language"
            russian = "Russian"
            english = "English"
            submitLogin = "Sign in"
            submitRegister = "Create account"
            done = "Done"
            errorAccessibilityPrefix = "Error"
            checkFields = "Check the highlighted fields."
            invalidEmail = "Enter a valid email address."
            emptyPassword = "Enter your password."
            invalidPasswordLength = "Password must be between 8 and 200 characters."
            emptyDisplayName = "Enter your name."
            invalidDisplayNameLength = "Name must not exceed 120 characters."
            checkEmail = "Check the email address."
            checkPassword = "Check the password."
            checkDisplayName = "Check the name."
            authenticationFailed = "Incorrect email or password."
            accountExists = "An account with this email already exists."
            serverUnavailable = "Could not reach the server. Try again."
            requestFailed = "Could not complete the request. Try again."
        }
    }

    func languageName(_ language: AppLanguage) -> String {
        switch language {
        case .ru: russian
        case .en: english
        }
    }
}
