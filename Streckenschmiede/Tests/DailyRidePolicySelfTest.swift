import Foundation

private func dailyRideExpect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("Daily ride policy test failed: \(message)\n".utf8))
        exit(1)
    }
}

@main
enum DailyRidePolicySelfTest {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        dailyRideExpect(
            !DailyRidePolicy.requiresRollover(
                startedAt: start,
                now: start.addingTimeInterval(60 * 60),
                calendar: calendar
            ),
            "one calendar day must remain one automatic ride"
        )
        dailyRideExpect(
            DailyRidePolicy.requiresRollover(
                startedAt: start,
                now: start.addingTimeInterval(24 * 60 * 60),
                calendar: calendar
            ),
            "the next calendar day must start a new ride"
        )
        dailyRideExpect(
            !DailyRidePolicy.requiresRollover(startedAt: nil, now: start, calendar: calendar),
            "an empty session cannot require rollover"
        )
        print("Daily ride policy self-test passed")
    }
}
