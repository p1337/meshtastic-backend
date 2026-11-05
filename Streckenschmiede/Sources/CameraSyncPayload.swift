import CryptoKit
import Foundation

enum CameraSyncEvent: String, Codable, CaseIterable, Identifiable {
    case start
    case checkpoint
    case end

    var id: String { rawValue }

    var title: String {
        switch self {
        case .start: return "Start"
        case .checkpoint: return "Checkpoint"
        case .end: return "Ende"
        }
    }
}

enum CameraSyncPayloadError: Error, Equatable {
    case unsupportedVersion
    case invalidRideID
    case invalidSequence
    case invalidUTC
    case invalidElapsedTime
    case incompleteCoordinate
    case invalidCoordinate
    case invalidAccuracy
    case invalidChecksumFormat
    case checksumMismatch
}

struct CameraSyncPayload: Codable, Equatable {
    static let currentVersion = 1
    static let checksumByteCount = 8

    let version: Int
    let rideID: String
    let event: CameraSyncEvent
    let sequence: Int
    let utc: String
    let rideElapsedMilliseconds: Int64
    let latitudeE7: Int?
    let longitudeE7: Int?
    let horizontalAccuracyCentimeters: Int?
    let payloadChecksum: String

    static func make(
        rideID: UUID,
        event: CameraSyncEvent,
        sequence: Int,
        date: Date,
        rideElapsedMilliseconds: Int64,
        latitude: Double?,
        longitude: Double?,
        horizontalAccuracy: Double?,
        includeGPS: Bool
    ) -> CameraSyncPayload {
        let utc = formatUTC(date)
        let coordinates = validatedCoordinates(
            latitude: latitude,
            longitude: longitude,
            includeGPS: includeGPS
        )
        let accuracy = validatedAccuracy(
            horizontalAccuracy,
            hasCoordinates: coordinates != nil,
            includeGPS: includeGPS
        )
        let values = Values(
            version: currentVersion,
            rideID: rideID.uuidString.lowercased(),
            event: event,
            sequence: max(0, sequence),
            utc: utc,
            rideElapsedMilliseconds: max(0, rideElapsedMilliseconds),
            latitudeE7: coordinates?.latitudeE7,
            longitudeE7: coordinates?.longitudeE7,
            horizontalAccuracyCentimeters: accuracy
        )
        return CameraSyncPayload(
            version: values.version,
            rideID: values.rideID,
            event: values.event,
            sequence: values.sequence,
            utc: values.utc,
            rideElapsedMilliseconds: values.rideElapsedMilliseconds,
            latitudeE7: values.latitudeE7,
            longitudeE7: values.longitudeE7,
            horizontalAccuracyCentimeters: values.horizontalAccuracyCentimeters,
            payloadChecksum: checksum(for: values)
        )
    }

    func encodedData() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    static func decodeValidated(from data: Data) throws -> CameraSyncPayload {
        let payload = try JSONDecoder().decode(CameraSyncPayload.self, from: data)
        try payload.validate()
        return payload
    }

    func validate() throws {
        guard version == Self.currentVersion else {
            throw CameraSyncPayloadError.unsupportedVersion
        }
        guard let parsedRideID = UUID(uuidString: rideID),
              parsedRideID.uuidString.lowercased() == rideID else {
            throw CameraSyncPayloadError.invalidRideID
        }
        guard sequence >= 0 else {
            throw CameraSyncPayloadError.invalidSequence
        }
        guard let parsedDate = Self.parseUTC(utc),
              Self.formatUTC(parsedDate) == utc else {
            throw CameraSyncPayloadError.invalidUTC
        }
        guard rideElapsedMilliseconds >= 0 else {
            throw CameraSyncPayloadError.invalidElapsedTime
        }

        switch (latitudeE7, longitudeE7) {
        case (nil, nil):
            guard horizontalAccuracyCentimeters == nil else {
                throw CameraSyncPayloadError.incompleteCoordinate
            }
        case let (.some(latitude), .some(longitude)):
            guard (-900_000_000...900_000_000).contains(latitude),
                  (-1_800_000_000...1_800_000_000).contains(longitude) else {
                throw CameraSyncPayloadError.invalidCoordinate
            }
            if let accuracy = horizontalAccuracyCentimeters,
               !(0...100_000_000).contains(accuracy) {
                throw CameraSyncPayloadError.invalidAccuracy
            }
        default:
            throw CameraSyncPayloadError.incompleteCoordinate
        }

        guard payloadChecksum.count == Self.checksumByteCount * 2,
              payloadChecksum.allSatisfy({ "0123456789abcdef".contains($0) }) else {
            throw CameraSyncPayloadError.invalidChecksumFormat
        }
        guard payloadChecksum == Self.checksum(for: values) else {
            throw CameraSyncPayloadError.checksumMismatch
        }
    }

    private var values: Values {
        Values(
            version: version,
            rideID: rideID,
            event: event,
            sequence: sequence,
            utc: utc,
            rideElapsedMilliseconds: rideElapsedMilliseconds,
            latitudeE7: latitudeE7,
            longitudeE7: longitudeE7,
            horizontalAccuracyCentimeters: horizontalAccuracyCentimeters
        )
    }

    private struct Values {
        let version: Int
        let rideID: String
        let event: CameraSyncEvent
        let sequence: Int
        let utc: String
        let rideElapsedMilliseconds: Int64
        let latitudeE7: Int?
        let longitudeE7: Int?
        let horizontalAccuracyCentimeters: Int?

        var canonicalText: String {
            [
                String(version),
                rideID,
                event.rawValue,
                String(sequence),
                utc,
                String(rideElapsedMilliseconds),
                latitudeE7.map { String($0) } ?? "",
                longitudeE7.map { String($0) } ?? "",
                horizontalAccuracyCentimeters.map { String($0) } ?? ""
            ].joined(separator: "|")
        }
    }

    private static func checksum(for values: Values) -> String {
        let digest = SHA256.hash(data: Data(values.canonicalText.utf8))
        return digest.prefix(checksumByteCount)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func validatedCoordinates(
        latitude: Double?,
        longitude: Double?,
        includeGPS: Bool
    ) -> (latitudeE7: Int, longitudeE7: Int)? {
        guard includeGPS,
              let latitude,
              let longitude,
              latitude.isFinite,
              longitude.isFinite,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else { return nil }
        return (
            Int((latitude * 10_000_000).rounded()),
            Int((longitude * 10_000_000).rounded())
        )
    }

    private static func validatedAccuracy(
        _ accuracy: Double?,
        hasCoordinates: Bool,
        includeGPS: Bool
    ) -> Int? {
        guard includeGPS,
              hasCoordinates,
              let accuracy,
              accuracy.isFinite,
              (0...1_000_000).contains(accuracy) else { return nil }
        return Int((accuracy * 100).rounded())
    }

    private static func formatUTC(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private static func parseUTC(_ value: String) -> Date? {
        dateFormatter.date(from: value)
    }

    private static var dateFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}
