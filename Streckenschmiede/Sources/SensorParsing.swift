import Foundation

enum SensorParseError: Error {
    case truncated
}

struct HeartRateMeasurement: Equatable {
    let beatsPerMinute: Int
    let contactDetected: Bool?
    let rrIntervalsSeconds: [Double]
}

struct RevolutionMeasurement: Equatable {
    let wheelRevolutions: UInt32?
    let wheelEventTime: UInt16?
    let crankRevolutions: UInt16?
    let crankEventTime: UInt16?
}

struct CyclingPowerMeasurement: Equatable {
    let watts: Int
    let pedalPowerBalancePercent: Double?
    let wheelRevolutions: UInt32?
    let wheelEventTime: UInt16?
    let crankRevolutions: UInt16?
    let crankEventTime: UInt16?
}

struct IndoorBikeMeasurement: Equatable {
    let speedKmh: Double?
    let cadenceRpm: Double?
    let resistanceLevel: Double?
    let powerWatts: Int?
    let heartRateBpm: Int?
}

enum BikeSensorParser {
    static func heartRate(_ data: Data) throws -> HeartRateMeasurement {
        var cursor = ByteCursor(data)
        let flags = try cursor.readUInt8()
        let bpm = flags & 0x01 != 0
            ? Int(try cursor.readUInt16())
            : Int(try cursor.readUInt8())
        let contactBits = flags & 0x06
        let contact: Bool? = contactBits == 0x06 ? true : (contactBits == 0x04 ? false : nil)
        if flags & 0x08 != 0 { _ = try cursor.readUInt16() }
        var rrIntervals: [Double] = []
        if flags & 0x10 != 0 {
            while cursor.remaining >= 2 {
                rrIntervals.append(Double(try cursor.readUInt16()) / 1_024)
            }
        }
        return HeartRateMeasurement(
            beatsPerMinute: bpm,
            contactDetected: contact,
            rrIntervalsSeconds: rrIntervals
        )
    }

    static func cyclingSpeedAndCadence(_ data: Data) throws -> RevolutionMeasurement {
        var cursor = ByteCursor(data)
        let flags = try cursor.readUInt8()
        let wheelRevolutions = flags & 0x01 != 0 ? try cursor.readUInt32() : nil
        let wheelEventTime = flags & 0x01 != 0 ? try cursor.readUInt16() : nil
        let crankRevolutions = flags & 0x02 != 0 ? try cursor.readUInt16() : nil
        let crankEventTime = flags & 0x02 != 0 ? try cursor.readUInt16() : nil
        return RevolutionMeasurement(
            wheelRevolutions: wheelRevolutions,
            wheelEventTime: wheelEventTime,
            crankRevolutions: crankRevolutions,
            crankEventTime: crankEventTime
        )
    }

    static func cyclingPower(_ data: Data) throws -> CyclingPowerMeasurement {
        var cursor = ByteCursor(data)
        let flags = try cursor.readUInt16()
        let power = Int(Int16(bitPattern: try cursor.readUInt16()))
        let pedalBalance = flags & 0x0001 != 0
            ? Double(try cursor.readUInt8()) / 2
            : nil
        if flags & 0x0004 != 0 { _ = try cursor.readUInt16() }
        let wheelRevolutions = flags & 0x0010 != 0 ? try cursor.readUInt32() : nil
        let wheelEventTime = flags & 0x0010 != 0 ? try cursor.readUInt16() : nil
        let crankRevolutions = flags & 0x0020 != 0 ? try cursor.readUInt16() : nil
        let crankEventTime = flags & 0x0020 != 0 ? try cursor.readUInt16() : nil
        return CyclingPowerMeasurement(
            watts: power,
            pedalPowerBalancePercent: pedalBalance,
            wheelRevolutions: wheelRevolutions,
            wheelEventTime: wheelEventTime,
            crankRevolutions: crankRevolutions,
            crankEventTime: crankEventTime
        )
    }

    static func indoorBikeData(_ data: Data) throws -> IndoorBikeMeasurement {
        var cursor = ByteCursor(data)
        let flags = try cursor.readUInt16()
        let speed = flags & 0x0001 == 0 ? Double(try cursor.readUInt16()) / 100 : nil
        if flags & 0x0002 != 0 { _ = try cursor.readUInt16() }
        let cadence = flags & 0x0004 != 0 ? Double(try cursor.readUInt16()) / 2 : nil
        if flags & 0x0008 != 0 { _ = try cursor.readUInt16() }
        if flags & 0x0010 != 0 { _ = try cursor.readUInt24() }
        let resistance = flags & 0x0020 != 0
            ? Double(Int16(bitPattern: try cursor.readUInt16())) / 10
            : nil
        let power = flags & 0x0040 != 0
            ? Int(Int16(bitPattern: try cursor.readUInt16()))
            : nil
        if flags & 0x0080 != 0 { _ = try cursor.readUInt16() }
        if flags & 0x0100 != 0 {
            _ = try cursor.readUInt16()
            _ = try cursor.readUInt16()
            _ = try cursor.readUInt8()
        }
        let heartRate = flags & 0x0200 != 0 ? Int(try cursor.readUInt8()) : nil
        if flags & 0x0400 != 0 { _ = try cursor.readUInt8() }
        if flags & 0x0800 != 0 { _ = try cursor.readUInt16() }
        if flags & 0x1000 != 0 { _ = try cursor.readUInt16() }
        return IndoorBikeMeasurement(
            speedKmh: speed,
            cadenceRpm: cadence,
            resistanceLevel: resistance,
            powerWatts: power,
            heartRateBpm: heartRate
        )
    }

    static func batteryLevel(_ data: Data) throws -> Int {
        var cursor = ByteCursor(data)
        return min(100, Int(try cursor.readUInt8()))
    }
}

private struct ByteCursor {
    private let bytes: [UInt8]
    private(set) var offset = 0

    init(_ data: Data) { bytes = Array(data) }
    var remaining: Int { bytes.count - offset }

    mutating func readUInt8() throws -> UInt8 {
        guard remaining >= 1 else { throw SensorParseError.truncated }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func readUInt16() throws -> UInt16 {
        let low = UInt16(try readUInt8())
        return low | (UInt16(try readUInt8()) << 8)
    }

    mutating func readUInt24() throws -> UInt32 {
        let low = UInt32(try readUInt16())
        return low | (UInt32(try readUInt8()) << 16)
    }

    mutating func readUInt32() throws -> UInt32 {
        let low = UInt32(try readUInt16())
        return low | (UInt32(try readUInt16()) << 16)
    }
}
