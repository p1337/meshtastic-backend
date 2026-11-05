import Foundation

enum AutoPauseAction: Equatable {
    case none
    case pause
    case resume
}

struct AutoPauseConfiguration: Equatable {
    var enabled: Bool
    var pauseBelowKmh: Double
    var pauseDelaySeconds: TimeInterval

    var resumeAboveKmh: Double {
        max(4, pauseBelowKmh + 1.5)
    }
}

/// Deterministic auto-pause state machine. Manual pause always owns the session
/// until the rider explicitly resumes it; GPS movement must never override it.
final class AutoPauseController {
    private enum PauseOwner: Equatable {
        case none
        case automatic
        case manual
    }

    private var pauseOwner: PauseOwner = .none
    private var belowThresholdSince: Date?

    var isAutomaticallyPaused: Bool { pauseOwner == .automatic }

    func reset() {
        pauseOwner = .none
        belowThresholdSince = nil
    }

    func manualPause() {
        pauseOwner = .manual
        belowThresholdSince = nil
    }

    func manualResume() {
        pauseOwner = .none
        belowThresholdSince = nil
    }

    func evaluate(
        speedKmh: Double?,
        at timestamp: Date,
        configuration: AutoPauseConfiguration
    ) -> AutoPauseAction {
        if !configuration.enabled {
            belowThresholdSince = nil
            if pauseOwner == .automatic {
                pauseOwner = .none
                return .resume
            }
            return .none
        }

        guard let speedKmh, speedKmh >= 0 else {
            belowThresholdSince = nil
            return .none
        }

        switch pauseOwner {
        case .manual:
            return .none
        case .automatic:
            guard speedKmh >= configuration.resumeAboveKmh else { return .none }
            pauseOwner = .none
            belowThresholdSince = nil
            return .resume
        case .none:
            guard speedKmh <= configuration.pauseBelowKmh else {
                belowThresholdSince = nil
                return .none
            }
            if belowThresholdSince == nil {
                belowThresholdSince = timestamp
            }
            guard let belowThresholdSince,
                  timestamp.timeIntervalSince(belowThresholdSince) >= configuration.pauseDelaySeconds else {
                return .none
            }
            pauseOwner = .automatic
            self.belowThresholdSince = nil
            return .pause
        }
    }
}
