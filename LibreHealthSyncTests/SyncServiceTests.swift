import XCTest
@testable import LibreHealthSync

// UserDefaults is thread-safe; add Sendable conformance for test use.
extension UserDefaults: @retroactive @unchecked Sendable {}

// MARK: - Mocks

actor MockGlucoseDataProvider: GlucoseDataProvider {
    var connectionsToReturn: [Connection] = []
    var graphDataToReturn: GraphData = GraphData(connection: nil, activeSensors: nil, graphData: nil, logbookData: nil)
    var fetchConnectionsCallCount = 0
    var fetchGraphDataCallCount = 0
    /// Thrown by the next fetchConnections call only, then cleared.
    var errorForNextFetchConnections: Error?

    func setConnections(_ connections: [Connection]) {
        connectionsToReturn = connections
    }

    func failNextFetchConnections(with error: Error) {
        errorForNextFetchConnections = error
    }

    func getFetchConnectionsCallCount() -> Int {
        fetchConnectionsCallCount
    }

    func setGraphData(_ graphData: GraphData) {
        graphDataToReturn = graphData
    }

    func fetchConnections() async throws -> [Connection] {
        fetchConnectionsCallCount += 1
        if let error = errorForNextFetchConnections {
            errorForNextFetchConnections = nil
            throw error
        }
        return connectionsToReturn
    }

    func fetchGraphData(connectionId: String) async throws -> GraphData {
        fetchGraphDataCallCount += 1
        return graphDataToReturn
    }
}

actor MockGlucoseWriter: GlucoseWriter {
    var writtenReadings: [HealthKitService.GlucoseReading] = []
    var writeCallCount = 0

    func getWrittenReadings() -> [HealthKitService.GlucoseReading] {
        writtenReadings
    }

    func writeGlucoseReadings(_ readings: [HealthKitService.GlucoseReading]) async throws -> Int {
        writeCallCount += 1
        writtenReadings.append(contentsOf: readings)
        return readings.count
    }
}

// MARK: - Helpers

private func makeConnection(patientId: String = "patient1", firstName: String = "Test", lastName: String = "User", glucose: GlucoseItem? = nil) -> Connection {
    Connection(
        id: patientId,
        patientId: patientId,
        firstName: firstName,
        lastName: lastName,
        glucoseMeasurement: glucose,
        glucoseItem: nil,
        sensor: nil
    )
}

private func makeGlucoseItem(mgPerDl: Double, timestamp: String, trendArrow: Int? = nil) -> GlucoseItem {
    GlucoseItem(
        FactoryTimestamp: timestamp,
        Timestamp: timestamp,
        type: 1,
        ValueInMgPerDl: mgPerDl,
        MeasurementColor: 1,
        GlucoseUnits: 1,
        Value: mgPerDl,
        isHigh: false,
        isLow: false,
        TrendArrow: trendArrow
    )
}

// MARK: - Tests

final class SyncServiceTests: XCTestCase {

    private var mockAPI: MockGlucoseDataProvider!
    private var mockWriter: MockGlucoseWriter!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        mockAPI = MockGlucoseDataProvider()
        mockWriter = MockGlucoseWriter()
        defaults = UserDefaults(suiteName: "SyncServiceTests")!
        defaults.removePersistentDomain(forName: "SyncServiceTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "SyncServiceTests")
        super.tearDown()
    }

    private func makeSyncService(reloginHandler: (@Sendable () async throws -> Void)? = nil) -> SyncService {
        SyncService(api: mockAPI, healthKit: mockWriter, defaults: defaults, reloginHandler: reloginHandler)
    }

    // MARK: - Test Cases

    /// First sync with no prior lastSyncTimestamp should write all readings.
    func testFirstSyncWritesAllReadings() async throws {
        let items = [
            makeGlucoseItem(mgPerDl: 100, timestamp: "1/1/2025 12:00:00 AM"),
            makeGlucoseItem(mgPerDl: 110, timestamp: "1/1/2025 12:05:00 AM"),
            makeGlucoseItem(mgPerDl: 120, timestamp: "1/1/2025 12:10:00 AM"),
        ]

        await mockAPI.setConnections([makeConnection()])
        await mockAPI.setGraphData(GraphData(connection: nil, activeSensors: nil, graphData: items, logbookData: nil))

        let service = makeSyncService()
        let result = try await service.sync()

        XCTAssertEqual(result.readingsWritten, 3)
        let writtenReadings = await mockWriter.getWrittenReadings()
        XCTAssertEqual(writtenReadings.count, 3)
    }

    /// Subsequent sync should only write readings newer than lastSyncTimestamp.
    func testSubsequentSyncDeduplicates() async throws {
        // Set lastSyncTimestamp so readings at or before this are skipped
        defaults.set("1/1/2025 12:05:00 AM", forKey: "lastSyncTimestamp")

        let items = [
            makeGlucoseItem(mgPerDl: 100, timestamp: "1/1/2025 12:00:00 AM"),
            makeGlucoseItem(mgPerDl: 110, timestamp: "1/1/2025 12:05:00 AM"),
            makeGlucoseItem(mgPerDl: 120, timestamp: "1/1/2025 12:10:00 AM"),
        ]

        await mockAPI.setConnections([makeConnection()])
        await mockAPI.setGraphData(GraphData(connection: nil, activeSensors: nil, graphData: items, logbookData: nil))

        let service = makeSyncService()
        let result = try await service.sync()

        // Only the 12:10 reading is newer than lastSyncTimestamp of 12:05
        XCTAssertEqual(result.readingsWritten, 1)
        let writtenReadings = await mockWriter.getWrittenReadings()
        XCTAssertEqual(writtenReadings.count, 1)
        XCTAssertEqual(writtenReadings.first?.mgPerDl, 120)
    }

