import SwiftUI

@main
struct LibreHealthSyncApp: App {
    @State private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    private let apiService: LibreLinkUpService
    private let healthKitService: HealthKitService
    private let syncService: SyncService
    private let liveActivityManager = LiveActivityManager.shared

    init() {
        let appState = AppState()
        _appState = State(initialValue: appState)
        self.apiService = LibreLinkUpService()
        self.healthKitService = HealthKitService()
        let api = self.apiService
        self.syncService = SyncService(api: api, healthKit: self.healthKitService, reloginHandler: { try await api.relogin() })
        // Wire the background manager here, not from a view's .task: when iOS
        // launches the app from a terminated state to run a BGAppRefreshTask, no
        // scene is connected and view lifecycle hooks never run.
        BackgroundSyncManager.shared.registerBackgroundTask(appState: appState, syncService: syncService)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(apiService: apiService, syncService: syncService, liveActivityManager: liveActivityManager)
                .environment(appState)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                // Before login (or after logout) there is nothing to sync, so don't
                // keep the process alive with silent audio or schedule refreshes
                // that would only fail with 401.
                guard appState.isReadyToSync else { break }
                Task {
                    if appState.aggressiveBackgroundSync {
                        // Start a continuous sync loop using silent audio to keep the app alive
                        await BackgroundSyncManager.shared.startBackgroundSyncLoop(
                            intervalSeconds: appState.autoRefreshIntervalSeconds
                        )
                    }
                    // Schedule a BGAppRefreshTask (primary when aggressive is off, fallback when on)
                    await BackgroundSyncManager.shared.scheduleBackgroundRefresh()
                }
            case .active:
                Task {
                    // Foreground timer in SyncDashboardView takes over
                    await BackgroundSyncManager.shared.stopBackgroundSyncLoop()
                    await BackgroundSyncManager.shared.cancelPendingRefreshes()
                }
            default:
                break
            }
        }
    }
}
