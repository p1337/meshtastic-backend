import Foundation

enum RideSessionPhase: String, Codable {
    case idle
    case preparing
    case recording
    case paused
    case finishing
    case finished
    case recoveryRequired
}

struct RideSample: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
    let speedMetersPerSecond: Double
    let courseDegrees: Double
    let timestamp: Date
}

struct RideDurations: Equatable {
    let totalSeconds: TimeInterval
    let ridingSeconds: TimeInterval
    let pausedSeconds: TimeInterval
}

struct RideSessionSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let rideID: UUID
    var phase: RideSessionPhase
    let startedAt: Date
    var stateChangedAt: Date
    var endedAt: Date?
    var accumulatedRidingSeconds: TimeInterval
    var accumulatedPausedSeconds: TimeInterval
    var distanceMeters: Double
    var maximumSpeedKmh: Double
    var latestSpeedKmh: Double
    var ascentMeters: Double
    var descentMeters: Double
    var samples: [RideSample]
}

/// Owns all ride state transitions, timers, metrics and the recoverable on-disk snapshot.
/// LocationCore supplies measurements but never changes the state independently.
final class RideSessionEngine {
    private(set) var snapshot: RideSessionSnapshot?
    private(set) var lastPersistenceError: String?

    private let storeURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var lastPersistedAt: Date?

    var phase: RideSessionPhase { snapshot?.phase ?? .idle }
    var hasRecovery: Bool { phase == .recoveryRequired }
    var samples: [RideSample] { snapshot?.samples ?? [] }

    init(storeURL: URL? = nil, now: Date = Date()) {
        self.storeURL = storeURL ?? Self.defaultStoreURL()
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder.dateDecodingStrategy = .millisecondsSince1970
        loadRecoverableSession(now: now)
    }

    @discardableResult
    func start(now: Date = Date()) -> RideSessionSnapshot {
        var newSnapshot = RideSessionSnapshot(
            schemaVersion: 1,
            rideID: UUID(),
            phase: .preparing,
            startedAt: now,
            stateChangedAt: now,
            endedAt: nil,
            accumulatedRidingSeconds: 0,
            accumulatedPausedSeconds: 0,
            distanceMeters: 0,
            maximumSpeedKmh: 0,
            latestSpeedKmh: 0,
            ascentMeters: 0,
            descentMeters: 0,
            samples: []
        )
        snapshot = newSnapshot
        persist(force: true, now: now)
        newSnapshot.phase = .recording
        snapshot = newSnapshot
        persist(force: true, now: now)
        return newSnapshot
    }

    func pause(now: Date = Date()) {
        guard phase == .recording else { return }
        advanceCurrentPhase(to: now)
        snapshot?.phase = .paused
        snapshot?.latestSpeedKmh = 0
        snapshot?.stateChangedAt = now
        persist(force: true, now: now)
    }

    func resume(now: Date = Date()) {
        guard phase == .paused || phase == .recoveryRequired else { return }
        advanceCurrentPhase(to: now)
        snapshot?.phase = .recording
        snapshot?.stateChangedAt = now
        persist(force: true, now: now)
    }

    @discardableResult
    func finish(now: Date = Date()) -> RideSessionSnapshot? {
        guard snapshot != nil,
              phase == .recording || phase == .paused || phase == .recoveryRequired else {
            return snapshot
        }
        advanceCurrentPhase(to: now)
        snapshot?.phase = .finishing
        snapshot?.latestSpeedKmh = 0
        snapshot?.stateChangedAt = now
        persist(force: true, now: now)
        snapshot?.phase = .finished
        snapshot?.endedAt = now
        persist(force: true, now: now)
        return snapshot
    }

    @discardableResult
    func append(_ sample: RideSample, now: Date = Date()) -> Bool {
        guard phase == .recording,
              sample.horizontalAccuracy >= 0,
              sample.horizontalAccuracy < 40,
              abs(sample.timestamp.timeIntervalSince(now)) < 20,
              sample.speedMetersPerSecond < 0 || sample.speedMetersPerSecond <= 35 else {
            return false
        }

        if let last = snapshot?.samples.last {
            let seconds = sample.timestamp.timeIntervalSince(last.timestamp)
            guard seconds > 0 else { return false }
            let distance = Self.distanceMeters(from: last, to: sample)
            guard distance >= 3, distance < 300 else { return false }
            let derivedSpeed = distance / seconds
            let measuredSpeed = sample.speedMetersPerSecond >= 0
                ? sample.speedMetersPerSecond
                : derivedSpeed
            guard measuredSpeed <= 35, derivedSpeed <= 35 else { return false }
            snapshot?.distanceMeters += distance
            snapshot?.latestSpeedKmh = max(0, measuredSpeed * 3.6)
            snapshot?.maximumSpeedKmh = max(
                snapshot?.maximumSpeedKmh ?? 0,
                snapshot?.latestSpeedKmh ?? 0
            )
            if sample.verticalAccuracy >= 0, sample.verticalAccuracy < 30,
               last.verticalAccuracy >= 0, last.verticalAccuracy < 30 {
                let change = sample.altitude - last.altitude
                if change >= 1 { snapshot?.ascentMeters += change }
                if change <= -1 { snapshot?.descentMeters += abs(change) }
            }
        } else {
            let initialSpeed = sample.speedMetersPerSecond >= 0
                ? sample.speedMetersPerSecond * 3.6
                : 0
            snapshot?.latestSpeedKmh = initialSpeed
            snapshot?.maximumSpeedKmh = initialSpeed
        }
        snapshot?.samples.append(sample)
        persist(force: false, now: now)
        return true
    }

