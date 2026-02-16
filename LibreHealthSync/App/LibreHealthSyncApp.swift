import SwiftUI

@main
struct LibreHealthSyncApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    private let apiService: LibreLinkUpService
    private let healthKitService: HealthKitService
    private let syncService: SyncService
    private let liveActivityManager = LiveActivityManager.shared

    init() {
        self.apiService = LibreLinkUpService()
        self.healthKitService = HealthKitService()
        let api = self.apiService
        self.syncService = SyncService(api: api, healthKit: self.healthKitService, reloginHandler: { try await api.relogin() })
        BackgroundSyncManager.shared.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(apiService: apiService, syncService: syncService, liveActivityManager: liveActivityManager)
                .environment(appState)
                .onAppear {
                    liveActivityManager.reclaimExistingActivity()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                if appState.aggressiveBackgroundSync {
                    // Start a continuous sync loop using silent audio to keep the app alive
                    BackgroundSyncManager.shared.startBackgroundSyncLoop(
                        intervalSeconds: appState.autoRefreshIntervalSeconds
                    )
                }
                // Schedule a BGAppRefreshTask (primary when aggressive is off, fallback when on)
                BackgroundSyncManager.shared.scheduleBackgroundRefresh()
            case .active:
                // Foreground timer in SyncDashboardView takes over
                BackgroundSyncManager.shared.stopBackgroundSyncLoop()
                BackgroundSyncManager.shared.cancelPendingRefreshes()
            default:
                break
            }
        }
    }
}
