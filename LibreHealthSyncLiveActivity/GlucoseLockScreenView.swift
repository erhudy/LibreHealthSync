import ActivityKit
import SwiftUI
import WidgetKit

struct GlucoseLockScreenView: View {
    let context: ActivityViewContext<GlucoseLiveActivityAttributes>

    private var state: GlucoseLiveActivityAttributes.ContentState {
        context.state
    }

    var body: some View {
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

                Text(state.readingTimestamp, style: .time).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
