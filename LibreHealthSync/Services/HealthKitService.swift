import Foundation
import HealthKit

nonisolated protocol GlucoseWriter: Sendable {
    func writeGlucoseReadings(_ readings: [HealthKitService.GlucoseReading]) async throws -> Int
}

actor HealthKitService: GlucoseWriter {
    private let healthStore = HKHealthStore()

    private var isAuthorized = false

    // MARK: - Sendable Data Transfer Type

    struct GlucoseReading: Sendable {
        let mgPerDl: Double
        let factoryTimestamp: String
        let trendDirection: TrendArrowDirection?
    }

    /// Extracts sendable glucose readings from GlucoseItems.
    nonisolated static func extractReadings(from items: [GlucoseItem]) -> [GlucoseReading] {
        items.compactMap { item in
            guard let mgPerDl = item.mgPerDl,
                  let timestamp = item.factoryTimestamp else {
                return nil
            }
            return GlucoseReading(
                mgPerDl: mgPerDl,
                factoryTimestamp: timestamp,
                trendDirection: item.trendDirection
            )
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }

        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            throw HealthKitError.invalidType
        }

        let typesToShare: Set<HKSampleType> = [glucoseType]

        try await healthStore.requestAuthorization(toShare: typesToShare, read: [])

        // The prompt completing says nothing about the answer; check the
        // resulting status so a denial surfaces as a clear message rather than
        // a raw HKError from the first save().
        guard healthStore.authorizationStatus(for: glucoseType) == .sharingAuthorized else {
            throw HealthKitError.writeAccessDenied
        }
        isAuthorized = true
    }

    // MARK: - Write Glucose Samples

    /// Writes an array of glucose readings to HealthKit.
    /// Values are always provided in mg/dL from the API.
    /// Returns the number of samples successfully written.
    func writeGlucoseReadings(_ readings: [GlucoseReading]) async throws -> Int {
        if !isAuthorized {
            try await requestAuthorization()
        }

        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            throw HealthKitError.invalidType
        }

        let unit = HKUnit(from: "mg/dL")
        var samples: [HKQuantitySample] = []

        for reading in readings {
            guard let date = LibreLinkUpTimestamp.parse(reading.factoryTimestamp) else {
                continue
            }

            let quantity = HKQuantity(unit: unit, doubleValue: reading.mgPerDl)

            // Use FactoryTimestamp as external UUID for deduplication
            var metadata: [String: Any] = [
                HKMetadataKeyExternalUUID: "librelinkup-\(reading.factoryTimestamp)",
                "Source": "LibreLinkUp",
            ]

            if let trend = reading.trendDirection {
                metadata["TrendArrow"] = trend.description
            }

            let sample = HKQuantitySample(
                type: glucoseType,
                quantity: quantity,
                start: date,
                end: date,
                metadata: metadata
            )

            samples.append(sample)
        }

        guard !samples.isEmpty else {
            return 0
        }

        try await healthStore.save(samples)
        return samples.count
    }
}

enum HealthKitError: LocalizedError {
    case notAvailable
    case invalidType
    case writeAccessDenied
    case writeFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device."
        case .invalidType:
            return "Invalid HealthKit quantity type."
        case .writeAccessDenied:
            return "Apple Health write access is turned off. Enable Blood Glucose for LibreHealth Sync under Settings > Health > Data Access & Devices."
        case .writeFailed(let error):
            return "Failed to write to HealthKit: \(error.localizedDescription)"
        }
    }
}
