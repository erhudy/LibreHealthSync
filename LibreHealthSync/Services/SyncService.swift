import Foundation

actor SyncService {
    private let api: any GlucoseDataProvider
    private let healthKit: any GlucoseWriter
    private let defaults: UserDefaults
    private let reloginHandler: (@Sendable () async throws -> Void)?

    private let lastSyncKey = "lastSyncTimestamp"

    init(api: any GlucoseDataProvider, healthKit: any GlucoseWriter, defaults: UserDefaults = .standard, reloginHandler: (@Sendable () async throws -> Void)? = nil) {
        self.api = api
        self.healthKit = healthKit
        self.defaults = defaults
        self.reloginHandler = reloginHandler
    }

    struct SyncResult {
        let readingsWritten: Int
        let currentGlucose: GlucoseItem?
        let allReadings: [GlucoseItem]
        let connectionName: String?
    }

    /// Fetch glucose data for the logged-in account, deduplicate, and write new readings to HealthKit.
    func sync() async throws -> SyncResult {
        // Fetch connections and use the first one
        let connections = try await api.fetchConnections()
        guard let connection = connections.first else {
            throw LibreLinkUpError.noData
        }

        // Fetch graph data from API
        let graphData = try await api.fetchGraphData(connectionId: connection.patientId)

        // Gather graph history readings (current measurement is tracked separately)
        var allReadings: [GlucoseItem] = []
        if let graphItems = graphData.graphData {
            allReadings.append(contentsOf: graphItems)
        }
        if let logbookItems = graphData.logbookData {
            allReadings.append(contentsOf: logbookItems)
        }

        let currentGlucose = graphData.connection?.latestGlucose

        // Sort by timestamp
        allReadings.sort { lhs, rhs in
            guard let l = lhs.factoryTimestamp, let r = rhs.factoryTimestamp,
                  let lDate = LibreLinkUpTimestamp.parse(l),
                  let rDate = LibreLinkUpTimestamp.parse(r)
            else { return false }
            return lDate < rDate
        }

        // Build the full set of readings for HealthKit (graph + current)
        var allReadingsForWrite = allReadings
        
        // Add all available measurements from the connection object to fill potential gaps
        let possibleLatest = [graphData.connection?.glucoseMeasurement, graphData.connection?.glucoseItem, connection.glucoseMeasurement, connection.glucoseItem]
        for item in possibleLatest {
            if let reading = item, let ts = reading.factoryTimestamp {
                // Only add if not already present (avoid duplicates by timestamp)
                if !allReadingsForWrite.contains(where: { $0.factoryTimestamp == ts }) {
                    allReadingsForWrite.append(reading)
                }
            }
        }
        
        allReadingsForWrite.sort { lhs, rhs in
            guard let l = lhs.factoryTimestamp, let r = rhs.factoryTimestamp,
                  let lDate = LibreLinkUpTimestamp.parse(l),
                  let rDate = LibreLinkUpTimestamp.parse(r)
            else { return false }
            return lDate < rDate
        }

        // Deduplicate: only keep readings newer than last synced timestamp
        let lastSynced = defaults.string(forKey: lastSyncKey)
        let newReadings: [GlucoseItem]

        if let lastSynced = lastSynced,
           let lastDate = LibreLinkUpTimestamp.parse(lastSynced) {
            newReadings = allReadingsForWrite.filter { reading in
                guard let ts = reading.factoryTimestamp,
                      let date = LibreLinkUpTimestamp.parse(ts)
                else { return false }
                return date > lastDate
            }
        } else {
            // First sync — write everything
            newReadings = allReadingsForWrite
        }

        // Write new readings to HealthKit
        // Extract sendable data from GlucoseItems on MainActor
        let readings = await HealthKitService.extractReadings(from: newReadings)
        let writtenCount = try await healthKit.writeGlucoseReadings(readings)

        // Update last synced timestamp to the newest reading we wrote
        if let newestTimestamp = newReadings.last?.factoryTimestamp {
            defaults.set(newestTimestamp, forKey: lastSyncKey)
        }

        return SyncResult(
            readingsWritten: writtenCount,
            currentGlucose: currentGlucose,
            allReadings: allReadingsForWrite,
            connectionName: connection.displayName
        )
    }

    /// Attempt to re-authenticate with stored credentials.
    func relogin() async throws {
        guard let reloginHandler else {
            throw LibreLinkUpError.authenticationFailed("No relogin handler configured.")
        }
        try await reloginHandler()
    }
}
