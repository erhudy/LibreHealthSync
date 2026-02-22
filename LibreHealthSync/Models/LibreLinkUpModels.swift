import Foundation

// MARK: - API Regions

nonisolated enum LibreLinkUpRegion: String, CaseIterable, Identifiable, Codable {
    case us = "api-us.libreview.io"
//    only deal with US at the moment because I have no way of testing other regions
//    case eu = "api-eu.libreview.io"
//    case de = "api-de.libreview.io"
//    case fr = "api-fr.libreview.io"
//    case jp = "api-jp.libreview.io"
//    case ap = "api-ap.libreview.io"
//    case au = "api-au.libreview.io"
//    case ae = "api-ae.libreview.io"
//    case ca = "api-ca.libreview.io"
//    case eu2 = "api-eu2.libreview.io"
//    case ru = "api-ru.libreview.io"
//    case la = "api-la.libreview.io"
//    case global = "api.libreview.io"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .us: return "United States"
//        only deal with US at the moment because I have no way of testing other regions
//        case .eu: return "Europe"
//        case .de: return "Germany"
//        case .fr: return "France"
//        case .jp: return "Japan"
//        case .ap: return "Asia Pacific"
//        case .au: return "Australia"
//        case .ae: return "UAE"
//        case .ca: return "Canada"
//        case .eu2: return "Europe 2"
//        case .ru: return "Russia"
//        case .la: return "Latin America"
//        case .global: return "Global"
        }
    }

    var baseURL: URL {
        URL(string: "https://\(rawValue)")!
    }
}

// MARK: - Login

nonisolated struct LoginRequest: Encodable {
    let email: String
    let password: String
}

nonisolated struct LoginResponse: Decodable {
    let status: Int
    let data: LoginData?
    let ticket: AuthTicket?
    let redirect: Bool?
    let region: String?
}

nonisolated struct LoginData: Decodable {
    let user: UserInfo?
    let authTicket: AuthTicket?
    let redirect: Bool?
    let region: String?
}

nonisolated struct UserInfo: Decodable {
    let id: String
    let firstName: String?
    let lastName: String?
    let email: String?
}

nonisolated struct AuthTicket: Decodable {
    let token: String
    let expires: Int
    let duration: Int
}

// MARK: - Connections

nonisolated struct ConnectionsResponse: Decodable {
    let status: Int
    let data: [Connection]?
    let ticket: AuthTicket?
}

nonisolated struct Connection: Decodable, Identifiable {
    let id: String
    let patientId: String
    let firstName: String
    let lastName: String
    let glucoseMeasurement: GlucoseItem?
    let glucoseItem: GlucoseItem?
    let sensor: SensorInfo?

    var displayName: String {
        "\(firstName) \(lastName)"
    }

    var latestGlucose: GlucoseItem? {
        glucoseMeasurement ?? glucoseItem
    }
}

nonisolated struct SensorInfo: Decodable {
    let deviceId: String?
    let sn: String?
}

// MARK: - Glucose Data

nonisolated struct GlucoseItem: Decodable, CustomStringConvertible {
    let FactoryTimestamp: String?
    let Timestamp: String?
    let type: Int?
    let ValueInMgPerDl: Double?
    let MeasurementColor: Int?
    let GlucoseUnits: Int?
    let Value: Double?
    let isHigh: Bool?
    let isLow: Bool?
    let TrendArrow: Int?

    var mgPerDl: Double? {
        ValueInMgPerDl ?? Value
    }

    var factoryTimestamp: String? {
        FactoryTimestamp
    }

    var trendDirection: TrendArrowDirection? {
        guard let arrow = TrendArrow else { return nil }
        return TrendArrowDirection(rawValue: arrow)
    }

    var description: String {
        return "Timestamp: \(String(describing: Timestamp)) | Value: \(String(describing: ValueInMgPerDl))"
    }
}

nonisolated enum TrendArrowDirection: Int, CaseIterable, Sendable {
    case notDetermined = 0
    case fallingQuickly = 1
    case falling = 2
    case stable = 3
    case rising = 4
    case risingQuickly = 5

    var symbol: String {
        switch self {
        case .notDetermined: return "?"
        case .fallingQuickly: return "↓↓"
        case .falling: return "↓"
        case .stable: return "→"
        case .rising: return "↑"
        case .risingQuickly: return "↑↑"
        }
    }

    var description: String {
        switch self {
        case .notDetermined: return "Not Determined"
        case .fallingQuickly: return "Falling Quickly"
        case .falling: return "Falling"
        case .stable: return "Stable"
        case .rising: return "Rising"
        case .risingQuickly: return "Rising Quickly"
        }
    }
}

// MARK: - Graph / History

nonisolated struct GraphResponse: Decodable {
    let status: Int
    let data: GraphData?
    let ticket: AuthTicket?
}

nonisolated struct GraphData: Decodable {
    let connection: Connection?
    let activeSensors: [SensorInfo]?
    let graphData: [GlucoseItem]?
}

// MARK: - Timestamp Parsing

nonisolated enum LibreLinkUpTimestamp {
    /// Parses the FactoryTimestamp format: "M/d/yyyy h:mm:ss a" in UTC
    static func parse(_ timestamp: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")

        // Try "M/d/yyyy h:mm:ss a" (12-hour with AM/PM)
        formatter.dateFormat = "M/d/yyyy h:mm:ss a"
        if let date = formatter.date(from: timestamp) {
            return date
        }

        // Try with "tt" replaced — some responses use "AM"/"PM" directly
        // Also try 24-hour format as fallback
        formatter.dateFormat = "M/d/yyyy HH:mm:ss"
        if let date = formatter.date(from: timestamp) {
            return date
        }

        return nil
    }
}
