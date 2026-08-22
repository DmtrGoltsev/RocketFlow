import Foundation
import XCTest
@testable import RocketFlow

@MainActor
private final class AuthSubmitterSpy: AuthSubmitting {
    var loginCalls: [(String, String)] = []
    var registrationCalls = 0
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
        registrationCalls += 1
        if let error { throw error }
    }
}

final class AuthViewModelTests: XCTestCase {
    @MainActor
    func testLoginValidationDoesNotSubmitInvalidFields() async {
        let submitter = AuthSubmitterSpy()
        let model = AuthViewModel(submitter: submitter)

        await model.submit()

        XCTAssertEqual(model.fieldErrors["email"], "Введите корректный адрес электронной почты.")
        XCTAssertEqual(model.fieldErrors["password"], "Введите пароль.")
        XCTAssertEqual(submitter.loginCalls.count, 0)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testRegistrationValidationAndSuccessState() async {
        let submitter = AuthSubmitterSpy()
        let model = AuthViewModel(submitter: submitter)
        model.mode = .register
        model.email = " USER@EXAMPLE.COM "
        model.password = "password1"
        model.displayName = " User "

        await model.submit()

        XCTAssertEqual(submitter.registrationCalls, 1)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.fieldErrors.isEmpty)
        XCTAssertFalse(model.isLoading)
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
        let model = AuthViewModel(submitter: submitter)
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
        let model = AuthViewModel(submitter: submitter)
        model.email = "user@example.com"
        model.password = "password"

        await model.submit()

        XCTAssertEqual(model.errorMessage, "Неверная электронная почта или пароль.")
    }
}
