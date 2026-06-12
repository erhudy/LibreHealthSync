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
        // Live Activity views render once per update into a static snapshot, so a
        // TimelineView never re-fires here. The only time-based re-render the system
        // provides is the staleDate: once it passes, the view is redrawn with
        // context.isStale == true. The staleDate is set to the reading timestamp plus
        // the user's red-border threshold, so isStale *is* the border condition.
        let _ = Self.logger.warning("GlucoseLockScreenView body called — glucoseMgPerDl: \(state.glucoseMgPerDl, privacy: .public), trendArrow: \(state.trendArrowRawValue, privacy: .public), readingTimestamp: \(state.readingTimestamp, privacy: .public), displayUnit: \(state.displayUnitRawValue, privacy: .public), redMinutes: \(state.stalenessRedMinutes, privacy: .public), isStale: \(context.isStale, privacy: .public)")
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
        .overlay {
            if context.isStale {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.red, lineWidth: 6)
            }
        }
    }
}
