import Foundation

private func archiveExpect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("Ride archive test failed: \(message)\n".utf8))
        exit(1)
    }
}

@main
enum RideArchiveSelfTest {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ride-archive-\(UUID().uuidString)", isDirectory: true)
        let storeURL = root.appendingPathComponent("archive.json")
        let documentsURL = root.appendingPathComponent("documents", isDirectory: true)
        try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let first = entry(day: "2026-11-04", offset: 0, distance: 20_000)
        let second = entry(day: "2026-11-05", offset: 86_400, distance: 42_000)
        try RideArchiveStore.upsert(first, storeURL: storeURL)
        let twoDays = try RideArchiveStore.upsert(second, storeURL: storeURL)
        archiveExpect(twoDays.map(\.dayIdentifier) == ["2026-11-05", "2026-11-04"], "newest day must sort first")

        let corrected = entry(day: "2026-11-04", offset: 0, distance: 25_000)
        let correctedDays = try RideArchiveStore.upsert(corrected, storeURL: storeURL)
        archiveExpect(correctedDays.count == 2, "upsert must not duplicate a calendar day")
        archiveExpect(correctedDays.last?.distanceMeters == 25_000, "same day must be replaced atomically")
        archiveExpect(corrected.averageSpeedKmh > 0, "derived average must use riding time")

        let gpxURL = RideArchiveStore.gpxURL(for: corrected, documentsURL: documentsURL)
        archiveExpect(gpxURL?.lastPathComponent == "Tagesfahrt-2026-11-04.gpx", "GPX URL must remain inside Documents")

        try Data("not-json".utf8).write(to: storeURL, options: .atomic)
        do {
            _ = try RideArchiveStore.load(storeURL: storeURL)
            archiveExpect(false, "corrupt archive must be rejected")
        } catch {
            archiveExpect(true, "corrupt archive rejected")
        }
        print("Ride archive self-test passed")
    }

    private static func entry(
        day: String,
        offset: TimeInterval,
        distance: Double
    ) -> RideArchiveEntry {
        RideArchiveEntry(
            dayIdentifier: day,
            rideID: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_800_000_000 + offset),
            updatedAt: Date(timeIntervalSince1970: 1_800_003_600 + offset),
            distanceMeters: distance,
            totalSeconds: 3_600,
            ridingSeconds: 3_000,
            pausedSeconds: 600,
            maximumSpeedKmh: 45,
            ascentMeters: 300,
            descentMeters: 280,
            pointCount: 100,
            gpxFileName: "Tagesfahrt-\(day).gpx"
        )
    }
}
