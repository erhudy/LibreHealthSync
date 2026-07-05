@preconcurrency import ActivityKit
import Foundation
import UIKit
import os

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    public let logger = Logger(subsystem: "com.erhudy.librehealthsync", category: "LiveActivityManager")

    /// A live activity is one the system will still render updates for.
    private static func isLive(_ activity: Activity<GlucoseLiveActivityAttributes>) -> Bool {
        activity.activityState == .active || activity.activityState == .stale
    }

    private func end(_ activity: Activity<GlucoseLiveActivityAttributes>) async {
        await activity.end(.init(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate)
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
            displayUnitRawValue: displayUnit.rawValue
        )
        // staleDate drives the red-border re-render: the system redraws the view with
        // context.isStale == true once this date passes.
        let staleDate = readingDate.addingTimeInterval(Double(stalenessRedMinutes) * 60)
        let content = ActivityContent(state: state, staleDate: staleDate)

        // Reconcile with the system's activity list every time: it can contain an
        // activity the user dismissed or one that survived from a previous run.
        let allActivities = Activity<GlucoseLiveActivityAttributes>.activities
        logger.trace("Total live activities: \(allActivities.count, privacy: .public)")
        for (index, act) in allActivities.enumerated() {
            logger.trace("  Activity[\(index, privacy: .public)] id=\(act.id, privacy: .public) state=\(String(describing: act.activityState), privacy: .public)")
        }

        // End anything dead, plus any duplicates beyond the first live activity,
        // so exactly one activity remains for the system to display.
        for dead in allActivities where !Self.isLive(dead) {
            await end(dead)
        }
        for extra in allActivities.filter(Self.isLive).dropFirst() {
            logger.warning("Ending duplicate live activity id=\(extra.id, privacy: .public)")
            await end(extra)
        }

        // Re-read the list after the awaits above: a concurrent call may have
        // created or ended activities while this one was suspended, and deciding
        // from the pre-suspension snapshot can double-create.
        if let activity = Activity<GlucoseLiveActivityAttributes>.activities.first(where: Self.isLive) {
            logger.trace("Updating activity id=\(activity.id, privacy: .public) activityState=\(String(describing: activity.activityState), privacy: .public)")
            await activity.update(content)
        } else {
            startActivity(connectionName: connectionName, content: content)
        }
    }

    /// Re-render the live activity from its own last reading with new display
    /// settings, for when settings change before a sync has populated app state.
    func applyDisplaySettings(displayUnit: GlucoseDisplayUnit, stalenessRedMinutes: Int) async {
        guard let activity = Activity<GlucoseLiveActivityAttributes>.activities.first(where: Self.isLive) else { return }
        let previous = activity.content.state
        let state = GlucoseLiveActivityAttributes.ContentState(
            glucoseMgPerDl: previous.glucoseMgPerDl,
            trendArrowRawValue: previous.trendArrowRawValue,
            readingTimestamp: previous.readingTimestamp,
            displayUnitRawValue: displayUnit.rawValue
        )
        let staleDate = previous.readingTimestamp.addingTimeInterval(Double(stalenessRedMinutes) * 60)
        await activity.update(ActivityContent(state: state, staleDate: staleDate))
    }

    private func startActivity(connectionName: String, content: ActivityContent<GlucoseLiveActivityAttributes.ContentState>) {
        logger.trace("Calling LiveActivityManager.startActivity")
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Live Activities can only be started from the foreground; a background
        // request always throws, so don't attempt one until the app is active again.
        guard UIApplication.shared.applicationState == .active else {
            logger.trace("Skipping Activity.request while app is not active")
            return
        }

        do {
            _ = try Activity.request(
                attributes: GlucoseLiveActivityAttributes(connectionName: connectionName),
                content: content
            )
        } catch {
            logger.error("Failed to start Live Activity: \(error)")
        }
    }

    func endActivity() async {
        logger.trace("Calling LiveActivityManager.endActivity")
        // End every activity the system knows about, so logout never leaves an
        // orphaned activity on the lock screen.
        for activity in Activity<GlucoseLiveActivityAttributes>.activities {
            await end(activity)
        }
    }
}