    /// The current glucose from graphData.connection.latestGlucose should be included.
    func testCurrentGlucoseIsIncluded() async throws {
        let historyItems = [
            makeGlucoseItem(mgPerDl: 100, timestamp: "1/1/2025 12:00:00 AM"),
        ]
        let currentItem = makeGlucoseItem(mgPerDl: 130, timestamp: "1/1/2025 12:15:00 AM")
        let connection = makeConnection(glucose: currentItem)

        await mockAPI.setConnections([makeConnection()])
        await mockAPI.setGraphData(GraphData(connection: connection, activeSensors: nil, graphData: historyItems, logbookData: nil))

        let service = makeSyncService()
        let result = try await service.sync()

        // Should write both the history item and the current glucose
        XCTAssertEqual(result.readingsWritten, 2)
        XCTAssertNotNil(result.currentGlucose)
        XCTAssertEqual(result.currentGlucose?.mgPerDl, 130)
    }

    /// Readings should be sorted by timestamp (chronological order).
    func testReadingsAreSortedByTimestamp() async throws {
        // Provide items out of order
        let items = [
            makeGlucoseItem(mgPerDl: 120, timestamp: "1/1/2025 12:10:00 AM"),
            makeGlucoseItem(mgPerDl: 100, timestamp: "1/1/2025 12:00:00 AM"),
            makeGlucoseItem(mgPerDl: 110, timestamp: "1/1/2025 12:05:00 AM"),
        ]

        await mockAPI.setConnections([makeConnection()])
        await mockAPI.setGraphData(GraphData(connection: nil, activeSensors: nil, graphData: items, logbookData: nil))

        let service = makeSyncService()
        let result = try await service.sync()

        XCTAssertEqual(result.readingsWritten, 3)
        // allReadings should be chronologically sorted
        XCTAssertEqual(result.allReadings.map { $0.mgPerDl }, [100, 110, 120])
    }

    /// When there are no readings, nothing should be written.
    func testEmptyGraphDataWritesNothing() async throws {
        await mockAPI.setConnections([makeConnection()])
        await mockAPI.setGraphData(GraphData(connection: nil, activeSensors: nil, graphData: [], logbookData: nil))

        let service = makeSyncService()
        let result = try await service.sync()

        XCTAssertEqual(result.readingsWritten, 0)
        let writtenReadings = await mockWriter.getWrittenReadings()
        XCTAssertEqual(writtenReadings.count, 0)
    }

    /// After sync, the lastSyncTimestamp should be updated to the newest reading's timestamp.
    func testUpdatesLastSyncTimestamp() async throws {
        let items = [
            makeGlucoseItem(mgPerDl: 100, timestamp: "1/1/2025 12:00:00 AM"),
            makeGlucoseItem(mgPerDl: 120, timestamp: "1/1/2025 12:10:00 AM"),
        ]

        await mockAPI.setConnections([makeConnection()])
        await mockAPI.setGraphData(GraphData(connection: nil, activeSensors: nil, graphData: items, logbookData: nil))

        let service = makeSyncService()
        _ = try await service.sync()

        let savedTimestamp = defaults.string(forKey: "lastSyncTimestamp")
        XCTAssertEqual(savedTimestamp, "1/1/2025 12:10:00 AM")
    }

    /// An expired session should trigger exactly one re-login and a retried fetch.
    func testSessionExpiredTriggersReloginAndRetry() async throws {
        let items = [makeGlucoseItem(mgPerDl: 100, timestamp: "1/1/2025 12:00:00 AM")]
        await mockAPI.setConnections([makeConnection()])
        await mockAPI.setGraphData(GraphData(connection: nil, activeSensors: nil, graphData: items, logbookData: nil))
        await mockAPI.failNextFetchConnections(with: LibreLinkUpError.sessionExpired)

        let reloginCount = ReloginCounter()
        let service = makeSyncService(reloginHandler: { await reloginCount.increment() })
        let result = try await service.sync()

        XCTAssertEqual(result.readingsWritten, 1)
        let relogins = await reloginCount.value
        XCTAssertEqual(relogins, 1)
        let fetches = await mockAPI.getFetchConnectionsCallCount()
        XCTAssertEqual(fetches, 2)
    }

    /// If the retried fetch still reports an expired session, the error surfaces.
    func testSessionExpiredAfterReloginPropagates() async throws {
        await mockAPI.setConnections([makeConnection()])
        await mockAPI.failNextFetchConnections(with: LibreLinkUpError.sessionExpired)

        let api = mockAPI!
        let service = makeSyncService(reloginHandler: {
            // Simulate the re-login succeeding but the new token being rejected too.
            await api.failNextFetchConnections(with: LibreLinkUpError.sessionExpired)
        })

        do {
            _ = try await service.sync()
            XCTFail("Expected sessionExpired to propagate")
        } catch LibreLinkUpError.sessionExpired {
            // expected
        }
    }

    /// Without a relogin handler, an expired session is reported immediately.
    func testSessionExpiredWithoutHandlerPropagates() async throws {
        await mockAPI.setConnections([makeConnection()])
        await mockAPI.failNextFetchConnections(with: LibreLinkUpError.sessionExpired)

        let service = makeSyncService()
        do {
            _ = try await service.sync()
            XCTFail("Expected sessionExpired to propagate")
        } catch LibreLinkUpError.sessionExpired {
            // expected
        }
        let fetches = await mockAPI.getFetchConnectionsCallCount()
        XCTAssertEqual(fetches, 1)
    }
}

private actor ReloginCounter {
    var value = 0
    func increment() { value += 1 }
}
