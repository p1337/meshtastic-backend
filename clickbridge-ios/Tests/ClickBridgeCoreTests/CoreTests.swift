import XCTest
@testable import ClickBridgeCore

final class DecoderTests: XCTestCase {
    func testReferenceVectors() throws {
        struct Vector: Decodable { let name: String; let hex: String; let buttons: [String] }
        struct File: Decodable { let vectors: [Vector] }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "reference-vectors", withExtension: "json", subdirectory: "Fixtures"))
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        for vector in file.vectors {
            let data = Data(vector.hex.split(separator: " ").map { UInt8($0, radix: 16)! })
            guard case .buttons(let buttons, _) = try ClickPacketDecoder.decode(data) else { return XCTFail(vector.name) }
            let names = buttons.map { String(describing: $0) }.sorted()
            XCTAssertEqual(names, vector.buttons.sorted(), vector.name)
        }
    }
    func testEveryButtonAndCombinations() throws {
        for button in ClickButton.allCases {
            let packet = try ClickPacketDecoder.decode(frame(~button.rawValue))
            XCTAssertEqual(packet, .buttons([button], bitmap: ~button.rawValue))
        }
        XCTAssertEqual(try ClickPacketDecoder.decode(frame(~(ClickButton.minus.rawValue | ClickButton.plus.rawValue))),
                       .buttons([.minus, .plus], bitmap: ~(ClickButton.minus.rawValue | ClickButton.plus.rawValue)))
    }
    func testMalformedNeverBecomesAllPressed() {
        let invalid: [[UInt8]] = [[], [0x23], [0x23, 0x08], [0x23, 0x00],
            [0x23, 0x08, 0xFF], [0x23, 0x0A, 0x00], [0x23, 0x0B],
            [0x23, 0x08, 0x00, 0x08, 0x00], [0x23, 0x12, 0x80, 0x80, 0x80, 0x01]]
        for bytes in invalid { XCTAssertThrowsError(try ClickPacketDecoder.decode(Data(bytes)), Data(bytes).hex) }
        XCTAssertThrowsError(try ClickPacketDecoder.decode(Data(repeating: 0, count: 513)))
        XCTAssertThrowsError(try ClickPacketDecoder.decode(Data([0x23, 0x08] + Array(repeating: 0xFF, count: 10))))
    }
    func testEveryTruncationOfBitmapFails() {
        let bytes = frame(~ClickButton.minus.rawValue)
        for count in 1..<bytes.count { XCTAssertThrowsError(try ClickPacketDecoder.decode(Data(bytes.prefix(count)))) }
    }
    func testHandshakeRequiresSupportedReply() throws {
        XCTAssertEqual(try ClickPacketDecoder.decode(ClickGATT.initialize), .handshake)
        XCTAssertEqual(try ClickPacketDecoder.decode(ClickGATT.initialize + Data([2, 3])), .handshake)
        XCTAssertEqual(try ClickPacketDecoder.decode(ClickGATT.initialize + Data([2, 3, 1])), .encryptionRequired)
        XCTAssertThrowsError(try ClickPacketDecoder.decode(ClickGATT.initialize + Data([1])))
    }
    func testBatteryBoundsAndUnknown() throws {
        XCTAssertEqual(try ClickPacketDecoder.decode(Data([0x19, 0x10, 100])), .battery(100))
        XCTAssertThrowsError(try ClickPacketDecoder.decode(Data([0x19, 0x10, 101])))
        XCTAssertThrowsError(try ClickPacketDecoder.decode(Data([0x19, 0x08, 12])))
        XCTAssertEqual(try ClickPacketDecoder.decode(Data([0x99, 1])), .unknown(0x99, Data([1])))
        XCTAssertEqual(try ClickPacketDecoder.decode(Data([0xFF, 0x05, 0x00, 0xEA, 0x05])), .stopped)
        XCTAssertEqual(try ClickPacketDecoder.decode(Data([0xFE])), .lostControl)
    }
    func testUnknownFieldsAreSkippedWithoutLosingBitmap() throws {
        let base = frame(UInt32.max)
        XCTAssertEqual(try ClickPacketDecoder.decode(base + Data([0x12, 0x02, 0x00, 0x00])), .buttons([], bitmap: .max))
    }
    func testManufacturerIdentityUsesThirdByte() {
        XCTAssertEqual(ManufacturerIdentity(data: Data([0x4A, 9, 0x0A]))?.side, .right)
        XCTAssertEqual(ManufacturerIdentity(data: Data([0x4A, 9, 0x0B]))?.side, .left)
        XCTAssertNil(ManufacturerIdentity(data: Data([0x4A, 9])))
        XCTAssertNil(ManufacturerIdentity(data: Data([0x4A, 9, 9])))
        XCTAssertNil(ManufacturerIdentity(data: Data([0, 9, 0x0A])))
    }
    private func frame(_ bitmap: UInt32) -> Data {
        var bytes: [UInt8] = [0x23, 0x08]
        var value = bitmap
        repeat {
            var byte = UInt8(value & 127); value >>= 7
            if value != 0 { byte |= 128 }; bytes.append(byte)
        } while value != 0
        return Data(bytes)
    }
}

