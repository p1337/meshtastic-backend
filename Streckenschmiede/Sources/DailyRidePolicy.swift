import Foundation

/// Defines the calendar boundary for automatic day rides independently from
/// GPS and UI state. A recoverable session from the same local calendar day is
/// continued; an older session is closed before a new day starts.
enum DailyRidePolicy {
    static func requiresRollover(
        startedAt: Date?,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        guard let startedAt else { return false }
        return !calendar.isDate(startedAt, inSameDayAs: now)
    }
}
