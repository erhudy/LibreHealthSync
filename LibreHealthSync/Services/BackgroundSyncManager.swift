import ActivityKit
import AVFoundation
@preconcurrency import BackgroundTasks
import UIKit
import os

actor BackgroundSyncManager {
    static let shared = BackgroundSyncManager()

    static let taskIdentifier = "com.librehealthsync.refresh"

    private var audioPlayer: AVAudioPlayer?
    private var backgroundSyncTask: Task<Void, Never>?

    nonisolated private struct Dependencies: Sendable {
        let appState: AppState
        let syncService: SyncService
    }

    /// Set synchronously from the app's init, before any BGTaskScheduler launch
    /// handler can fire. Guarded by a lock rather than actor isolation so the
    /// registration path stays synchronous.
    nonisolated private let dependencies = OSAllocatedUnfairLock<Dependencies?>(initialState: nil)

    private enum BackgroundSyncError: Error {
        case notConfigured
    }

    nonisolated public let logger = Logger(subsystem: "com.erhudy.librehealthsync", category: "BackgroundSyncManager")

    private init() {}

    // MARK: - BGTaskScheduler (infrequent fallback)

    /// Stores the sync dependencies and registers the BGAppRefreshTask handler.
    /// Must be called before the app finishes launching. When iOS launches the
    /// app from a terminated state just to run the refresh task, no scene ever
    /// connects, so the dependencies can't be injected from a view lifecycle.
    nonisolated func registerBackgroundTask(appState: AppState, syncService: SyncService) {
        logger.trace("Calling BackgroundSyncManager.registerBackgroundTask")
        dependencies.withLock { $0 = Dependencies(appState: appState, syncService: syncService) }
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            Task {
                await self.handleBackgroundRefresh(refreshTask)
            }
        }
    }

    func scheduleBackgroundRefresh() {
        logger.trace("Calling BackgroundSyncManager.scheduleBackgroundRefresh")
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(UserDefaults.standard.integer(forKey: "autoRefreshIntervalSeconds")))
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.error("Failed to schedule background refresh: \(error)")
        }
    }

    func cancelPendingRefreshes() {
        logger.trace("Calling BackgroundSyncManager.cancelPendingRefreshes")
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
    }

    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        logger.trace("Calling BackgroundSyncManager.handleBackgroundRefresh")
        scheduleBackgroundRefresh()

        // setTaskCompleted must be called exactly once, but both the sync task
        // and the expiration handler can reach it; whichever gets there first wins.
        let completed = OSAllocatedUnfairLock(initialState: false)
        let finish: @Sendable (Bool) -> Void = { success in
            let isFirst = completed.withLock { done -> Bool in
                defer { done = true }
                return !done
            }
            if isFirst {
                task.setTaskCompleted(success: success)
            }
        }

        // Install the expiration handler before any work starts so an early
        // expiration can never race ahead of it.
        let syncTask = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)
        task.expirationHandler = {
            syncTask.withLock { $0?.cancel() }
            finish(false)
        }

        let started = Task {
            do {
                try await performBackgroundSync()
                finish(true)
            } catch {
                logger.error("Background refresh sync failed: \(error)")
                finish(false)
            }
        }
        syncTask.withLock { $0 = started }
        // If the task expired in the window before the sync task was recorded,
        // the handler couldn't cancel it, so do that now.
        if completed.withLock({ $0 }) {
            started.cancel()
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
                    try await performBackgroundSync()
                } catch {
                    logger.error("Background sync loop iteration failed: \(error)")
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
            logger.error("Failed to configure audio session: \(error)")
            return
        }

        // Generate a minimal silent WAV in memory: 1 second of silence at 16kHz mono 16-bit
        guard let silentData = generateSilentWAV(durationSeconds: 1, sampleRate: 16000) else {
            logger.error("Failed to generate silent audio data")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(data: silentData)
            audioPlayer?.numberOfLoops = -1 // loop forever
            audioPlayer?.volume = 0
            audioPlayer?.play()
        } catch {
            logger.error("Failed to start silent audio player: \(error)")
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

    private func performBackgroundSync() async throws {
        logger.trace("Calling BackgroundSyncManager.performBackgroundSync")
        guard let dependencies = dependencies.withLock({ $0 }) else {
            logger.error("BackgroundSyncManager not configured with syncService or appState")
            throw BackgroundSyncError.notConfigured
        }

        let result = try await dependencies.syncService.sync()

        await dependencies.appState.updateFromSyncResult(result)
    }
}
