import Foundation

private func ftmsExpect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("FTMS control test failed: \(message)\n".utf8))
        exit(1)
    }
}

@main
enum FTMSControlSelfTest {
    static func main() throws {
        let capabilities = try FTMSControlCodec.targetCapabilities(Data([
            0x00, 0x00, 0x00, 0x00,
            0x0E, 0x20, 0x00, 0x00
        ]))
        ftmsExpect(capabilities.inclination, "inclination capability")
        ftmsExpect(capabilities.resistance, "resistance capability")
        ftmsExpect(capabilities.power, "power capability")
        ftmsExpect(capabilities.indoorBikeSimulation, "simulation capability")

        let resistanceRange = try FTMSControlCodec.valueRange(
            Data([0x9C, 0xFF, 0xC8, 0x00, 0x05, 0x00]),
            resolution: 0.1
        )
        ftmsExpect(resistanceRange.minimum == -10, "resistance minimum")
        ftmsExpect(resistanceRange.maximum == 20, "resistance maximum")
        ftmsExpect(resistanceRange.increment == 0.5, "resistance increment")

        let powerRange = try FTMSControlCodec.valueRange(
            Data([0x32, 0x00, 0xE8, 0x03, 0x05, 0x00]),
            resolution: 1
        )
        let inclinationRange = resistanceRange

        let resistance = try FTMSControlCodec.encode(
            .setResistance(7.5),
            capabilities: capabilities,
            resistanceRange: resistanceRange,
            inclinationRange: inclinationRange,
            powerRange: powerRange
        )
        ftmsExpect(Array(resistance) == [0x04, 0x4B, 0x00], "resistance payload")

        let power = try FTMSControlCodec.encode(
            .setPower(253),
            capabilities: capabilities,
            resistanceRange: resistanceRange,
            inclinationRange: inclinationRange,
            powerRange: powerRange
        )
        ftmsExpect(Array(power) == [0x05, 0xFF, 0x00], "power quantization")

        let inclination = try FTMSControlCodec.encode(
            .setInclination(7.4),
            capabilities: capabilities,
            resistanceRange: resistanceRange,
            inclinationRange: inclinationRange,
            powerRange: powerRange
        )
        ftmsExpect(Array(inclination) == [0x03, 0x4B, 0x00], "inclination quantization")

        let simulation = try FTMSControlCodec.encode(
            .setSimulationGrade(6.25),
            capabilities: capabilities,
            resistanceRange: resistanceRange,
            inclinationRange: inclinationRange,
            powerRange: powerRange
        )
        ftmsExpect(
            Array(simulation) == [0x11, 0x00, 0x00, 0x71, 0x02, 40, 51],
            "simulation payload"
        )

        let response = try FTMSControlCodec.response(Data([0x80, 0x05, 0x01]))
        ftmsExpect(response == FTMSControlResponse(requestOpcode: 0x05, result: .success), "response")
        let controlLoss = try FTMSControlCodec.machineStatus(Data([0xFF]))
        let pause = try FTMSControlCodec.machineStatus(Data([0x02, 0x02]))
        ftmsExpect(controlLoss == .controlPermissionLost, "control loss")
        ftmsExpect(pause == .paused, "pause status")

        do {
            _ = try FTMSControlCodec.encode(
                .setSimulationGrade(25),
                capabilities: capabilities,
                resistanceRange: resistanceRange,
                inclinationRange: inclinationRange,
                powerRange: powerRange
            )
            ftmsExpect(false, "unsafe grade must fail")
        } catch FTMSControlError.outOfRange {
            // Expected.
        }

        do {
            _ = try FTMSControlCodec.response(Data([0x80, 0x05]))
            ftmsExpect(false, "truncated response must fail")
        } catch FTMSControlError.truncated {
            // Expected.
        }
        print("FTMS control self-test passed")
    }
}
