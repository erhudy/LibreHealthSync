import ActivityKit
import Foundation
import os

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<GlucoseLiveActivityAttributes>?

    public let logger = Logger(subsystem: "com.erhudy.librehealthsync", category: "LiveActivityManager")

    func startActivity(connectionName: String, displayUnit: GlucoseDisplayUnit, glucose: GlucoseItem) {
        logger.trace("Calling LiveActivityManager.startActivity")
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let mgPerDl = glucose.mgPerDl,
              let timestamp = glucose.factoryTimestamp,
              let readingDate = LibreLinkUpTimestamp.parse(timestamp) else { return }

        let attributes = GlucoseLiveActivityAttributes(connectionName: connectionName)
        let state = GlucoseLiveActivityAttributes.ContentState(
            glucoseMgPerDl: mgPerDl,
            trendArrowRawValue: glucose.TrendArrow ?? 0,
            readingTimestamp: readingDate,
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
        logger.trace("Calling LiveActivityManager.updateActivity")
        if currentActivity == nil { return }
        guard let mgPerDl = glucose.mgPerDl,
              let timestamp = glucose.factoryTimestamp,
              let readingDate = LibreLinkUpTimestamp.parse(timestamp) else { return }

        let state = GlucoseLiveActivityAttributes.ContentState(
            glucoseMgPerDl: mgPerDl,
            trendArrowRawValue: glucose.TrendArrow ?? 0,
            readingTimestamp: readingDate,
            displayUnitRawValue: displayUnit.rawValue
        )

        Task {
            logger.trace("In Task in updateActivity")

            // Log all live activities to check for duplicates
            let allActivities = Activity<GlucoseLiveActivityAttributes>.activities
            logger.trace("Total live activities: \(allActivities.count, privacy: .public)")
            for (index, act) in allActivities.enumerated() {
                logger.trace("  Activity[\(index, privacy: .public)] id=\(act.id, privacy: .public) state=\(String(describing: act.activityState), privacy: .public)")
            }

            guard let activity = currentActivity else {
                logger.error("currentActivity became nil before update")
                return
            }
            logger.trace("Updating activity id=\(activity.id, privacy: .public) activityState=\(String(describing: activity.activityState), privacy: .public)")

            let staleDate = Date().addingTimeInterval(5 * 60)
            let content = ActivityContent(state: state, staleDate: staleDate)
            await activity.update(content)
        }
    }

    func endActivity() {
        logger.trace("Calling LiveActivityManager.endActivity")
        guard let activity = currentActivity else { return }
        let state = activity.content.state
        Task {
            await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
        currentActivity = nil
    }

    func reclaimExistingActivity() {
        logger.trace("Calling LiveActivityManager.reclaimExistingActivity")
        if let existing = Activity<GlucoseLiveActivityAttributes>.activities.first {
            currentActivity = existing
        }
    }

    var hasActiveActivity: Bool {
        logger.trace("Activity active: \(self.currentActivity != nil)")
        return currentActivity != nil
    }
}
