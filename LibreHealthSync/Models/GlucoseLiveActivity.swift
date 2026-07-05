import ActivityKit
import Foundation

nonisolated struct GlucoseLiveActivityAttributes: ActivityAttributes {
    /// Name of the LibreLinkUp connection (patient name) — static for the activity lifetime
    let connectionName: String

    // Adding a required field here breaks decoding of activities persisted by
    // older app versions, leaving them orphaned on the lock screen (undecodable
    // activities are omitted from Activity.activities, so they can never be
    // updated or ended). New fields must be optional or get a custom init(from:)
    // with a default.
    struct ContentState: Codable, Hashable {
        let glucoseMgPerDl: Double
        let trendArrowRawValue: Int
        let readingTimestamp: Date
        let displayUnitRawValue: String
    }
}
