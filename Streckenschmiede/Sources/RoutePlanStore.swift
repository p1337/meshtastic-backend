import Foundation

private struct StoredRouteEnvelope: Codable {
    let schemaVersion: Int
    let savedAt: Date
    let plan: RideRoutePlan
}

enum RoutePlanStore {
    private static let schemaVersion = 1
    private static let maximumFileBytes = 25 * 1_024 * 1_024
    private static let maximumPoints = 200_000
    private static let maximumManeuvers = 10_000

    static func load(from url: URL = defaultURL()) throws -> RideRoutePlan? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize > 0,
              fileSize <= maximumFileBytes else {
            throw storeError("Ungültige oder zu große Routendatei")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let envelope = try decoder.decode(
            StoredRouteEnvelope.self,
            from: Data(contentsOf: url, options: [.mappedIfSafe])
        )
        guard envelope.schemaVersion == schemaVersion else {
            throw storeError("Unbekannte Routendatei-Version")
        }
        try validate(envelope.plan)
        return envelope.plan
    }

    static func save(
        _ plan: RideRoutePlan,
        to url: URL = defaultURL(),
        now: Date = Date()
    ) throws {
        try validate(plan)
        let envelope = StoredRouteEnvelope(
            schemaVersion: schemaVersion,
            savedAt: now,
            plan: plan
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        guard data.count <= maximumFileBytes else {
            throw storeError("Route ist zu groß zum sicheren Speichern")
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    static func clear(at url: URL = defaultURL()) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    static func defaultURL() -> URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("Streckenschmiede", isDirectory: true)
            .appendingPathComponent("active-route-v1.json", isDirectory: false)
    }

    private static func validate(_ plan: RideRoutePlan) throws {
        guard plan.points.count >= 2, plan.points.count <= maximumPoints else {
            throw storeError("Route enthält keine gültige Punktzahl")
        }
        guard plan.maneuvers.count <= maximumManeuvers else {
            throw storeError("Route enthält zu viele Manöver")
        }
        guard plan.distanceMeters.isFinite, plan.distanceMeters >= 0,
              plan.expectedTravelTime.isFinite, plan.expectedTravelTime >= 0 else {
            throw storeError("Route enthält ungültige Summen")
        }
        guard plan.destinationName.count <= 500,
              plan.providerName.count <= 200,
              plan.summary.count <= 2_000 else {
            throw storeError("Route enthält zu lange Texte")
        }
        for point in plan.points {
            guard point.latitude.isFinite, point.longitude.isFinite,
                  (-90...90).contains(point.latitude),
                  (-180...180).contains(point.longitude) else {
                throw storeError("Route enthält ungültige Koordinaten")
            }
        }
        for maneuver in plan.maneuvers {
            guard maneuver.instruction.count <= 500,
                  maneuver.distanceAlongRouteMeters.isFinite,
                  maneuver.distanceAlongRouteMeters >= 0 else {
                throw storeError("Route enthält ungültige Manöver")
            }
        }
    }

    private static func storeError(_ message: String) -> NSError {
        NSError(
            domain: "Streckenschmiede.RoutePlanStore",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
