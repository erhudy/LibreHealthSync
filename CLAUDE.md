# CLAUDE.md — LibreLinkUp to Apple Health Sync App

## Project Overview

A native iOS app (Swift) that reads continuous glucose monitor (CGM) data from Abbott's LibreLinkUp API and writes it to Apple HealthKit as blood glucose samples.

## Architecture

### 1. LibreLinkUp API Integration

- Base URL: `https://api.libreview.io` (with regional variants for EU, AU, etc.). Only support United States at this time.
- Auth flow: POST login with email/password → receive JWT token
- Fetch connections: GET list of patients linked to the account
- Fetch glucose readings: GET recent CGM data for a given connection (current value, trend arrow, historical graph data)
- Tokens are JWT-based and expire; implement token refresh logic
- Regional server differences must be handled (the API may redirect to a region-specific endpoint on first auth)

### 2. Apple HealthKit Integration

- Request user authorization to write `HKQuantityType.bloodGlucose`
- Create `HKQuantitySample` objects with:
  - Glucose value (mg/dL or mmol/L depending on user region)
  - Timestamp from the CGM reading
  - Appropriate metadata (e.g., source device, meal context if available)
- Use `HKHealthStore.save()` to write samples

### 3. Data Sync Logic

- Use iOS Background App Refresh to periodically resync in the background
- Provide a manual sync button that can be used to refresh immediately
- Track the last synced reading timestamp (persist in UserDefaults or similar) to avoid duplicates
- Compare reading timestamps against last sync to determine which readings are new
- Write only new readings to HealthKit
- Implement mechanism to allow a user to backfill older data 

## Key Technical Considerations

- **Simple**: The application should remain extremely simple so as to avoid any implication that it has overlapping functionality or is a replacement for Abbott's own official application; it exists only to add features not provided by Abbott
- **Credentials storage**: Store LibreLinkUp email/password in iOS Keychain
- **Units**: LibreLink reports in mg/dL or mmol/L depending on user region; HealthKit requires explicit unit specification (`HKUnit.moleUnit(with: .milli, molarMass: HKUnitMolarMassBloodGlucose).unitDivided(by: .literUnit(with: .deci))` for mmol/L, or `HKUnit(from: "mg/dL")` for mg/dL)
- **Rate limiting**: Poll no more frequently than every 1 minute; the API likely rate-limits
- **Error handling**: Auth failures, network errors, expired tokens, API changes
- **Deduplication**: Use reading timestamps as unique keys to prevent duplicate HealthKit entries
- **Terms of service**: This uses an unofficial, reverse-engineered API — it may break if Abbott changes endpoints
- **Background activity**: The application requires the "Background Fetch", "Background Processing", and "Audio, AirPlay and Picture in Picture" background activity capabilities to allow syncing to happen on a regular basis even when the app is backgrounded

## Existing References

These open-source projects may be useful for understanding the LibreLinkUp API:

- `libre-link-up-api-client` (npm/TypeScript) — community wrapper around the API
- Nightscout LibreLinkUp plugin — Python/JS implementations of the auth and data fetch flow
- xDrip4iOS, Glucose Direct — open-source iOS apps that interact with Libre sensors and HealthKit

## MVP Scope

1. Login screen: email/password input, stored in Keychain
2. Manual sync: "Sync Now" button fetches recent readings and writes new ones to HealthKit
3. Sync status: display last sync time, number of readings written, any errors
4. Backfill: add a view that will allow a user to ask the application to sync older data from LibreLinkUp with selectable time windows, e.g. 1 day, 2 days, 1 week, as far back as possible
5. Settings: unit preference (mg/dL vs mmol/L), regional server selection
6. Live Activity: simple Live Activity showing the most recently synced blood glucose value and arrow

## Project Structure (suggested)

```
LibreHealthSync/
├── App/
│   └── LibreHealthSyncApp.swift
├── Models/
│   ├── GlucoseReading.swift
│   └── Connection.swift
├── Services/
│   ├── LibreLinkUpService.swift      # API client
│   ├── HealthKitService.swift         # HealthKit read/write
│   ├── KeychainService.swift          # Credential storage
│   └── SyncService.swift              # Orchestrates fetch + write + dedup
├── Views/
│   ├── LoginView.swift
│   ├── ConnectionListView.swift
│   ├── SyncDashboardView.swift
│   └── SettingsView.swift
└── Info.plist                         # HealthKit entitlement, usage descriptions
LibreHealthSyncLiveActivity/
├── GlucoseDisplayHelpers.swift   # Utility code
├── GlucoseLiveActivityWidget.swift    # Live Activity widget for when phone is unlocked
├── GlucoseLockScreenView.swift    # Live Activity widget for when phone is locked
└── Info.plist                         # HealthKit entitlement, usage descriptions
```

## Build & Run

- Xcode 15+, iOS 17+ target
- Enable HealthKit capability in Xcode project settings
- Add `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription` to Info.plist
