import Foundation

enum FTMSControlError: Error, Equatable {
    case truncated
    case invalidPacket
    case unsupported
    case rangeUnavailable
    case outOfRange
}

struct FTMSTargetCapabilities: Equatable {
    var inclination = false
    var resistance = false
    var power = false
    var indoorBikeSimulation = false
}

struct FTMSValueRange: Equatable {
    let minimum: Double
    let maximum: Double
    let increment: Double

    func quantized(_ value: Double) throws -> Double {
        guard value.isFinite, minimum <= maximum,
              value >= minimum - 0.000_001,
              value <= maximum + 0.000_001 else {
            throw FTMSControlError.outOfRange
        }
        guard increment > 0 else { return min(max(value, minimum), maximum) }
        let steps = ((value - minimum) / increment).rounded()
        return min(max(minimum + steps * increment, minimum), maximum)
    }
}

enum FTMSControlResult: UInt8, Equatable {
    case success = 0x01
    case opcodeNotSupported = 0x02
    case invalidParameter = 0x03
    case operationFailed = 0x04
    case controlNotPermitted = 0x05

    var message: String {
        switch self {
        case .success: return "Bestätigt"
        case .opcodeNotSupported: return "Befehl nicht unterstützt"
        case .invalidParameter: return "Wert vom Trainer abgelehnt"
        case .operationFailed: return "Trainer konnte den Befehl nicht ausführen"
        case .controlNotPermitted: return "Trainersteuerung nicht erlaubt"
        }
    }
}

struct FTMSControlResponse: Equatable {
    let requestOpcode: UInt8
    let result: FTMSControlResult
}

enum FTMSMachineStatus: Equatable {
    case reset
    case stopped
    case paused
    case safetyStop
    case started
    case controlPermissionLost
    case other(UInt8)
}

enum FTMSControlCommand: Equatable {
    case requestControl
    case startOrResume
    case stop
    case pause
    case setResistance(Double)
    case setPower(Int)
    case setInclination(Double)
    case setSimulationGrade(Double)

    var opcode: UInt8 {
        switch self {
        case .requestControl: return 0x00
        case .setInclination: return 0x03
        case .setResistance: return 0x04
        case .setPower: return 0x05
        case .startOrResume: return 0x07
        case .stop, .pause: return 0x08
        case .setSimulationGrade: return 0x11
        }
    }

    var title: String {
        switch self {
        case .requestControl: return "Steuerung anfordern"
        case .startOrResume: return "Training starten"
        case .stop: return "Not-Stopp"
        case .pause: return "Training pausieren"
        case .setResistance: return "Widerstand setzen"
        case .setPower: return "ERG-Leistung setzen"
        case .setInclination, .setSimulationGrade: return "Steigung setzen"
        }
    }
}

enum FTMSControlCodec {
    static func targetCapabilities(_ data: Data) throws -> FTMSTargetCapabilities {
        let bytes = Array(data)
        guard bytes.count >= 8 else { throw FTMSControlError.truncated }
        let target = readUInt32(bytes, offset: 4)
        return FTMSTargetCapabilities(
            inclination: target & (1 << 1) != 0,
            resistance: target & (1 << 2) != 0,
            power: target & (1 << 3) != 0,
            indoorBikeSimulation: target & (1 << 13) != 0
        )
    }

    static func valueRange(_ data: Data, resolution: Double) throws -> FTMSValueRange {
        let bytes = Array(data)
        guard bytes.count >= 6 else { throw FTMSControlError.truncated }
        let minimum = Double(readInt16(bytes, offset: 0)) * resolution
        let maximum = Double(readInt16(bytes, offset: 2)) * resolution
        let increment = Double(readUInt16(bytes, offset: 4)) * resolution
        guard minimum <= maximum, increment >= 0 else { throw FTMSControlError.invalidPacket }
        return FTMSValueRange(minimum: minimum, maximum: maximum, increment: increment)
    }

