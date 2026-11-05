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
        mapCameraExpect(flat == 240, "flat look-ahead must remain a small safe camera fraction")
        mapCameraExpect(pitched == 180, "pitched look-ahead must be reduced further")
        mapCameraExpect(pitched < flat, "3D camera must not push the rider farther toward the edge")
        mapCameraExpect(
            MapCameraPolicy.lookAheadDistance(zoomMeters: -1, is3D: false) == 40,
            "invalid low zoom values must be clamped"
        )
        mapCameraExpect(
            MapCameraPolicy.lookAheadDistance(zoomMeters: 50_000, is3D: true) == 1_200,
            "invalid high zoom values must be clamped"
        )
        print("Map camera policy self-test passed")
    }
}
