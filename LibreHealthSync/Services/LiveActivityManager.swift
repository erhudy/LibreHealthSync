import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    private var currentActivity: Activity<GlucoseLiveActivityAttributes>?

    func startActivity(connectionName: String, displayUnit: GlucoseDisplayUnit, glucose: GlucoseItem) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let mgPerDl = glucose.mgPerDl,
              let timestamp = glucose.factoryTimestamp,
              let readingDate = LibreLinkUpTimestamp.parse(timestamp) else { return }

        let attributes = GlucoseLiveActivityAttributes(connectionName: connectionName)
        let state = GlucoseLiveActivityAttributes.ContentState(
            glucoseMgPerDl: mgPerDl,
            trendArrowRawValue: glucose.TrendArrow ?? 0,
            readingTimestamp: readingDate,
            lastSyncDate: Date(),
            displayUnitRawValue: displayUnit.rawValue
        )

        do {
            let staleDate = Date().addingTimeInterval(5 * 60)
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: staleDate)
            )
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }

    func updateActivity(glucose: GlucoseItem, displayUnit: GlucoseDisplayUnit) {
        guard let activity = currentActivity else { return }
        guard let mgPerDl = glucose.mgPerDl,
              let timestamp = glucose.factoryTimestamp,
              let readingDate = LibreLinkUpTimestamp.parse(timestamp) else { return }

        let state = GlucoseLiveActivityAttributes.ContentState(
            glucoseMgPerDl: mgPerDl,
            trendArrowRawValue: glucose.TrendArrow ?? 0,
            readingTimestamp: readingDate,
            lastSyncDate: Date(),
            displayUnitRawValue: displayUnit.rawValue
        )

        Task {
            let staleDate = Date().addingTimeInterval(5 * 60)
            await activity.update(.init(state: state, staleDate: staleDate))
        }
    }

    func endActivity() {
        guard let activity = currentActivity else { return }
        let state = activity.content.state
        Task {
            await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
        currentActivity = nil
    }

    func reclaimExistingActivity() {
        if let existing = Activity<GlucoseLiveActivityAttributes>.activities.first {
            currentActivity = existing
        }
    }

    var hasActiveActivity: Bool {
        if let activity = currentActivity {
            return activity.activityState == .active
        }
        return false
    }
}
