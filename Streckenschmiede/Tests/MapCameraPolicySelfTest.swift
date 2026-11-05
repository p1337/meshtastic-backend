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
            MapCameraPolicy.pitchDegrees(is3DEnabled: true) == 55,
            "3D must tilt the map even before a valid travel course exists"
        )
        mapCameraExpect(
            MapCameraPolicy.pitchDegrees(is3DEnabled: false) == 0,
            "disabled 3D must return to a flat map"
        )
        print("Map camera policy self-test passed")
    }
}
