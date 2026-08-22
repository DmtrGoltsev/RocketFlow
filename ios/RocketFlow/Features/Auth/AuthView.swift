import SwiftUI

@MainActor
struct AuthView: View {
    private enum Field: Hashable {
        case displayName
        case email
        case password
    }

    @StateObject private var model: AuthViewModel
    @FocusState private var focusedField: Field?

    init(submitter: any AuthSubmitting) {
        _model = StateObject(wrappedValue: AuthViewModel(submitter: submitter))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("RocketFlow")
                                .font(.largeTitle.bold())
                            Text(model.mode == .login ? "Войдите в своё пространство" : "Создайте аккаунт")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Picker("Режим авторизации", selection: $model.mode) {
                            Text("Вход").tag(AuthMode.login)
                            Text("Регистрация").tag(AuthMode.register)
                        }
                        .pickerStyle(.segmented)
                        .disabled(model.isLoading)

                        if model.mode == .register {
                            field(
                                title: "Имя",
                                error: model.fieldErrors["displayName"]
                            ) {
                                TextField("Как к вам обращаться", text: $model.displayName)
                                    .textContentType(.name)
                                    .textInputAutocapitalization(.words)
                                    .focused($focusedField, equals: .displayName)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .email }
                                    .accessibilityIdentifier("auth.displayName")
                            }
                            .id(Field.displayName)
                        }

                        field(title: "Электронная почта", error: model.fieldErrors["email"]) {
                            TextField("name@example.com", text: $model.email)
                                .textContentType(.username)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .email)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .password }
                                .accessibilityIdentifier("auth.email")
                        }
                        .id(Field.email)

                        field(title: "Пароль", error: model.fieldErrors["password"]) {
                            SecureField("Пароль", text: $model.password)
                                .textContentType(model.mode == .login ? .password : .newPassword)
                                .focused($focusedField, equals: .password)
                                .submitLabel(.go)
                                .onSubmit { Task { await model.submit() } }
                                .accessibilityIdentifier("auth.password")
                        }
                        .id(Field.password)

                        if let message = model.errorMessage {
                            Label(message, systemImage: "exclamationmark.circle")
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("auth.error")
                                .accessibilityLabel("Ошибка. \(message)")
                        }
                    }
                    .frame(maxWidth: 520, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .padding(.bottom, 120)
                    .onChange(of: focusedField) { field in
                        guard let field else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(field, anchor: .center)
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("auth.screen")
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await model.submit() }
                } label: {
                    HStack(spacing: 10) {
                        if model.isLoading {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(model.mode == .login ? "Войти" : "Создать аккаунт")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isLoading)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.bar)
                .accessibilityIdentifier("auth.submit")
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") { focusedField = nil }
                }
            }
        }
    }

    @ViewBuilder
    private func field<Content: View>(
        title: String,
        error: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
            content()
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(error == nil ? Color.clear : Color.red, lineWidth: 1)
                }
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