final class ControllerTests: XCTestCase {
    func testPersistentDistinctAssignments() throws {
        let left = UUID(), right = UUID()
        var registry = ControllerRegistry()
        try registry.assign(left, to: .left); try registry.assign(right, to: .right)
        let copy = try JSONDecoder().decode(ControllerRegistry.self, from: JSONEncoder().encode(registry))
        XCTAssertEqual(copy.side(for: left), .left); XCTAssertEqual(copy.id(for: .right), right)
        XCTAssertThrowsError(try registry.assign(left, to: .right))
        XCTAssertThrowsError(try registry.assign(UUID(), to: .left))
        registry.remove(.left); try registry.assign(UUID(), to: .left)
    }
    func testDuplicatePressesDebounceAndLongRelease() {
        var tracker = ButtonTracker()
        XCTAssertEqual(tracker.update([.minus], at: 1).map(\.phase), [.down])
        XCTAssertTrue(tracker.update([.minus], at: 1.1).isEmpty)
        XCTAssertEqual(tracker.update([], at: 1.7).map(\.phase), [.up, .longPress])
        XCTAssertTrue(tracker.update([], at: 1.8).isEmpty)
        XCTAssertEqual(tracker.update([.minus], at: 2).map(\.phase), [.down])
        _ = tracker.update([], at: 2.01)
        XCTAssertTrue(tracker.update([.minus], at: 2.02).isEmpty)
    }
    func testTwoIndependentControllersAndReset() {
        var left = ButtonTracker(), right = ButtonTracker()
        XCTAssertEqual(left.update([.minus], at: 0).count, 1)
        XCTAssertEqual(right.update([.plus], at: 0).count, 1)
        left.reset()
        XCTAssertEqual(left.update([.minus], at: 2).count, 1)
        XCTAssertTrue(right.update([.plus], at: 2).isEmpty)
    }
    func testBoundedReconnectAndSuccessfulReset() {
        var policy = ReconnectPolicy()
        XCTAssertEqual((0..<8).compactMap { _ in policy.nextDelay() }, [1, 2, 4, 8, 16, 32, 60, 60])
        XCTAssertNil(policy.nextDelay()); policy.succeeded(); XCTAssertEqual(policy.nextDelay(), 1)
    }
    func testSessionRejectsLateInputAfterDisconnect() {
        var state = SessionMachine()
        XCTAssertFalse(state.advance(to: .receiving))
        let phases: [SessionPhase] = [.connecting, .discovering, .subscribing, .initializing, .awaitingInput, .receiving]
        for phase in phases {
            XCTAssertTrue(state.advance(to: phase))
        }
        XCTAssertTrue(state.advance(to: .disconnected))
        XCTAssertFalse(state.advance(to: .receiving)); XCTAssertFalse(state.advance(to: .awaitingInput))
        XCTAssertTrue(state.advance(to: .connecting))
        state.fail("test failure"); XCTAssertEqual(state.reason, "test failure")
    }
}

