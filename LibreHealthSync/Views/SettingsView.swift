import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var showLogoutConfirmation = false

    var body: some View {
        @Bindable var state = appState

        Form {
            Section("Display") {
                Picker("Glucose Unit", selection: $state.displayUnit) {
                    ForEach(GlucoseDisplayUnit.allCases, id: \.self) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
            }

            Section("Auto Refresh") {
                Picker("Refresh Interval", selection: $state.autoRefreshIntervalSeconds) {
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                    Text("5 minutes").tag(300)
                    Text("10 minutes").tag(600)
                    Text("15 minutes").tag(900)
                }
            }

            Section("Account") {
                if let email = KeychainService().getEmail() {
                    HStack {
                        Text("Email")
                        Spacer()
                        Text(email)
                            .foregroundStyle(.secondary)
                    }
                }

                if let region = KeychainService().getRegion() {
                    HStack {
                        Text("Region")
                        Spacer()
                        Text(region.displayName)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button("Log Out", role: .destructive) {
                    showLogoutConfirmation = true
                }
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }

                Text("This app uses the unofficial LibreLinkUp API. It may stop working if Abbott changes their API.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Log Out", isPresented: $showLogoutConfirmation) {
            Button("Log Out", role: .destructive) {
                appState.logout()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to log out? Your stored credentials will be removed.")
        }
    }
}
