import ActivityKit
import BackgroundTasks
import UIKit

@MainActor
final class BackgroundSyncManager {
    static let shared = BackgroundSyncManager()

    static let taskIdentifier = "com.librehealthsync.refresh"

    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var backgroundSyncTask: Task<Void, Never>?

    private init() {}

    // MARK: - BGTaskScheduler (infrequent fallback)

    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            Task { @MainActor in
                self.handleBackgroundRefresh(refreshTask)
            }
        }
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule background refresh: \(error)")
        }
    }

    func cancelPendingRefreshes() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
    }

    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()

        let syncTask = Task {
            do {
                let result = try await performBackgroundSync()
                updateLiveActivity(with: result)
                task.setTaskCompleted(success: true)
            } catch {
                print("Background refresh sync failed: \(error)")
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            syncTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    // MARK: - Continuous background execution

    /// Start a repeating sync loop that runs for as long as iOS grants background time.
    /// Typically ~30 seconds, but can be longer depending on system conditions.
    func startBackgroundSyncLoop(intervalSeconds: Int) {
        stopBackgroundSyncLoop()

        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            // iOS is about to kill our background time — clean up
            self?.stopBackgroundSyncLoop()
        }

        guard backgroundTaskID != .invalid else { return }

        backgroundSyncTask = Task {
            while !Task.isCancelled {
                do {
                    let result = try await performBackgroundSync()
                    updateLiveActivity(with: result)
                } catch {
                    print("Background sync loop iteration failed: \(error)")
                }

                do {
                    try await Task.sleep(for: .seconds(intervalSeconds))
                } catch {
                    break // cancelled
                }
            }
        }
    }

    func stopBackgroundSyncLoop() {
        backgroundSyncTask?.cancel()
        backgroundSyncTask = nil

        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }

    // MARK: - Shared sync logic

    private func performBackgroundSync() async throws -> SyncService.SyncResult {
        let apiService = LibreLinkUpService()
        let healthKitService = HealthKitService()
        let syncService = SyncService(api: apiService, healthKit: healthKitService, reloginHandler: { try await apiService.relogin() })
        return try await syncService.sync()
    }

    private func updateLiveActivity(with result: SyncService.SyncResult) {
        guard let glucose = result.currentGlucose else { return }

        let liveActivityManager = LiveActivityManager()
        liveActivityManager.reclaimExistingActivity()

        let displayUnitRaw = UserDefaults.standard.string(forKey: "displayUnit") ?? GlucoseDisplayUnit.mgdl.rawValue
        let displayUnit = GlucoseDisplayUnit(rawValue: displayUnitRaw) ?? .mgdl

        if liveActivityManager.hasActiveActivity {
            liveActivityManager.updateActivity(glucose: glucose, displayUnit: displayUnit)
        } else if let connectionName = result.connectionName {
            liveActivityManager.startActivity(connectionName: connectionName, displayUnit: displayUnit, glucose: glucose)
        }
    }
}
