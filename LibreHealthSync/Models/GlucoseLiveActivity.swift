import ActivityKit
import Foundation

nonisolated struct GlucoseLiveActivityAttributes: ActivityAttributes {
    /// Name of the LibreLinkUp connection (patient name) — static for the activity lifetime
    let connectionName: String

    struct ContentState: Codable, Hashable {
        let glucoseMgPerDl: Double
        let trendArrowRawValue: Int
        let readingTimestamp: Date
        let displayUnitRawValue: String
        let stalenessRedMinutes: Int
    }
}
