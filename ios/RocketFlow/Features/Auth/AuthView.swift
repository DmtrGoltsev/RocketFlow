import SwiftUI

@MainActor
struct AuthView: View {
    private enum Field: Hashable {
        case displayName
        case email
        case password
    }

    @ObservedObject private var languageStore: AppLanguageStore
    @StateObject private var model: AuthViewModel
    @FocusState private var focusedField: Field?

    init(
        submitter: any AuthSubmitting,
        languageStore: AppLanguageStore = .shared
    ) {
        _languageStore = ObservedObject(wrappedValue: languageStore)
        _model = StateObject(
            wrappedValue: AuthViewModel(submitter: submitter, language: languageStore.language)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("RocketFlow")
                                .font(.largeTitle.bold())
                            Text(model.mode == .login ? model.copy.loginSubtitle : model.copy.registerSubtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Picker(model.copy.mode, selection: $model.mode) {
                            Text(model.copy.login).tag(AuthMode.login)
                            Text(model.copy.register).tag(AuthMode.register)
                        }
                        .pickerStyle(.segmented)
                        .disabled(model.isLoading)
                        .accessibilityLabel(model.copy.mode)
                        .accessibilityIdentifier("auth.mode")

                        if model.mode == .register {
                            field(
                                title: model.copy.displayName,
                                error: model.fieldErrors["displayName"]
                            ) {
                                TextField(model.copy.displayNamePlaceholder, text: $model.displayName)
                                    .textContentType(.name)
                                    .textInputAutocapitalization(.words)
                                    .focused($focusedField, equals: .displayName)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .email }
                                    .accessibilityLabel(model.copy.displayName)
                                    .accessibilityIdentifier("auth.displayName")
                            }
                            .id(Field.displayName)
                        }

                        field(title: model.copy.email, error: model.fieldErrors["email"]) {
                            TextField("name@example.com", text: $model.email)
                                .textContentType(.username)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .email)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .password }
                                .accessibilityLabel(model.copy.email)
                                .accessibilityIdentifier("auth.email")
                        }
                        .id(Field.email)

                        field(title: model.copy.password, error: model.fieldErrors["password"]) {
                            SecureField(model.copy.password, text: $model.password)
                                .textContentType(model.mode == .login ? .password : .newPassword)
                                .focused($focusedField, equals: .password)
                                .submitLabel(.go)
                                .onSubmit { Task { await model.submit() } }
                                .accessibilityLabel(model.copy.password)
                                .accessibilityIdentifier("auth.password")
                        }
                        .id(Field.password)

                        if let message = model.errorMessage {
                            Label(message, systemImage: "exclamationmark.circle")
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("auth.error")
                                .accessibilityLabel("\(model.copy.errorAccessibilityPrefix). \(message)")
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
                        Text(model.mode == .login ? model.copy.submitLogin : model.copy.submitRegister)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isLoading)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.bar)
                .accessibilityLabel(
                    model.mode == .login ? model.copy.submitLogin : model.copy.submitRegister
                )
                .accessibilityIdentifier("auth.submit")
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Picker(
                        model.copy.language,
                        selection: Binding(
                            get: { languageStore.language },
                            set: { languageStore.setLanguage($0) }
                        )
                    ) {
                        Text(model.copy.russian).tag(AppLanguage.ru)
                        Text(model.copy.english).tag(AppLanguage.en)
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel(model.copy.language)
                    .accessibilityValue(model.copy.languageName(languageStore.language))
                    .accessibilityIdentifier("auth.language")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(model.copy.done) { focusedField = nil }
                }
            }
            .onChange(of: languageStore.language) { language in
                model.setLanguage(language)
            }
        }
        .environment(\.locale, Locale(identifier: languageStore.localeIdentifier))
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
