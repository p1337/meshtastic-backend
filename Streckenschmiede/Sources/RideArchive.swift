import Foundation

struct RideArchiveEntry: Codable, Equatable, Identifiable {
    let dayIdentifier: String
    let rideID: UUID
    let startedAt: Date
    let updatedAt: Date
    let distanceMeters: Double
    let totalSeconds: Int
    let ridingSeconds: Int
    let pausedSeconds: Int
    let maximumSpeedKmh: Double
    let ascentMeters: Double
    let descentMeters: Double
    let pointCount: Int
    let gpxFileName: String

    var id: UUID { rideID }

    var averageSpeedKmh: Double {
        ridingSeconds > 0 ? distanceMeters / Double(ridingSeconds) * 3.6 : 0
    }

    var isValid: Bool {
        !dayIdentifier.isEmpty
            && dayIdentifier.count <= 32
            && distanceMeters.isFinite && distanceMeters >= 0
            && maximumSpeedKmh.isFinite && maximumSpeedKmh >= 0
            && ascentMeters.isFinite && ascentMeters >= 0
            && descentMeters.isFinite && descentMeters >= 0
            && totalSeconds >= 0
            && ridingSeconds >= 0
            && pausedSeconds >= 0
            && ridingSeconds <= totalSeconds
            && pausedSeconds <= totalSeconds
            && pointCount >= 0
            && (gpxFileName.hasPrefix("Tagesfahrt-") || gpxFileName.hasPrefix("Fahrt-"))
            && gpxFileName.hasSuffix(".gpx")
            && !gpxFileName.contains("..")
            && URL(fileURLWithPath: gpxFileName).lastPathComponent == gpxFileName
    }
}

private struct RideArchiveEnvelope: Codable {
    let schemaVersion: Int
    let entries: [RideArchiveEntry]
}

enum RideArchiveStore {
    static let maximumEntries = 3_650

    static func load(storeURL: URL? = nil) throws -> [RideArchiveEntry] {
        let url = storeURL ?? defaultStoreURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let envelope = try decoder.decode(
            RideArchiveEnvelope.self,
            from: Data(contentsOf: url)
        )
        guard envelope.schemaVersion == 1,
              envelope.entries.count <= maximumEntries,
              envelope.entries.allSatisfy(\.isValid),
              Set(envelope.entries.map(\.rideID)).count == envelope.entries.count,
              Set(envelope.entries.map(\.gpxFileName)).count == envelope.entries.count else {
            throw archiveError("Ungültige Fahrtenhistorie")
        }
        return envelope.entries.sorted { $0.startedAt > $1.startedAt }
    }

    @discardableResult
    static func upsert(
        _ entry: RideArchiveEntry,
        storeURL: URL? = nil
    ) throws -> [RideArchiveEntry] {
        guard entry.isValid else { throw archiveError("Ungültiger Historieneintrag") }
        let url = storeURL ?? defaultStoreURL()
        var entries = try load(storeURL: url)
        entries.removeAll { $0.rideID == entry.rideID }
        entries.append(entry)
        entries.sort { $0.startedAt > $1.startedAt }
        if entries.count > maximumEntries {
            entries.removeLast(entries.count - maximumEntries)
        }
        try persist(entries, to: url)
        return entries
    }

    @discardableResult
    static func delete(
        _ entry: RideArchiveEntry,
        storeURL: URL? = nil,
        documentsURL: URL? = nil
    ) throws -> [RideArchiveEntry] {
        guard entry.isValid else { throw archiveError("Ungültiger Historieneintrag") }
        let archiveURL = storeURL ?? defaultStoreURL()
        let originalEntries = try load(storeURL: archiveURL)
        guard originalEntries.contains(where: { $0.id == entry.id }) else {
            throw archiveError("Fahrt wurde nicht gefunden")
        }
        guard let gpxURL = gpxURL(for: entry, documentsURL: documentsURL) else {
            throw archiveError("Ungültiger GPX-Dateipfad")
        }
        let fileManager = FileManager.default
        let backupURL = gpxURL.deletingLastPathComponent().appendingPathComponent(
            ".streckenschmiede-delete-\(UUID().uuidString).gpx",
            isDirectory: false
        )
        var movedGPX = false
        if fileManager.fileExists(atPath: gpxURL.path) {
            try fileManager.moveItem(at: gpxURL, to: backupURL)
            movedGPX = true
        }

        var remaining = originalEntries
        remaining.removeAll { $0.id == entry.id }
        do {
            try persist(remaining, to: archiveURL)
            if movedGPX {
                do {
                    try fileManager.removeItem(at: backupURL)
                } catch {
                    try? persist(originalEntries, to: archiveURL)
                    try? fileManager.moveItem(at: backupURL, to: gpxURL)
                    throw archiveError("GPX-Datei konnte nicht sicher gelöscht werden")
                }
            }
            return remaining
        } catch {
            if movedGPX, fileManager.fileExists(atPath: backupURL.path) {
                try? fileManager.moveItem(at: backupURL, to: gpxURL)
            }
            throw error
        }
    }

    private static func persist(_ entries: [RideArchiveEntry], to url: URL) throws {
        guard entries.count <= maximumEntries,
              entries.allSatisfy(\.isValid),
              Set(entries.map(\.rideID)).count == entries.count,
              Set(entries.map(\.gpxFileName)).count == entries.count else {
            throw archiveError("Ungültige Fahrtenhistorie")
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(
            RideArchiveEnvelope(schemaVersion: 1, entries: entries)
        ).write(to: url, options: .atomic)
    }

    static func gpxURL(
        for entry: RideArchiveEntry,
        documentsURL: URL? = nil
    ) -> URL? {
        guard entry.isValid else { return nil }
        let root = documentsURL ?? FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let url = root.appendingPathComponent(entry.gpxFileName, isDirectory: false)
        guard url.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL else {
            return nil
        }
        return url
    }

    private static func defaultStoreURL() -> URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("Streckenschmiede", isDirectory: true)
            .appendingPathComponent("ride-archive-v1.json", isDirectory: false)
    }

    private static func archiveError(_ message: String) -> NSError {
        NSError(
            domain: "Streckenschmiede.RideArchive",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
