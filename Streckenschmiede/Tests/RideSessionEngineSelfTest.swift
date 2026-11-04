import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("RideSessionEngine test failed: \(message)\n".utf8))
        exit(1)
    }
}

private func sample(latitude: Double, timestamp: Date, speed: Double = 4) -> RideSample {
    RideSample(
        latitude: latitude,
        longitude: 9,
        altitude: 250,
        horizontalAccuracy: 5,
        verticalAccuracy: 5,
        speedMetersPerSecond: speed,
        courseDegrees: 90,
        timestamp: timestamp
    )
}

@main
enum RideSessionEngineSelfTest {
    static func main() throws {
        let base = Date(timeIntervalSince1970: 2_000_000_000)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ride-session-test-\(UUID().uuidString)", isDirectory: true)
        let store = root.appendingPathComponent("active.json")
        defer { try? FileManager.default.removeItem(at: root) }

        let engine = RideSessionEngine(storeURL: store, now: base)
        engine.start(now: base)
        expect(engine.append(sample(latitude: 48, timestamp: base.addingTimeInterval(1)), now: base.addingTimeInterval(1)), "first point")
        expect(engine.append(sample(latitude: 48.0001, timestamp: base.addingTimeInterval(4)), now: base.addingTimeInterval(4)), "second point")
        expect((engine.snapshot?.distanceMeters ?? 0) > 10, "distance calculation")
        expect(!engine.append(sample(latitude: 49, timestamp: base.addingTimeInterval(5)), now: base.addingTimeInterval(5)), "reject GPS jump")
        engine.pause(now: base.addingTimeInterval(10))
        engine.resume(now: base.addingTimeInterval(20))
        engine.finish(now: base.addingTimeInterval(30))
        let durations = engine.durations(at: base.addingTimeInterval(30))
        expect(durations.totalSeconds == 30, "total time")
        expect(durations.ridingSeconds == 20, "riding time")
        expect(durations.pausedSeconds == 10, "paused time")

        engine.clearPersistedSession()
        let interrupted = RideSessionEngine(storeURL: store, now: base)
        interrupted.start(now: base)
        expect(interrupted.append(sample(latitude: 48, timestamp: base.addingTimeInterval(1)), now: base.addingTimeInterval(1)), "recovery first point")
        expect(interrupted.append(sample(latitude: 48.0001, timestamp: base.addingTimeInterval(5)), now: base.addingTimeInterval(5)), "recovery second point")
        interrupted.persistNow(now: base.addingTimeInterval(5))

        let recovered = RideSessionEngine(storeURL: store, now: base.addingTimeInterval(20))
        expect(recovered.phase == .recoveryRequired, "recovery phase")
        expect(recovered.samples.count == 2, "recovered points")
        let recoveryDurations = recovered.durations(at: base.addingTimeInterval(20))
        expect(recoveryDurations.ridingSeconds == 5, "recovered riding time")
        expect(recoveryDurations.pausedSeconds == 15, "interruption counted as pause")
        recovered.resume(now: base.addingTimeInterval(25))
        recovered.finish(now: base.addingTimeInterval(35))
        expect(recovered.durations(at: base.addingTimeInterval(35)).ridingSeconds == 15, "continued riding time")
        expect(recovered.lastPersistenceError == nil, "atomic persistence")
        print("RideSessionEngine self-test passed")
    }
}
