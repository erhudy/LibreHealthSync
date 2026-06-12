@preconcurrency import ActivityKit
import Foundation
import os

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<GlucoseLiveActivityAttributes>?

    public let logger = Logger(subsystem: "com.erhudy.librehealthsync", category: "LiveActivityManager")

    /// A live activity is one the system will still render updates for.
    private static func isLive(_ activity: Activity<GlucoseLiveActivityAttributes>) -> Bool {
        activity.activityState == .active || activity.activityState == .stale
    }

    func updateOrCreateActivity(connectionName: String, displayUnit: GlucoseDisplayUnit, glucose: GlucoseItem, stalenessRedMinutes: Int) async {
        logger.trace("Calling LiveActivityManager.updateOrCreateActivity")

        guard let mgPerDl = glucose.mgPerDl,
              let timestamp = glucose.factoryTimestamp,
              let readingDate = LibreLinkUpTimestamp.parse(timestamp) else { return }

        let state = GlucoseLiveActivityAttributes.ContentState(
            glucoseMgPerDl: mgPerDl,
            trendArrowRawValue: glucose.TrendArrow ?? 0,
            readingTimestamp: readingDate,
            displayUnitRawValue: displayUnit.rawValue,
            stalenessRedMinutes: stalenessRedMinutes
        )
        // staleDate drives the red-border re-render: the system redraws the view with
        // context.isStale == true once this date passes.
        let staleDate = readingDate.addingTimeInterval(Double(stalenessRedMinutes) * 60)
        let content = ActivityContent(state: state, staleDate: staleDate)

        // Reconcile with the system's activity list every time: our cached handle can
        // point at an activity the user dismissed or that survived from a previous run.
        let allActivities = Activity<GlucoseLiveActivityAttributes>.activities
        logger.trace("Total live activities: \(allActivities.count, privacy: .public)")
        for (index, act) in allActivities.enumerated() {
            logger.trace("  Activity[\(index, privacy: .public)] id=\(act.id, privacy: .public) state=\(String(describing: act.activityState), privacy: .public)")
        }

        let liveActivities = allActivities.filter(Self.isLive)

        // End anything dead, plus any duplicates beyond the first live activity,
        // so exactly one activity remains for the system to display.
        for dead in allActivities where !Self.isLive(dead) {
            await dead.end(.init(state: dead.content.state, staleDate: nil), dismissalPolicy: .immediate)
        }
        for extra in liveActivities.dropFirst() {
            logger.warning("Ending duplicate live activity id=\(extra.id, privacy: .public)")
            await extra.end(.init(state: extra.content.state, staleDate: nil), dismissalPolicy: .immediate)
        }

        if let activity = liveActivities.first {
            currentActivity = activity
            logger.trace("Updating activity id=\(activity.id, privacy: .public) activityState=\(String(describing: activity.activityState), privacy: .public)")
            await activity.update(content)
        } else {
            currentActivity = nil
            startActivity(connectionName: connectionName, content: content)
        }
    }

    private func startActivity(connectionName: String, content: ActivityContent<GlucoseLiveActivityAttributes.ContentState>) {
        logger.trace("Calling LiveActivityManager.startActivity")
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        do {
            currentActivity = try Activity.request(
                attributes: GlucoseLiveActivityAttributes(connectionName: connectionName),
                content: content
            )
        } catch {
            logger.error("Failed to start Live Activity: \(error)")
        }
    }

    func endActivity() async {
        logger.trace("Calling LiveActivityManager.endActivity")
        currentActivity = nil
        // End every activity the system knows about, not just our cached handle,
        // so logout never leaves an orphaned activity on the lock screen.
        for activity in Activity<GlucoseLiveActivityAttributes>.activities {
            await activity.end(.init(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate)
        }
    }

    func reclaimExistingActivity() {
        logger.trace("Calling LiveActivityManager.reclaimExistingActivity")
        currentActivity = Activity<GlucoseLiveActivityAttributes>.activities.first(where: Self.isLive)
    }

    var hasActiveActivity: Bool {
        logger.trace("Activity active: \(self.currentActivity != nil)")
        return currentActivity != nil
    }
}
