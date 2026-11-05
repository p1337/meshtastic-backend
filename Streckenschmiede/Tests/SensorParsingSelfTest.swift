import Foundation

private func sensorExpect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("Sensor parser test failed: \(message)\n".utf8))
        exit(1)
    }
}

@main
enum SensorParsingSelfTest {
    static func main() throws {
        let heartRate = try BikeSensorParser.heartRate(Data([0x16, 72, 0x00, 0x04]))
        sensorExpect(heartRate.beatsPerMinute == 72, "heart rate")
        sensorExpect(heartRate.contactDetected == true, "contact status")
        sensorExpect(heartRate.rrIntervalsSeconds == [1], "RR interval")

        let csc = try BikeSensorParser.cyclingSpeedAndCadence(Data([
            0x03,
            0x10, 0x00, 0x00, 0x00,
            0x00, 0x04,
            0x20, 0x00,
            0x00, 0x08
        ]))
        sensorExpect(csc.wheelRevolutions == 16, "wheel revolutions")
        sensorExpect(csc.wheelEventTime == 1_024, "wheel time")
        sensorExpect(csc.crankRevolutions == 32, "crank revolutions")
        sensorExpect(csc.crankEventTime == 2_048, "crank time")

        let power = try BikeSensorParser.cyclingPower(Data([0x01, 0x00, 0xFA, 0x00, 100]))
        sensorExpect(power.watts == 250, "cycling power")
        sensorExpect(power.pedalPowerBalancePercent == 50, "power balance")

        let indoor = try BikeSensorParser.indoorBikeData(Data([
            0x44, 0x02,
            0xC4, 0x09,
            0xB4, 0x00,
            0xFA, 0x00,
            150
        ]))
        sensorExpect(indoor.speedKmh == 25, "FTMS speed")
        sensorExpect(indoor.cadenceRpm == 90, "FTMS cadence")
        sensorExpect(indoor.powerWatts == 250, "FTMS power")
        sensorExpect(indoor.heartRateBpm == 150, "FTMS heart rate")
        let battery = try BikeSensorParser.batteryLevel(Data([87]))
        sensorExpect(battery == 87, "battery")
        let positiveTemperature = try BikeSensorParser.temperatureCelsius(Data([0x29, 0x09]))
        sensorExpect(positiveTemperature == 23.45, "positive environmental temperature")
        let negativeTemperature = try BikeSensorParser.temperatureCelsius(Data([0xF3, 0xFD]))
        sensorExpect(negativeTemperature == -5.25, "negative environmental temperature")

        do {
            _ = try BikeSensorParser.cyclingPower(Data([0x00]))
            sensorExpect(false, "truncated packet must fail")
        } catch SensorParseError.truncated {
            // Expected.
        }
        do {
            _ = try BikeSensorParser.temperatureCelsius(Data([0x01]))
            sensorExpect(false, "truncated temperature must fail")
        } catch SensorParseError.truncated {
            // Expected.
        }
        print("Sensor parser self-test passed")
    }
}
