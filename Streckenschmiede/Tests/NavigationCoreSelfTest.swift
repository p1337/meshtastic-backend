import Foundation

private func navigationExpect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) {
    guard condition() else {
        FileHandle.standardError.write(Data("NavigationCore test failed: \(message)\n".utf8))
        exit(1)
    }
}

@main
enum NavigationCoreSelfTest {
    static func main() {
        let route = [
            RoutePoint(latitude: 48, longitude: 9),
            RoutePoint(latitude: 48, longitude: 9.01),
            RoutePoint(latitude: 48.01, longitude: 9.01)
        ]
        let length = NavigationProgressEngine.routeLengthMeters(route)
        let turnDistance = NavigationProgressEngine.distanceAlongRoute(
            to: route[1],
            route: route
        ) ?? -1
        let plan = RideRoutePlan(
            destinationName: "Testziel",
            providerName: "Test",
            summary: "Teststrecke",
            distanceMeters: length,
            expectedTravelTime: 600,
            points: route,
            maneuvers: [RouteManeuver(
                instruction: "Links abbiegen",
                distanceAlongRouteMeters: turnDistance
            )]
        )

        let beforeTurn = NavigationProgressEngine.progress(
            position: RoutePoint(latitude: 48, longitude: 9.009),
            plan: plan
        )
        navigationExpect(beforeTurn != nil, "progress exists")
        navigationExpect(beforeTurn?.nextManeuver?.instruction == "Links abbiegen", "next maneuver")
        navigationExpect((beforeTurn?.distanceToNextManeuverMeters ?? 0) > 50, "distance to maneuver")
        navigationExpect((beforeTurn?.remainingDistanceMeters ?? 0) > 1_000, "remaining distance")
        navigationExpect((beforeTurn?.remainingTravelTime ?? 0) > 0, "remaining time")

        let offRoute = NavigationProgressEngine.progress(
            position: RoutePoint(latitude: 48.001, longitude: 9.005),
            plan: plan
        )
        navigationExpect((offRoute?.distanceFromRouteMeters ?? 0) > 100, "cross-track distance")

        let afterTurn = NavigationProgressEngine.progress(
            position: RoutePoint(latitude: 48.005, longitude: 9.01),
            plan: plan
        )
        navigationExpect(afterTurn?.nextManeuver == nil, "passed maneuver is removed")
        navigationExpect((afterTurn?.remainingDistanceMeters ?? .infinity) < length / 2, "remaining route shrinks")
        print("NavigationCore self-test passed")
    }
}
