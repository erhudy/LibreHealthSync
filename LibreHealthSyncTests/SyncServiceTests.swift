import XCTest
@testable import LibreHealthSync

// MARK: - Mocks

final class MockGlucoseDataProvider: GlucoseDataProvider {
    var connectionsToReturn: [Connection] = []
    var graphDataToReturn: GraphData = GraphData(connection: nil, activeSensors: nil, graphData: nil)
    var fetchConnectionsCallCount = 0
    var fetchGraphDataCallCount = 0

    func fetchConnections() async throws -> [Connection] {
        fetchConnectionsCallCount += 1
        return connectionsToReturn
    }

    func fetchGraphData(connectionId: String) async throws -> GraphData {
        fetchGraphDataCallCount += 1
        return graphDataToReturn
    }
}

final class MockGlucoseWriter: GlucoseWriter {
    var writtenReadings: [HealthKitService.GlucoseReading] = []
    var writeCallCount = 0

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

    private func makeSyncService() -> SyncService {
        SyncService(api: mockAPI, healthKit: mockWriter, defaults: defaults)
    }

    // MARK: - Test Cases

    /// First sync with no prior lastSyncTimestamp should write all readings.
    func testFirstSyncWritesAllReadings() async throws {
        let items = [
            makeGlucoseItem(mgPerDl: 100, timestamp: "1/1/2025 12:00:00 AM"),
            makeGlucoseItem(mgPerDl: 110, timestamp: "1/1/2025 12:05:00 AM"),
            makeGlucoseItem(mgPerDl: 120, timestamp: "1/1/2025 12:10:00 AM"),
        ]

        mockAPI.connectionsToReturn = [makeConnection()]
        mockAPI.graphDataToReturn = GraphData(connection: nil, activeSensors: nil, graphData: items)

        let service = makeSyncService()
        let result = try await service.sync()

        XCTAssertEqual(result.readingsWritten, 3)
        XCTAssertEqual(mockWriter.writtenReadings.count, 3)
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

        mockAPI.connectionsToReturn = [makeConnection()]
        mockAPI.graphDataToReturn = GraphData(connection: nil, activeSensors: nil, graphData: items)

        let service = makeSyncService()
        let result = try await service.sync()

        // Only the 12:10 reading is newer than lastSyncTimestamp of 12:05
        XCTAssertEqual(result.readingsWritten, 1)
        XCTAssertEqual(mockWriter.writtenReadings.count, 1)
        XCTAssertEqual(mockWriter.writtenReadings.first?.mgPerDl, 120)
    }

    /// The current glucose from graphData.connection.latestGlucose should be included.
    func testCurrentGlucoseIsIncluded() async throws {
        let historyItems = [
            makeGlucoseItem(mgPerDl: 100, timestamp: "1/1/2025 12:00:00 AM"),
        ]
        let currentItem = makeGlucoseItem(mgPerDl: 130, timestamp: "1/1/2025 12:15:00 AM")
        let connection = makeConnection(glucose: currentItem)

        mockAPI.connectionsToReturn = [makeConnection()]
        mockAPI.graphDataToReturn = GraphData(connection: connection, activeSensors: nil, graphData: historyItems)

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

        mockAPI.connectionsToReturn = [makeConnection()]
        mockAPI.graphDataToReturn = GraphData(connection: nil, activeSensors: nil, graphData: items)

        let service = makeSyncService()
        let result = try await service.sync()

        XCTAssertEqual(result.readingsWritten, 3)
        // allReadings should be chronologically sorted
        XCTAssertEqual(result.allReadings.map { $0.mgPerDl }, [100, 110, 120])
    }

    /// When there are no readings, nothing should be written.
    func testEmptyGraphDataWritesNothing() async throws {
        mockAPI.connectionsToReturn = [makeConnection()]
        mockAPI.graphDataToReturn = GraphData(connection: nil, activeSensors: nil, graphData: [])

        let service = makeSyncService()
        let result = try await service.sync()

        XCTAssertEqual(result.readingsWritten, 0)
        XCTAssertEqual(mockWriter.writtenReadings.count, 0)
    }

    /// After sync, the lastSyncTimestamp should be updated to the newest reading's timestamp.
    func testUpdatesLastSyncTimestamp() async throws {
        let items = [
            makeGlucoseItem(mgPerDl: 100, timestamp: "1/1/2025 12:00:00 AM"),
            makeGlucoseItem(mgPerDl: 120, timestamp: "1/1/2025 12:10:00 AM"),
        ]

        mockAPI.connectionsToReturn = [makeConnection()]
        mockAPI.graphDataToReturn = GraphData(connection: nil, activeSensors: nil, graphData: items)

        let service = makeSyncService()
        _ = try await service.sync()

        let savedTimestamp = defaults.string(forKey: "lastSyncTimestamp")
        XCTAssertEqual(savedTimestamp, "1/1/2025 12:10:00 AM")
    }
}
