import Foundation

// Wire constants and active-low bitmap interpretation reference TrainerHUD (MIT).
// See THIRD_PARTY_NOTICES.md. Parser and error handling are implemented independently.
public enum ClickGATT {
    public static let service = "FC82"
    public static let legacyService = "00000001-19CA-4651-86E5-FA29DCDD09D1"
    public static let notify = "00000002-19CA-4651-86E5-FA29DCDD09D1"
    public static let write = "00000003-19CA-4651-86E5-FA29DCDD09D1"
    public static let indicate = "00000004-19CA-4651-86E5-FA29DCDD09D1"
    public static let battery = "2A19", firmware = "2A26", hardware = "2A27"
    /// Only these source-backed application commands are transmitted.
    public static let initialize = Data([0x52, 0x69, 0x64, 0x65, 0x4F, 0x6E])
    public static let readDeviceInfo = Data([0x00, 0x08, 0x00])
}

public enum PacketError: Error, Equatable, CustomStringConvertible {
    case empty, tooLarge, truncated, varintOverflow, invalidField, unsupportedWire
    case missingBitmap, duplicateBitmap, invalidValue
    public var description: String { String(reflecting: self) }
}

public enum ClickPacket: Equatable, Sendable {
    case handshake
    case encryptionRequired
    case buttons(Set<ClickButton>, bitmap: UInt32)
    case battery(Int)
    case idle
    case stopped
    case lostControl
    case unknown(UInt8, Data)
}

private struct Field {
    let number: UInt64
    let wire: UInt8
    let value: UInt64?
}

/// Bounded protobuf wire reader. Incomplete frames are never decoded as presses.
private enum Wire {
    static func fields(_ data: Data) throws -> [Field] {
        let bytes = Array(data)
        var i = 0
        func varint() throws -> UInt64 {
            var value: UInt64 = 0
            for index in 0..<10 {
                guard i < bytes.count else { throw PacketError.truncated }
                let byte = bytes[i]; i += 1
                if index == 9, byte > 1 { throw PacketError.varintOverflow }
                value |= UInt64(byte & 0x7F) << UInt64(index * 7)
                if byte & 0x80 == 0 { return value }
            }
            throw PacketError.varintOverflow
        }
        func skip(_ count: Int) throws {
            guard count <= bytes.count - i else { throw PacketError.truncated }
            i += count
        }
        var result: [Field] = []
        while i < bytes.count {
            let tag = try varint()
            let number = tag >> 3
            guard number > 0, number <= 536_870_911 else { throw PacketError.invalidField }
            let wire = UInt8(tag & 7)
            var value: UInt64?
            switch wire {
            case 0: value = try varint()
            case 1: try skip(8)
            case 2:
                let count = try varint()
                guard count <= UInt64(bytes.count - i) else { throw PacketError.truncated }
                try skip(Int(count))
            case 5: try skip(4)
            default: throw PacketError.unsupportedWire
            }
            result.append(Field(number: number, wire: wire, value: value))
        }
        return result
    }
}

public enum ClickPacketDecoder {
    public static func decode(_ data: Data) throws -> ClickPacket {
        guard !data.isEmpty else { throw PacketError.empty }
        guard data.count <= 512 else { throw PacketError.tooLarge }
        if data.starts(with: ClickGATT.initialize) {
            if data.count > 8 { return .encryptionRequired }
            if data == ClickGATT.initialize || data == ClickGATT.initialize + Data([0x02, 0x03]) {
                return .handshake
            }
            throw PacketError.invalidValue
        }
        let opcode = data[data.startIndex]
        let payload = Data(data.dropFirst())
        switch opcode {
        case 0x23:
            let fields = try Wire.fields(payload)
            let maps = fields.filter { $0.number == 1 }
            guard !maps.isEmpty else { throw PacketError.missingBitmap }
            guard maps.count == 1 else { throw PacketError.duplicateBitmap }
            guard let raw = maps[0].value, raw <= UInt64(UInt32.max) else { throw PacketError.invalidValue }
            let bitmap = UInt32(raw)
            let pressed = Set(ClickButton.allCases.filter { bitmap & $0.rawValue == 0 })
            return .buttons(pressed, bitmap: bitmap)
        case 0x19:
            let fields = try Wire.fields(payload).filter { $0.number == 2 }
            guard fields.count == 1, let percent = fields[0].value, percent <= 100 else { throw PacketError.invalidValue }
            return .battery(Int(percent))
        case 0x15: return .idle
        case 0xFE: return .lostControl
        case 0xFF:
            if data == Data([0xFF, 0x05, 0x00, 0xEA, 0x05]) || data == Data([0xFF, 0x05, 0x00, 0xFA, 0x05]) {
                return .stopped
            }
            return .unknown(opcode, payload)
        default: return .unknown(opcode, payload)
        }
    }
}

public extension Data {
    var hex: String { map { String(format: "%02X", $0) }.joined(separator: " ") }
}
