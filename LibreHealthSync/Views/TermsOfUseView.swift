import SwiftUI

struct TermsOfUseView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Please read and accept the following before using this app.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Group {
                        disclaimerSection(
                            title: "Unofficial API",
                            text: "This app uses an unofficial, reverse-engineered Abbott LibreLinkUp API. It is not affiliated with, endorsed by, or supported by Abbott Laboratories. The API may change or stop working at any time without notice."
                        )

                        disclaimerSection(
                            title: "Not a Medical Device",
                            text: "This app is not a medical device and must not be used to make medical decisions. Always rely on your official glucose monitor and consult your healthcare provider for medical guidance."
                        )

                        disclaimerSection(
                            title: "No Warranty",
                            text: "This app is provided \"as is\" without warranty of any kind. The developer assumes no liability for any damages or issues arising from its use."
                        )

                        disclaimerSection(
                            title: "Data & Credentials",
                            text: "Your LibreLinkUp credentials are stored locally in the iOS Keychain on your device. Glucose data is transmitted to and from Abbott's servers as part of the normal LibreLinkUp API flow."
                        )

                        disclaimerSection(
                            title: "Use at Your Own Risk",
                            text: "By accepting these terms, you acknowledge that you understand and accept the risks associated with using this unofficial application."
                        )
                    }

                    Button {
                        appState.acceptTerms()
                    } label: {
                        Text("Accept")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("Terms of Use")
        }
    }

    private func disclaimerSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}
