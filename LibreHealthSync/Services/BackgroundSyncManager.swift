import ActivityKit
import AVFoundation
import BackgroundTasks
import UIKit
import os

@MainActor
final class BackgroundSyncManager {
    static let shared = BackgroundSyncManager()

    static let taskIdentifier = "com.librehealthsync.refresh"

    private var audioPlayer: AVAudioPlayer?
    private var backgroundSyncTask: Task<Void, Never>?

    public let logger = Logger(subsystem: "com.erhudy.librehealthsync", category: "BackgroundSyncManager")

    private init() {}

    // MARK: - BGTaskScheduler (infrequent fallback)

    func registerBackgroundTask() {
        logger.trace("Calling BackgroundSyncManager.registerBackgroundTask")
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            Task { @MainActor in
                self.handleBackgroundRefresh(refreshTask)
            }
        }
    }

    func scheduleBackgroundRefresh() {
        logger.trace("Calling BackgroundSyncManager.scheduleBackgroundRefresh")
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule background refresh: \(error)")
        }
    }

    func cancelPendingRefreshes() {
        logger.trace("Calling BackgroundSyncManager.cancelPendingRefreshes")
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
    }

    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        logger.trace("Calling BackgroundSyncManager.handleBackgroundRefresh")
        scheduleBackgroundRefresh()

        let syncTask = Task {
            do {
                let result = try await performBackgroundSync()
                updateLiveActivity(with: result)
                task.setTaskCompleted(success: true)
            } catch {
                print("Background refresh sync failed: \(error)")
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            syncTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    // MARK: - Silent audio background execution

    /// Start playing silent audio to keep the app alive indefinitely in the background,
    /// then run a repeating sync loop at the given interval.
    func startBackgroundSyncLoop(intervalSeconds: Int) {
        logger.trace("Calling BackgroundSyncManager.startBackgroundSyncLoop")
        stopBackgroundSyncLoop()
        startSilentAudio()

        backgroundSyncTask = Task {
            while !Task.isCancelled {
                do {
                    let result = try await performBackgroundSync()
                    updateLiveActivity(with: result)
                } catch {
                    print("Background sync loop iteration failed: \(error)")
                }

                do {
                    try await Task.sleep(for: .seconds(intervalSeconds))
                } catch {
                    break // cancelled
                }
            }
        }
    }

    func stopBackgroundSyncLoop() {
        logger.trace("Calling BackgroundSyncManager.stopBackgroundSyncLoop")
        backgroundSyncTask?.cancel()
        backgroundSyncTask = nil
        stopSilentAudio()
    }

    // MARK: - Silent audio helpers

    private func startSilentAudio() {
        logger.trace("Calling BackgroundSyncManager.startSilentAudio")
        guard audioPlayer == nil else { return }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .default, options: .mixWithOthers)
            try audioSession.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
            return
        }

        // Generate a minimal silent WAV in memory: 1 second of silence at 16kHz mono 16-bit
        guard let silentData = generateSilentWAV(durationSeconds: 1, sampleRate: 16000) else {
            print("Failed to generate silent audio data")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(data: silentData)
            audioPlayer?.numberOfLoops = -1 // loop forever
            audioPlayer?.volume = 0
            audioPlayer?.play()
        } catch {
            print("Failed to start silent audio player: \(error)")
        }
    }

    private func stopSilentAudio() {
        logger.trace("Calling BackgroundSyncManager.stopSilentAudio")
        audioPlayer?.stop()
        audioPlayer = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Generate a WAV file in memory containing silence.
    private func generateSilentWAV(durationSeconds: Int, sampleRate: Int) -> Data? {
        logger.trace("Calling BackgroundSyncManager.generateSilentWAV")
        let channels = 1
        let bitsPerSample = 16
        let bytesPerSample = bitsPerSample / 8
        let dataSize = sampleRate * durationSeconds * channels * bytesPerSample
        let fileSize = 44 + dataSize // 44-byte WAV header + PCM data

        var data = Data(capacity: fileSize)

        // RIFF header
        data.append(contentsOf: [UInt8]("RIFF".utf8))
        appendUInt32LE(&data, UInt32(fileSize - 8))
        data.append(contentsOf: [UInt8]("WAVE".utf8))

        // fmt sub-chunk
        data.append(contentsOf: [UInt8]("fmt ".utf8))
        appendUInt32LE(&data, 16) // sub-chunk size (PCM)
        appendUInt16LE(&data, 1)  // audio format (1 = PCM)
        appendUInt16LE(&data, UInt16(channels))
        appendUInt32LE(&data, UInt32(sampleRate))
        appendUInt32LE(&data, UInt32(sampleRate * channels * bytesPerSample)) // byte rate
        appendUInt16LE(&data, UInt16(channels * bytesPerSample)) // block align
        appendUInt16LE(&data, UInt16(bitsPerSample))

        // data sub-chunk
        data.append(contentsOf: [UInt8]("data".utf8))
        appendUInt32LE(&data, UInt32(dataSize))
        data.append(Data(count: dataSize)) // all zeros = silence

        return data
    }

    private func appendUInt32LE(_ data: inout Data, _ value: UInt32) {
        var v = value.littleEndian
        data.append(Data(bytes: &v, count: 4))
    }

    private func appendUInt16LE(_ data: inout Data, _ value: UInt16) {
        var v = value.littleEndian
        data.append(Data(bytes: &v, count: 2))
    }

    // MARK: - Shared sync logic

    private func performBackgroundSync() async throws -> SyncService.SyncResult {
        logger.trace("Calling BackgroundSyncManager.performBackgroundSync")
        let apiService = LibreLinkUpService()
        let healthKitService = HealthKitService()
        let syncService = SyncService(api: apiService, healthKit: healthKitService, reloginHandler: { try await apiService.relogin() })
        return try await syncService.sync()
    }

    private func updateLiveActivity(with result: SyncService.SyncResult) {
        logger.trace("Calling BackgroundSyncManager.updateLiveActivity")
        guard let glucose = result.currentGlucose else { return }

        let displayUnitRaw = UserDefaults.standard.string(forKey: "displayUnit") ?? GlucoseDisplayUnit.mgdl.rawValue
        let displayUnit = GlucoseDisplayUnit(rawValue: displayUnitRaw) ?? .mgdl

        if LiveActivityManager.shared.hasActiveActivity {
            logger.trace("Live Activity was updated because active one exists")
            LiveActivityManager.shared.updateActivity(glucose: glucose, displayUnit: displayUnit)
        } else if let connectionName = result.connectionName {
            logger.trace("Live Activity was started")
            LiveActivityManager.shared.startActivity(connectionName: connectionName, displayUnit: displayUnit, glucose: glucose)
        } else {
            logger.trace("Ran off end of LiveActivity block")
        }
    }
}