    func durations(at now: Date = Date()) -> RideDurations {
        guard let snapshot else {
            return RideDurations(totalSeconds: 0, ridingSeconds: 0, pausedSeconds: 0)
        }
        let end = snapshot.endedAt ?? now
        let total = max(0, end.timeIntervalSince(snapshot.startedAt))
        var riding = snapshot.accumulatedRidingSeconds
        var paused = snapshot.accumulatedPausedSeconds
        let current = max(0, end.timeIntervalSince(snapshot.stateChangedAt))
        if snapshot.phase == .recording { riding += current }
        if snapshot.phase == .paused || snapshot.phase == .recoveryRequired { paused += current }
        return RideDurations(
            totalSeconds: total,
            ridingSeconds: max(0, min(riding, total)),
            pausedSeconds: max(0, min(paused, total))
        )
    }

    func persistNow(now: Date = Date()) {
        persist(force: true, now: now)
    }

    func clearPersistedSession() {
        snapshot = nil
        lastPersistedAt = nil
        do {
            if FileManager.default.fileExists(atPath: storeURL.path) {
                try FileManager.default.removeItem(at: storeURL)
            }
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error.localizedDescription
        }
    }

    private func advanceCurrentPhase(to now: Date) {
        guard let current = snapshot else { return }
        let delta = max(0, now.timeIntervalSince(current.stateChangedAt))
        if current.phase == .recording {
            snapshot?.accumulatedRidingSeconds += delta
        } else if current.phase == .paused || current.phase == .recoveryRequired {
            snapshot?.accumulatedPausedSeconds += delta
        }
    }

    private func persist(force: Bool, now: Date) {
        guard let snapshot else { return }
        if !force, let lastPersistedAt, now.timeIntervalSince(lastPersistedAt) < 5 { return }
        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(snapshot).write(to: storeURL, options: .atomic)
            lastPersistedAt = now
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error.localizedDescription
        }
    }

    private func loadRecoverableSession(now: Date) {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }
        do {
            var loaded = try decoder.decode(
                RideSessionSnapshot.self,
                from: Data(contentsOf: storeURL)
            )
            guard loaded.schemaVersion == 1 else {
                throw NSError(
                    domain: "Streckenschmiede.RideSession",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Unbekannte Sitzungsdatei"]
                )
            }
            if loaded.phase == .idle || (loaded.phase == .finished && loaded.samples.isEmpty) {
                return
            }
            let lastValidActivity = min(now, loaded.samples.last?.timestamp ?? loaded.stateChangedAt)
            if loaded.phase == .recording {
                loaded.accumulatedRidingSeconds += max(
                    0,
                    lastValidActivity.timeIntervalSince(loaded.stateChangedAt)
                )
                loaded.accumulatedPausedSeconds += max(
                    0,
                    now.timeIntervalSince(lastValidActivity)
                )
            } else {
                loaded.accumulatedPausedSeconds += max(
                    0,
                    now.timeIntervalSince(loaded.stateChangedAt)
                )
            }
            loaded.phase = .recoveryRequired
            loaded.latestSpeedKmh = 0
            loaded.stateChangedAt = now
            loaded.endedAt = nil
            snapshot = loaded
            persist(force: true, now: now)
        } catch {
            lastPersistenceError = error.localizedDescription
        }
    }

    private static func defaultStoreURL() -> URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("Streckenschmiede", isDirectory: true)
            .appendingPathComponent("active-ride-v1.json", isDirectory: false)
    }

    private static func distanceMeters(from start: RideSample, to end: RideSample) -> Double {
        let radius = 6_371_000.0
        let latitude1 = start.latitude * .pi / 180
        let latitude2 = end.latitude * .pi / 180
        let latitudeDelta = (end.latitude - start.latitude) * .pi / 180
        let longitudeDelta = (end.longitude - start.longitude) * .pi / 180
        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(latitude1) * cos(latitude2)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return radius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
