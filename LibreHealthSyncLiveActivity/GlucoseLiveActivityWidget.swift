import ActivityKit
import os
import SwiftUI
import WidgetKit

struct GlucoseLiveActivityWidget: Widget {
    private static let logger = Logger(subsystem: "com.erhudy.librehealthsync.liveactivity", category: "GlucoseLiveActivityWidget")

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GlucoseLiveActivityAttributes.self) { context in
            // Lock Screen / StandBy presentation
            let _ = Self.logger.notice("GlucoseLiveActivityWidget lock screen closure called — glucoseMgPerDl: \(context.state.glucoseMgPerDl, privacy: .public), trendArrow: \(context.state.trendArrowRawValue, privacy: .public), readingTimestamp: \(context.state.readingTimestamp, privacy: .public), displayUnit: \(context.state.displayUnitRawValue, privacy: .public)")
            GlucoseLockScreenView(context: context)
                .activityBackgroundTint(.black.opacity(0.7))

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded regions
                DynamicIslandExpandedRegion(.leading) {
                    let _ = Self.logger.notice("GlucoseLiveActivityWidget dynamicIsland rendered — glucoseMgPerDl: \(context.state.glucoseMgPerDl, privacy: .public), trendArrow: \(context.state.trendArrowRawValue, privacy: .public), readingTimestamp: \(context.state.readingTimestamp, privacy: .public), displayUnit: \(context.state.displayUnitRawValue, privacy: .public)")
                    Text(GlucoseDisplayHelpers.formatGlucose(
                        mgPerDl: context.state.glucoseMgPerDl,
                        unitRaw: context.state.displayUnitRawValue
                    ))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(GlucoseDisplayHelpers.glucoseColor(mgPerDl: context.state.glucoseMgPerDl))
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(GlucoseDisplayHelpers.trendSymbol(rawValue: context.state.trendArrowRawValue))
                        .font(.system(size: 28, weight: .medium))
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        Text(context.state.displayUnitRawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text(context.state.readingTimestamp, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        + Text(" ago")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Text(GlucoseDisplayHelpers.formatGlucose(
                    mgPerDl: context.state.glucoseMgPerDl,
                    unitRaw: context.state.displayUnitRawValue
                ))
                .font(.system(.headline, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(GlucoseDisplayHelpers.glucoseColor(mgPerDl: context.state.glucoseMgPerDl))
            } compactTrailing: {
                Text(GlucoseDisplayHelpers.trendSymbol(rawValue: context.state.trendArrowRawValue))
                    .font(.headline)
            } minimal: {
                Text(GlucoseDisplayHelpers.formatGlucose(
                    mgPerDl: context.state.glucoseMgPerDl,
                    unitRaw: context.state.displayUnitRawValue
                ))
                .font(.system(.caption, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(GlucoseDisplayHelpers.glucoseColor(mgPerDl: context.state.glucoseMgPerDl))
            }
        }
    }
}