final class GearTests: XCTestCase {
    func testNoIntegrationMeansNoGearChange() throws {
        var engine = try GearEngine()
        XCTAssertThrowsError(try engine.request(.up, at: 0, integrationAvailable: false)) { XCTAssertEqual($0 as? GearError, .noIntegration) }
        XCTAssertNil(engine.acceptedGear); XCTAssertNil(engine.pending)
    }
    func testAcceptedOnlyAfterMatchingAcknowledgement() throws {
        var engine = try GearEngine()
        let request = try engine.request(.up, at: 0, integrationAvailable: true)
        XCTAssertEqual(request.gear, 13); XCTAssertNil(engine.acceptedGear)
        XCTAssertThrowsError(try engine.request(.down, at: 1, integrationAvailable: true))
        try engine.acknowledge(request, evidence: .softwareAccepted, at: 1)
        XCTAssertEqual(engine.acceptedGear, 13)
        XCTAssertThrowsError(try engine.acknowledge(request, evidence: .softwareAccepted, at: 2))
        XCTAssertThrowsError(try engine.request(.up, at: 1.01, integrationAvailable: true))
    }
    func testRejectedRequestDoesNotChangeSavedGear() throws {
        var engine = try GearEngine(lastAcceptedGear: 8)
        let request = try engine.request(.down, at: 1, integrationAvailable: true)
        engine.reject(request)
        XCTAssertEqual(engine.acceptedGear, 8); XCTAssertNil(engine.pending)
    }
    func testBothLimitsAndRatioIndex() throws {
        for (start, direction) in [(1, ShiftDirection.down), (24, ShiftDirection.up)] {
            var engine = try GearEngine(lastAcceptedGear: start)
            XCTAssertThrowsError(try engine.request(direction, at: 0, integrationAvailable: true))
        }
        var engine = try GearEngine(lastAcceptedGear: 23)
        let request = try engine.request(.up, at: 0, integrationAvailable: true)
        XCTAssertEqual(request.ratio, GearConfiguration.standard.ratios[23])
    }
    func testConfigurationValidationAndResize() throws {
        var config = GearConfiguration.standard; try config.validate()
        try config.resize(32); XCTAssertEqual(config.count, 32); try config.validate()
        config.ratios[1] = config.ratios[0]; XCTAssertThrowsError(try config.validate())
        config = .standard; config.startGear = 25; XCTAssertThrowsError(try config.validate())
        config = .standard; config.ratios[0] = .nan; XCTAssertThrowsError(try config.validate())
        config = .standard; config.shiftInterval = -1; XCTAssertThrowsError(try config.validate())
        config = .standard; config.bindings.append(config.bindings[0]); XCTAssertThrowsError(try config.validate())
    }
    func testSettingsRoundtripAndCorruptionRecovery() throws {
        var saved = SavedSettings(); saved.lastAcceptedGear = 19
        XCTAssertEqual(SavedSettings.restore(from: try JSONEncoder().encode(saved)), saved)
        XCTAssertEqual(SavedSettings.restore(from: Data("bad".utf8)), SavedSettings())
        saved.gearing.ratios = [-1, 0]
        XCTAssertEqual(SavedSettings.restore(from: try JSONEncoder().encode(saved)), SavedSettings())
    }
    func testOnlyPressEdgeShifts() {
        let config = GearConfiguration.standard
        XCTAssertEqual(config.direction(for: ButtonEvent(button: .minus, phase: .down, duration: 0)), .down)
        XCTAssertEqual(config.direction(for: ButtonEvent(button: .plus, phase: .down, duration: 0)), .up)
        XCTAssertNil(config.direction(for: ButtonEvent(button: .minus, phase: .longPress, duration: 2)))
    }
}
