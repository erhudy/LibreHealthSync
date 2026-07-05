import Foundation
import SwiftUI

@MainActor
@Observable
final class AppState {
    // Auth state
    var isLoggedIn: Bool = false
    var userId: String?

    // Sync state
    var connectionName: String?
    var lastSyncDate: Date?
    var lastSyncReadingsCount: Int = 0
    var isSyncing: Bool = false
    var currentGlucose: GlucoseItem?
    var recentReadings: [GlucoseItem] = []

    // Error state
    var errorMessage: String?
    var showError: Bool = false
    var hasAcceptedTerms: Bool = false
    var needsTermsAcceptance: Bool = false

    // Settings
    var displayUnit: GlucoseDisplayUnit = .mgdl {
        didSet {
            UserDefaults.standard.set(displayUnit.rawValue, forKey: "displayUnit")
            scheduleLiveActivityRefresh()
        }
    }
    var autoRefreshIntervalSeconds: Int = 60 {
        didSet {
            UserDefaults.standard.set(autoRefreshIntervalSeconds, forKey: "autoRefreshIntervalSeconds")
        }
    }
    var aggressiveBackgroundSync: Bool = true {
        didSet {
            UserDefaults.standard.set(aggressiveBackgroundSync, forKey: "aggressiveBackgroundSync")
        }
    }
    var stalenessRedMinutes: Int = 5 {
        didSet {
            UserDefaults.standard.set(stalenessRedMinutes, forKey: "stalenessRedMinutes")
            scheduleLiveActivityRefresh()
        }
    }

    @ObservationIgnored private var liveActivityRefreshTask: Task<Void, Never>?

    init() {
        // Restore persisted preferences
        if let unitRaw = UserDefaults.standard.string(forKey: "displayUnit"),
           let unit = GlucoseDisplayUnit(rawValue: unitRaw) {
            displayUnit = unit
        }
        let storedInterval = UserDefaults.standard.integer(forKey: "autoRefreshIntervalSeconds")
        if storedInterval > 0 {
            autoRefreshIntervalSeconds = storedInterval
        }
        if UserDefaults.standard.object(forKey: "aggressiveBackgroundSync") != nil {
            aggressiveBackgroundSync = UserDefaults.standard.bool(forKey: "aggressiveBackgroundSync")
        }
        let redMinutes = UserDefaults.standard.integer(forKey: "stalenessRedMinutes")
        if redMinutes > 0 {
            stalenessRedMinutes = redMinutes
        }

        // Restore terms acceptance
        hasAcceptedTerms = UserDefaults.standard.bool(forKey: "hasAcceptedTerms")

        // Check if we have stored credentials
        let keychain = KeychainService()
        isLoggedIn = keychain.getToken() != nil && keychain.getUserId() != nil
        userId = keychain.getUserId()
    }

    func acceptTerms() {
        hasAcceptedTerms = true
        UserDefaults.standard.set(true, forKey: "hasAcceptedTerms")
    }

    func setError(_ message: String) {
        errorMessage = message
        showError = true
    }

    func clearError() {
        errorMessage = nil
        showError = false
    }

    func logout() {
        let keychain = KeychainService()
        keychain.deleteAll()
        isLoggedIn = false
        userId = nil
        connectionName = nil
        currentGlucose = nil
        recentReadings = []
        lastSyncDate = nil
        lastSyncReadingsCount = 0
        UserDefaults.standard.removeObject(forKey: "lastSyncTimestamp")
    }

    func updateFromSyncResult(_ result: SyncService.SyncResult) async {
        self.connectionName = result.connectionName
        self.currentGlucose = result.currentGlucose
        self.recentReadings = result.allReadings
        self.lastSyncDate = Date()
        self.lastSyncReadingsCount = result.readingsWritten

        await refreshLiveActivity()
    }

    /// Coalesce bursts of settings changes (e.g. a held Stepper) into a single
    /// Live Activity update, since iOS budgets how often an activity may refresh.
    private func scheduleLiveActivityRefresh() {
        liveActivityRefreshTask?.cancel()
        liveActivityRefreshTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch { return }
            await refreshLiveActivity()
        }
    }

    /// Push the current glucose reading and display settings to the Live Activity.
    func refreshLiveActivity() async {
        guard let glucose = currentGlucose, let connectionName else {
            // No reading in app state yet (e.g. relaunch before a successful sync):
            // re-render any existing activity from its own last reading so settings
            // changes still reach the lock screen.
            await LiveActivityManager.shared.applyDisplaySettings(
                displayUnit: displayUnit,
                stalenessRedMinutes: stalenessRedMinutes
            )
            return
        }
        await LiveActivityManager.shared.updateOrCreateActivity(
            connectionName: connectionName,
            displayUnit: displayUnit,
            glucose: glucose,
            stalenessRedMinutes: stalenessRedMinutes
        )
    }
}

enum GlucoseDisplayUnit: String, CaseIterable {
    case mgdl = "mg/dL"
    case mmoll = "mmol/L"

    func convert(mgPerDl: Double) -> Double {
        switch self {
        case .mgdl: return mgPerDl
        case .mmoll: return mgPerDl / 18.0182
        }
    }

    func format(mgPerDl: Double) -> String {
        switch self {
        case .mgdl:
            return String(format: "%.0f", mgPerDl)
        case .mmoll:
            return String(format: "%.1f", convert(mgPerDl: mgPerDl))
        }
    }
}
