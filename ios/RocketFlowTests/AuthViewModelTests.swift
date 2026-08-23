import Foundation
import XCTest
@testable import RocketFlow

@MainActor
private final class AuthSubmitterSpy: AuthSubmitting {
    var loginCalls: [(String, String)] = []
    var registrationLanguages: [AppLanguage] = []
    var error: Error?

    func login(email: String, password: String) async throws {
        loginCalls.append((email, password))
        if let error { throw error }
    }

    func register(
        email: String,
        password: String,
        displayName: String,
        timezone: String,
        language: AppLanguage
    ) async throws {
        registrationLanguages.append(language)
        if let error { throw error }
    }
}

final class AuthViewModelTests: XCTestCase {
    @MainActor
    func testLoginValidationDoesNotSubmitInvalidFields() async {
        let submitter = AuthSubmitterSpy()
        let model = AuthViewModel(submitter: submitter, language: .ru)

        await model.submit()

        XCTAssertEqual(model.fieldErrors["email"], "Введите корректный адрес электронной почты.")
        XCTAssertEqual(model.fieldErrors["password"], "Введите пароль.")
        XCTAssertEqual(submitter.loginCalls.count, 0)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testRegistrationValidationAndSuccessState() async {
        let submitter = AuthSubmitterSpy()
        let model = AuthViewModel(submitter: submitter, language: .ru)
        model.setLanguage(.en)
        model.mode = .register
        model.email = " USER@EXAMPLE.COM "
        model.password = "password1"
        model.displayName = " User "

        await model.submit()

        XCTAssertEqual(submitter.registrationLanguages, [.en])
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.fieldErrors.isEmpty)
        XCTAssertFalse(model.isLoading)
    }

    func testRussianAndEnglishAccessibilityCopyDescribesCurrentPickerSelection() {
        let russian = AuthCopy(language: .ru)
        XCTAssertEqual(russian.mode, "Режим авторизации")
        XCTAssertEqual(russian.language, "Язык")
        XCTAssertEqual(russian.languageName(.ru), "Русский")
        XCTAssertEqual(russian.languageName(.en), "English")
        XCTAssertEqual(russian.errorAccessibilityPrefix, "Ошибка")
        XCTAssertEqual(russian.submitLogin, "Войти")

        let english = AuthCopy(language: .en)
        XCTAssertEqual(english.mode, "Authentication mode")
        XCTAssertEqual(english.language, "Language")
        XCTAssertEqual(english.languageName(.ru), "Russian")
        XCTAssertEqual(english.languageName(.en), "English")
        XCTAssertEqual(english.errorAccessibilityPrefix, "Error")
        XCTAssertEqual(english.submitRegister, "Create account")
    }

    @MainActor
    func testServerFieldErrorsAreExposedToControls() async {
        let submitter = AuthSubmitterSpy()
        submitter.error = APIError(
            statusCode: 422,
            code: "validation_error",
            message: "Invalid request",
            details: [.init(field: "email", message: "Already used")],
            traceID: "trace-id",
            requestID: UUID()
        )
        let model = AuthViewModel(submitter: submitter, language: .ru)
        model.email = "user@example.com"
        model.password = "password"

        await model.submit()

        XCTAssertEqual(model.fieldErrors["email"], "Проверьте адрес электронной почты.")
        XCTAssertEqual(model.errorMessage, "Проверьте заполненные поля.")
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testAuthenticationFailureUsesRussianUserFacingMessage() async {
        let submitter = AuthSubmitterSpy()
        submitter.error = APIError(
            statusCode: 401,
            code: "authentication_failed",
            message: "Invalid email or password.",
            details: [],
            traceID: nil,
            requestID: UUID()
        )
        let model = AuthViewModel(submitter: submitter, language: .ru)
        model.email = "user@example.com"
        model.password = "password"

        await model.submit()

        XCTAssertEqual(model.errorMessage, "Неверная электронная почта или пароль.")
    }

    @MainActor
    func testEnglishPreferenceLocalizesValidationAndServerErrors() async {
        let submitter = AuthSubmitterSpy()
        let model = AuthViewModel(submitter: submitter, language: .en)

        await model.submit()

        XCTAssertEqual(model.fieldErrors["email"], "Enter a valid email address.")
        XCTAssertEqual(model.fieldErrors["password"], "Enter your password.")
        XCTAssertEqual(model.errorMessage, "Check the highlighted fields.")

        submitter.error = APIError(
            statusCode: 401,
            code: "authentication_failed",
            message: "Invalid email or password.",
            details: [],
            traceID: nil,
            requestID: UUID()
        )
        model.email = "user@example.com"
        model.password = "password"
        await model.submit()

        XCTAssertEqual(model.errorMessage, "Incorrect email or password.")
    }

    @MainActor
    func testChangingLanguageUpdatesCopyAndClearsStaleErrors() async {
        let model = AuthViewModel(submitter: AuthSubmitterSpy(), language: .ru)
        await model.submit()
        XCTAssertNotNil(model.errorMessage)

        model.setLanguage(.en)

        XCTAssertEqual(model.language, .en)
        XCTAssertEqual(model.copy.submitLogin, "Sign in")
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.fieldErrors.isEmpty)
    }
}
