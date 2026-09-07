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
        let (connection, graphData) = try await fetchWithReloginRetry()

        // Gather graph history readings (current measurement is tracked separately)
        var allReadings: [GlucoseItem] = []
        if let graphItems = graphData.graphData {
            allReadings.append(contentsOf: graphItems)
        }
        if let logbookItems = graphData.logbookData {
            allReadings.append(contentsOf: logbookItems)
        }

        let currentGlucose = graphData.connection?.latestGlucose

        // Add all available measurements from the connection object to fill potential gaps
        let possibleLatest = [graphData.connection?.glucoseMeasurement, graphData.connection?.glucoseItem, connection.glucoseMeasurement, connection.glucoseItem]
        for item in possibleLatest {
            if let reading = item, let ts = reading.factoryTimestamp {
                // Only add if not already present (avoid duplicates by timestamp)
                if !allReadings.contains(where: { $0.factoryTimestamp == ts }) {
                    allReadings.append(reading)
                }
            }
        }

        // Parse each timestamp exactly once, then sort chronologically. Readings
        // without a parseable timestamp can't be ordered, deduplicated, or written
        // to HealthKit, so they are dropped here.
        let datedReadings = allReadings
            .compactMap { reading in reading.factoryDate.map { (reading: reading, date: $0) } }
            .sorted { $0.date < $1.date }
        let allReadingsForWrite = datedReadings.map(\.reading)

        // Deduplicate: only keep readings newer than last synced timestamp
        let newReadings: [GlucoseItem]
        if let lastSynced = defaults.string(forKey: lastSyncKey),
           let lastDate = LibreLinkUpTimestamp.parse(lastSynced) {
            newReadings = datedReadings.filter { $0.date > lastDate }.map(\.reading)
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

    /// Fetch the first connection and its graph data. If the API reports the
    /// session has expired, re-login once with the stored credentials and retry.
    private func fetchWithReloginRetry() async throws -> (Connection, GraphData) {
        do {
            return try await fetchConnectionAndGraph()
        } catch LibreLinkUpError.sessionExpired where reloginHandler != nil {
            try await relogin()
            return try await fetchConnectionAndGraph()
        }
    }

    private func fetchConnectionAndGraph() async throws -> (Connection, GraphData) {
        // Use the first connection
        let connections = try await api.fetchConnections()
        guard let connection = connections.first else {
            throw LibreLinkUpError.noData
        }
        let graphData = try await api.fetchGraphData(connectionId: connection.patientId)
        return (connection, graphData)
    }

    /// Attempt to re-authenticate with stored credentials.
    func relogin() async throws {
        guard let reloginHandler else {
            throw LibreLinkUpError.authenticationFailed("No relogin handler configured.")
        }
        try await reloginHandler()
    }
}
