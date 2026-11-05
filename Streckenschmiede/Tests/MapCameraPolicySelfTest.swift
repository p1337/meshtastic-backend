import Foundation

private func mapCameraExpect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("Map camera policy test failed: \(message)\n".utf8))
        exit(1)
    }
}

private func mapCameraApproximatelyEqual(_ left: Double, _ right: Double) -> Bool {
    abs(left - right) < 0.000_001
}

@main
enum MapCameraPolicySelfTest {
    static func main() {
        let flat = MapCameraPolicy.lookAheadDistance(zoomMeters: 1_500, is3D: false)
        let pitched = MapCameraPolicy.lookAheadDistance(zoomMeters: 1_500, is3D: true)
        mapCameraExpect(
            mapCameraApproximatelyEqual(flat, 330),
            "flat look-ahead must hold the rider in the lower map third"
        )
        mapCameraExpect(
            mapCameraApproximatelyEqual(pitched, 330),
            "pitched look-ahead must hold the rider in the lower map third"
        )
        mapCameraExpect(
            mapCameraApproximatelyEqual(
                MapCameraPolicy.lookAheadDistance(zoomMeters: -1, is3D: false),
                55
            ),
            "invalid low zoom values must be clamped"
        )
        mapCameraExpect(
            mapCameraApproximatelyEqual(
                MapCameraPolicy.lookAheadDistance(zoomMeters: 50_000, is3D: true),
                2_200
            ),
            "invalid high zoom values must be clamped"
        )
        mapCameraExpect(
            MapCameraPolicy.pitchDegrees(is3DEnabled: true, visualTiltDegrees: 30) == 60,
            "the full rider-facing tilt must create a clearly inclined MapKit camera"
        )
        mapCameraExpect(
            MapCameraPolicy.pitchDegrees(is3DEnabled: false, visualTiltDegrees: 30) == 0,
            "disabled 3D must return to a flat map"
        )
        mapCameraExpect(
            MapCameraPolicy.pitchDegrees(is3DEnabled: true, visualTiltDegrees: 100) == 60
                && MapCameraPolicy.pitchDegrees(is3DEnabled: true, visualTiltDegrees: -10) == 0,
            "saved tilt values must remain inside the supported 0...30 degree range"
        )
        let phoneHeight = 844.0
        let controlTop = phoneHeight - 34 - 84
        let riderY = MapCameraPolicy.riderScreenY(
            viewHeight: phoneHeight,
            controlHitSize: 84,
            controlsBottomPadding: 34,
            markerDiameter: 42
        )
        mapCameraExpect(
            mapCameraApproximatelyEqual(riderY, phoneHeight * 2 / 3),
            "normal screens must anchor the rider one third above the bottom"
        )
        mapCameraExpect(
            riderY + 21 + MapCameraPolicy.minimumRiderControlGap <= controlTop,
            "the rider marker must never enter the bottom control hit area"
        )
        let compactRiderY = MapCameraPolicy.riderScreenY(
            viewHeight: 300,
            controlHitSize: 84,
            controlsBottomPadding: 34,
            markerDiameter: 42
        )
        mapCameraExpect(
            compactRiderY + 21 + MapCameraPolicy.minimumRiderControlGap <= 300 - 34 - 84,
            "compact screens must move the rider upward before controls overlap"
        )
        let navigationRiderY = MapCameraPolicy.riderScreenY(
            viewHeight: 568,
            controlHitSize: 84,
            controlsBottomPadding: 34,
            markerDiameter: 42,
            additionalBottomReservedHeight: 82
        )
        mapCameraExpect(
            navigationRiderY + 21 + MapCameraPolicy.minimumRiderControlGap
                <= 568 - 34 - 84 - 82,
            "an active navigation banner must also reserve space above the rider"
        )
        print("Map camera policy self-test passed")
    }
}
