import ActivityKit
import os
import SwiftUI
import WidgetKit

struct GlucoseLockScreenView: View {
    private static let logger = Logger(subsystem: "com.erhudy.librehealthsync.liveactivity", category: "GlucoseLockScreenView")

    let context: ActivityViewContext<GlucoseLiveActivityAttributes>

    private var state: GlucoseLiveActivityAttributes.ContentState {
        context.state
    }

    var body: some View {
        let _ = Self.logger.trace("GlucoseLockScreenView body called — glucoseMgPerDl: \(state.glucoseMgPerDl, privacy: .public), trendArrow: \(state.trendArrowRawValue, privacy: .public), readingTimestamp: \(state.readingTimestamp, privacy: .public), displayUnit: \(state.displayUnitRawValue, privacy: .public)")
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                Text(GlucoseDisplayHelpers.formatGlucose(
                    mgPerDl: state.glucoseMgPerDl,
                    unitRaw: state.displayUnitRawValue
                ))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(GlucoseDisplayHelpers.glucoseColor(mgPerDl: state.glucoseMgPerDl))

                Text(state.displayUnitRawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(GlucoseDisplayHelpers.trendSymbol(rawValue: state.trendArrowRawValue))
                    .font(.system(size: 32, weight: .medium))

                Spacer()

                let relativeTime = Text(state.readingTimestamp, style: .relative)
                let absoluteTime = Text(state.readingTimestamp, style: .time)

                Text("\(relativeTime) ago (\(absoluteTime))").font(.default).foregroundStyle(.primary).multilineTextAlignment(.trailing)
            }
        }
        .padding()
    }
}
