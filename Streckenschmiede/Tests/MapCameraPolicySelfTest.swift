import Foundation

private func mapCameraExpect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("Map camera policy test failed: \(message)\n".utf8))
        exit(1)
    }
}

@main
enum MapCameraPolicySelfTest {
    static func main() {
        let flat = MapCameraPolicy.lookAheadDistance(zoomMeters: 1_500, is3D: false)
        let pitched = MapCameraPolicy.lookAheadDistance(zoomMeters: 1_500, is3D: true)
        mapCameraExpect(flat == 180, "flat look-ahead must remain a small safe camera fraction")
        mapCameraExpect(pitched == 120, "pitched look-ahead must be reduced further")
        mapCameraExpect(pitched < flat, "3D camera must not push the rider farther toward the edge")
        mapCameraExpect(
            MapCameraPolicy.lookAheadDistance(zoomMeters: -1, is3D: false) == 30,
            "invalid low zoom values must be clamped"
        )
        mapCameraExpect(
            MapCameraPolicy.lookAheadDistance(zoomMeters: 50_000, is3D: true) == 800,
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
