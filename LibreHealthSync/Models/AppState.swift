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
        }
    }
    var autoRefreshIntervalSeconds: Int = 60 {
        didSet {
            UserDefaults.standard.set(autoRefreshIntervalSeconds, forKey: "autoRefreshIntervalSeconds")
        }
    }

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