    static func encode(
        _ command: FTMSControlCommand,
        capabilities: FTMSTargetCapabilities,
        resistanceRange: FTMSValueRange?,
        inclinationRange: FTMSValueRange?,
        powerRange: FTMSValueRange?
    ) throws -> Data {
        var bytes = [command.opcode]
        switch command {
        case .requestControl, .startOrResume:
            break
        case .stop:
            bytes.append(0x01)
        case .pause:
            bytes.append(0x02)
        case let .setResistance(value):
            guard capabilities.resistance else { throw FTMSControlError.unsupported }
            guard let resistanceRange else { throw FTMSControlError.rangeUnavailable }
            let value = try resistanceRange.quantized(value)
            try appendScaledInt16(value, resolution: 0.1, to: &bytes)
        case let .setPower(watts):
            guard capabilities.power else { throw FTMSControlError.unsupported }
            guard let powerRange else { throw FTMSControlError.rangeUnavailable }
            let value = try powerRange.quantized(Double(watts))
            try appendScaledInt16(value, resolution: 1, to: &bytes)
        case let .setInclination(percent):
            guard capabilities.inclination else { throw FTMSControlError.unsupported }
            guard let inclinationRange else { throw FTMSControlError.rangeUnavailable }
            let value = try inclinationRange.quantized(percent)
            try appendScaledInt16(value, resolution: 0.1, to: &bytes)
        case let .setSimulationGrade(percent):
            guard capabilities.indoorBikeSimulation else { throw FTMSControlError.unsupported }
            guard percent.isFinite, (-10.0...15.0).contains(percent) else {
                throw FTMSControlError.outOfRange
            }
            appendInt16(0, to: &bytes) // wind speed: 0.000 m/s
            try appendScaledInt16(percent, resolution: 0.01, to: &bytes)
            bytes.append(40) // rolling resistance coefficient: 0.0040
            bytes.append(51) // wind resistance coefficient: 0.51 kg/m
        }
        return Data(bytes)
    }

    static func response(_ data: Data) throws -> FTMSControlResponse {
        let bytes = Array(data)
        guard bytes.count >= 3 else { throw FTMSControlError.truncated }
        guard bytes[0] == 0x80, let result = FTMSControlResult(rawValue: bytes[2]) else {
            throw FTMSControlError.invalidPacket
        }
        return FTMSControlResponse(requestOpcode: bytes[1], result: result)
    }

    static func machineStatus(_ data: Data) throws -> FTMSMachineStatus {
        let bytes = Array(data)
        guard let opcode = bytes.first else { throw FTMSControlError.truncated }
        switch opcode {
        case 0x01: return .reset
        case 0x02:
            guard bytes.count >= 2 else { throw FTMSControlError.truncated }
            return bytes[1] == 0x02 ? .paused : .stopped
        case 0x03: return .safetyStop
        case 0x04: return .started
        case 0xFF: return .controlPermissionLost
        default: return .other(opcode)
        }
    }

    private static func readUInt16(_ bytes: [UInt8], offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readInt16(_ bytes: [UInt8], offset: Int) -> Int16 {
        Int16(bitPattern: readUInt16(bytes, offset: offset))
    }

    private static func readUInt32(_ bytes: [UInt8], offset: Int) -> UInt32 {
        UInt32(readUInt16(bytes, offset: offset))
            | (UInt32(readUInt16(bytes, offset: offset + 2)) << 16)
    }

    private static func appendInt16(_ value: Int16, to bytes: inout [UInt8]) {
        let raw = UInt16(bitPattern: value)
        bytes.append(UInt8(raw & 0xFF))
        bytes.append(UInt8(raw >> 8))
    }

    private static func appendScaledInt16(
        _ value: Double,
        resolution: Double,
        to bytes: inout [UInt8]
    ) throws {
        let raw = (value / resolution).rounded()
        guard raw >= Double(Int16.min), raw <= Double(Int16.max) else {
            throw FTMSControlError.outOfRange
        }
        appendInt16(Int16(raw), to: &bytes)
    }
}
