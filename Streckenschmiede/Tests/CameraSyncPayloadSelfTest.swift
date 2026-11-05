import Foundation

private func cameraSyncExpect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) {
    guard condition() else {
        FileHandle.standardError.write(Data("Camera sync payload test failed: \(message)\n".utf8))
        exit(1)
    }
}

private func expectCameraSyncError(
    _ expected: CameraSyncPayloadError,
    _ operation: () throws -> Void,
    _ message: String
) {
    do {
        try operation()
        cameraSyncExpect(false, message)
    } catch let error as CameraSyncPayloadError {
        cameraSyncExpect(error == expected, "\(message): received \(error)")
    } catch {
        cameraSyncExpect(false, "\(message): unexpected error \(error)")
    }
}

@main
enum CameraSyncPayloadSelfTest {
    static func main() throws {
        let rideID = UUID(uuidString: "01234567-89ab-cdef-0123-456789abcdef")!
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: "2026-11-05T20:00:00.123Z")!
        let payload = CameraSyncPayload.make(
            rideID: rideID,
            event: .start,
            sequence: 7,
            date: date,
            rideElapsedMilliseconds: 1_234_567,
            latitude: 48.83,
            longitude: 9.32,
            horizontalAccuracy: 3.5,
            includeGPS: true
        )

        cameraSyncExpect(payload.version == 1, "protocol version")
        cameraSyncExpect(payload.rideID == rideID.uuidString.lowercased(), "canonical ride ID")
        cameraSyncExpect(payload.utc == "2026-11-05T20:00:00.123Z", "canonical UTC")
        cameraSyncExpect(payload.latitudeE7 == 488_300_000, "latitude E7")
        cameraSyncExpect(payload.longitudeE7 == 93_200_000, "longitude E7")
        cameraSyncExpect(payload.horizontalAccuracyCentimeters == 350, "accuracy centimeters")
        cameraSyncExpect(payload.payloadChecksum == "f5dda70a7c2e12a3", "stable checksum vector")

        let encoded = try payload.encodedData()
        let restored = try CameraSyncPayload.decodeValidated(from: encoded)
        cameraSyncExpect(restored == payload, "validated JSON roundtrip")

        let privatePayload = CameraSyncPayload.make(
            rideID: rideID,
            event: .checkpoint,
            sequence: 8,
            date: date,
            rideElapsedMilliseconds: 2_000,
            latitude: 48.83,
            longitude: 9.32,
            horizontalAccuracy: 3.5,
            includeGPS: false
        )
        cameraSyncExpect(privatePayload.latitudeE7 == nil, "privacy mode omits latitude")
        cameraSyncExpect(privatePayload.longitudeE7 == nil, "privacy mode omits longitude")
        cameraSyncExpect(privatePayload.horizontalAccuracyCentimeters == nil, "privacy mode omits accuracy")
        try privatePayload.validate()

        let invalidGPSPayload = CameraSyncPayload.make(
            rideID: rideID,
            event: .checkpoint,
            sequence: -1,
            date: date,
            rideElapsedMilliseconds: -1,
            latitude: 100,
            longitude: 9.32,
            horizontalAccuracy: -10,
            includeGPS: true
        )
        cameraSyncExpect(invalidGPSPayload.sequence == 0, "negative sequence is clamped")
        cameraSyncExpect(invalidGPSPayload.rideElapsedMilliseconds == 0, "negative elapsed time is clamped")
        cameraSyncExpect(invalidGPSPayload.latitudeE7 == nil, "invalid coordinates are omitted together")
        cameraSyncExpect(invalidGPSPayload.longitudeE7 == nil, "invalid coordinate pair is omitted")
        cameraSyncExpect(invalidGPSPayload.horizontalAccuracyCentimeters == nil, "accuracy requires coordinates")
        try invalidGPSPayload.validate()

        let tamperedJSON = String(decoding: encoded, as: UTF8.self)
            .replacingOccurrences(of: payload.payloadChecksum, with: "0000000000000000")
        expectCameraSyncError(.checksumMismatch, {
            _ = try CameraSyncPayload.decodeValidated(from: Data(tamperedJSON.utf8))
        }, "tampered payload must fail")

        let incompleteCoordinate = CameraSyncPayload(
            version: payload.version,
            rideID: payload.rideID,
            event: payload.event,
            sequence: payload.sequence,
            utc: payload.utc,
            rideElapsedMilliseconds: payload.rideElapsedMilliseconds,
            latitudeE7: payload.latitudeE7,
            longitudeE7: nil,
            horizontalAccuracyCentimeters: nil,
            payloadChecksum: payload.payloadChecksum
        )
        expectCameraSyncError(.incompleteCoordinate, {
            try incompleteCoordinate.validate()
        }, "half coordinate pair must fail")

        let unsupportedVersion = CameraSyncPayload(
            version: 2,
            rideID: payload.rideID,
            event: payload.event,
            sequence: payload.sequence,
            utc: payload.utc,
            rideElapsedMilliseconds: payload.rideElapsedMilliseconds,
            latitudeE7: payload.latitudeE7,
            longitudeE7: payload.longitudeE7,
            horizontalAccuracyCentimeters: payload.horizontalAccuracyCentimeters,
            payloadChecksum: payload.payloadChecksum
        )
        expectCameraSyncError(.unsupportedVersion, {
            try unsupportedVersion.validate()
        }, "future payload version must fail closed")

        print("Camera sync payload self-test passed")
    }
}
