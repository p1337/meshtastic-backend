import Foundation

private func routeStoreExpect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) {
    guard condition() else {
        FileHandle.standardError.write(Data("RoutePlanStore test failed: \(message)\n".utf8))
        exit(1)
    }
}

@main
enum RoutePlanStoreSelfTest {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("route-store-test-\(UUID().uuidString)", isDirectory: true)
        let url = root.appendingPathComponent("active-route.json")
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = RideRoutePlan(
            destinationName: "Testziel",
            providerName: "Apple Fahrrad",
            summary: "Testziel · 1,2 km",
            distanceMeters: 1_200,
            expectedTravelTime: 300,
            points: [
                RoutePoint(latitude: 48, longitude: 9),
                RoutePoint(latitude: 48.01, longitude: 9.01)
            ],
            maneuvers: [RouteManeuver(
                instruction: "Rechts abbiegen",
                distanceAlongRouteMeters: 500
            )]
        )

        let missing = try RoutePlanStore.load(from: url)
        routeStoreExpect(missing == nil, "missing file is empty")
        try RoutePlanStore.save(plan, to: url, now: Date(timeIntervalSince1970: 2_000_000_000))
        let restored = try RoutePlanStore.load(from: url)
        routeStoreExpect(restored == plan, "atomic roundtrip")
        try RoutePlanStore.clear(at: url)
        let cleared = try RoutePlanStore.load(from: url)
        routeStoreExpect(cleared == nil, "clear removes route")

        let invalid = RideRoutePlan(
            destinationName: "Ungültig",
            providerName: "Test",
            summary: "Ungültig",
            distanceMeters: 1,
            expectedTravelTime: 1,
            points: [
                RoutePoint(latitude: 200, longitude: 9),
                RoutePoint(latitude: 48, longitude: 9)
            ],
            maneuvers: []
        )
        do {
            try RoutePlanStore.save(invalid, to: url)
            routeStoreExpect(false, "invalid coordinates must fail")
        } catch {
            routeStoreExpect(!FileManager.default.fileExists(atPath: url.path), "invalid route was not written")
        }
        print("RoutePlanStore self-test passed")
    }
}
