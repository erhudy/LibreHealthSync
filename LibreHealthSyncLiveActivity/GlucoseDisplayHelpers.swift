import SwiftUI

/// Standalone formatting helpers for the widget extension.
/// Duplicated from main app to avoid cross-target dependency issues.
enum GlucoseDisplayHelpers {

    static func formatGlucose(mgPerDl: Double, unitRaw: String) -> String {
        if unitRaw == "mmol/L" {
            return String(format: "%.1f", mgPerDl / 18.0182)
        }
        return String(format: "%.0f", mgPerDl)
    }

    static func glucoseColor(mgPerDl: Double) -> Color {
        if mgPerDl < 70 { return .red }
        if mgPerDl > 180 { return .orange }
        return .green
    }

    static func trendSymbol(rawValue: Int) -> String {
        switch rawValue {
        case 1: return "↓↓"
        case 2: return "↓"
        case 3: return "→"
        case 4: return "↑"
        case 5: return "↑↑"
        default: return "?"
        }
    }

    static func trendDescription(rawValue: Int) -> String {
        switch rawValue {
        case 1: return "Falling Quickly"
        case 2: return "Falling"
        case 3: return "Stable"
        case 4: return "Rising"
        case 5: return "Rising Quickly"
        default: return "Not Determined"
        }
    }
}
