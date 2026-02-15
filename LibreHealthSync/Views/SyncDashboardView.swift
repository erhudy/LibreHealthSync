import ActivityKit
import SwiftUI

struct SyncDashboardView: View {
    @Environment(AppState.self) private var appState

    let syncService: SyncService
    let liveActivityManager: LiveActivityManager

    @State private var secondsRemaining: Int = 0
    @State private var timerTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Current glucose card
                    currentGlucoseCard

                    // Sync controls
                    syncControlsCard

                    // Sync status
                    syncStatusCard

                    // Recent readings
                    if !appState.recentReadings.isEmpty {
                        recentReadingsCard
                    }
                }
                .padding()
            }
            .navigationTitle(appState.connectionName ?? "Dashboard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        NavigationLink {
                            FAQView()
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gear")
                        }
                    }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { appState.showError },
                set: { if !$0 { appState.clearError() } }
            )) {
                Button("OK") { appState.clearError() }
            } message: {
                Text(appState.errorMessage ?? "Unknown error")
            }
            .task {
                await performSync()
                startAutoRefreshTimer()
            }
            .onDisappear { timerTask?.cancel() }
            .onChange(of: appState.autoRefreshIntervalSeconds) {
                startAutoRefreshTimer()
            }
        }
    }

    // MARK: - Current Glucose Card

    private var currentGlucoseCard: some View {
        VStack(spacing: 8) {
            if let glucose = appState.currentGlucose, let mgPerDl = glucose.mgPerDl {
                Text(appState.displayUnit.format(mgPerDl: mgPerDl))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(glucoseColor(mgPerDl: mgPerDl))

                HStack(spacing: 8) {
                    Text(appState.displayUnit.rawValue)
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    if let trend = glucose.trendDirection {
                        Text(trend.symbol)
                            .font(.title2)
                        Text(trend.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let timestamp = glucose.factoryTimestamp,
                   let date = LibreLinkUpTimestamp.parse(timestamp) {
                    Text(date, format: .dateTime.hour().minute().second())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    + Text(" ago")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("--")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("No data yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Sync Controls

    private var syncControlsCard: some View {
        VStack(spacing: 8) {
            Button {
                Task {
                    await performSync()
                    startAutoRefreshTimer()
                }
            } label: {
                HStack {
                    if appState.isSyncing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text(appState.isSyncing ? "Syncing..." : "Sync Now")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(appState.isSyncing ? Color.gray : Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(appState.isSyncing)

            if !appState.isSyncing && secondsRemaining > 0 {
                Text("Next sync in \(secondsRemaining)s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Sync Status

    private var syncStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Sync Status", systemImage: "clock.arrow.circlepath")
                .font(.headline)

            if let lastSync = appState.lastSyncDate {
                HStack {
                    Text("Last sync:")
                    Spacer()
                    Text(lastSync, style: .relative)
                    + Text(" ago")
                }
                .font(.subheadline)

                HStack {
                    Text("Readings written:")
                    Spacer()
                    Text("\(appState.lastSyncReadingsCount)")
                }
                .font(.subheadline)
            } else {
                Text("Not synced yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Recent Readings

    private var recentReadingsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Recent Readings", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)

            ForEach(appState.recentReadings.suffix(10).reversed(), id: \.FactoryTimestamp) { reading in
                if let mgPerDl = reading.mgPerDl,
                   let timestamp = reading.factoryTimestamp,
                   let date = LibreLinkUpTimestamp.parse(timestamp) {
                    HStack {
                        Text(appState.displayUnit.format(mgPerDl: mgPerDl))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(glucoseColor(mgPerDl: mgPerDl))
                        Text(appState.displayUnit.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let trend = reading.trendDirection {
                            Text(trend.symbol)
                                .font(.caption)
                        }
                        Spacer()
                        Text(date, format: .dateTime.hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func glucoseColor(mgPerDl: Double) -> Color {
        if mgPerDl < 70 { return .red }
        if mgPerDl > 180 { return .orange }
        return .green
    }

    private func startAutoRefreshTimer() {
        timerTask?.cancel()
        secondsRemaining = appState.autoRefreshIntervalSeconds
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                if secondsRemaining > 1 {
                    secondsRemaining -= 1
                } else {
                    secondsRemaining = 0
                    await performSync()
                    guard !Task.isCancelled else { break }
                    secondsRemaining = appState.autoRefreshIntervalSeconds
                }
            }
        }
    }

    private func performSync() async {
        appState.isSyncing = true
        appState.clearError()

        do {
            let result = try await syncService.sync()
            appState.connectionName = result.connectionName
            appState.currentGlucose = result.currentGlucose
            appState.recentReadings = result.allReadings
            appState.lastSyncDate = Date()
            appState.lastSyncReadingsCount = result.readingsWritten

            // Update or start Live Activity
            if let glucose = result.currentGlucose {
                if Activity<GlucoseLiveActivityAttributes>.activities.isEmpty {
                    liveActivityManager.startActivity(
                        connectionName: result.connectionName!,
                        displayUnit: appState.displayUnit,
                        glucose: glucose
                    )
                } else {
                    liveActivityManager.updateActivity(
                        glucose: glucose,
                        displayUnit: appState.displayUnit
                    )
                }
            }
        } catch {
            appState.setError(error.localizedDescription)
        }

        appState.isSyncing = false
    }
}
