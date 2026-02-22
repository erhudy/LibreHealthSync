import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    let apiService: LibreLinkUpService
    let syncService: SyncService
    let liveActivityManager: LiveActivityManager

    var body: some View {
        Group {
            if !appState.hasAcceptedTerms {
                TermsOfUseView()
            } else if !appState.isLoggedIn {
                LoginView(apiService: apiService)
            } else {
                SyncDashboardView(syncService: syncService, liveActivityManager: liveActivityManager)
            }
        }
        .animation(.default, value: appState.hasAcceptedTerms)
        .animation(.default, value: appState.isLoggedIn)
        .onChange(of: appState.isLoggedIn) { _, isLoggedIn in
            if !isLoggedIn {
                Task {
                    await liveActivityManager.endActivity()
                }
            }
        }
    }
}
