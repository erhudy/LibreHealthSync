import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState

    let apiService: LibreLinkUpService

    @State private var email = ""
    @State private var password = ""
    @State private var selectedRegion: LibreLinkUpRegion = .us
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("LibreLinkUp Credentials") {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }

                Section("Region") {
                    Picker("Server Region", selection: $selectedRegion) {
                        ForEach(LibreLinkUpRegion.allCases) { region in
                            Text(region.displayName).tag(region)
                        }
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                Section {
                    Button {
                        Task { await login() }
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView()
                            } else {
                                Text("Log In")
                            }
                            Spacer()
                        }
                    }
                    .disabled(email.isEmpty || password.isEmpty || isLoading)
                }
            }
            .navigationTitle("LibreHealth Sync")
            .onAppear {
                // Pre-fill email if stored
                let keychain = KeychainService()
                if let storedEmail = keychain.getEmail() {
                    email = storedEmail
                }
                if let storedRegion = keychain.getRegion() {
                    selectedRegion = storedRegion
                }
            }
        }
    }

    private func login() async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await apiService.login(
                email: email,
                password: password,
                region: selectedRegion
            )
            appState.userId = result.userId
            appState.isLoggedIn = true
        } catch let error as LibreLinkUpError {
            if case .termsOfUseRequired = error {
                appState.needsTermsAcceptance = true
            }
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
