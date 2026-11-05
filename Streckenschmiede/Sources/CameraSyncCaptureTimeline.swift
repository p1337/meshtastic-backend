enum CameraSyncCaptureStage: Equatable {
    case preparing(secondsRemaining: Int)
    case exposing(secondsRemaining: Int)
    case complete
}

struct CameraSyncCaptureTimeline {
    static let preparationSeconds = 3
    static let minimumExposureSeconds = 5
    static let totalSeconds = preparationSeconds + minimumExposureSeconds

    static func stage(at elapsedSeconds: Int) -> CameraSyncCaptureStage {
        let elapsed = max(0, elapsedSeconds)
        if elapsed < preparationSeconds {
            return .preparing(secondsRemaining: preparationSeconds - elapsed)
        }
        if elapsed < totalSeconds {
            return .exposing(secondsRemaining: totalSeconds - elapsed)
        }
        return .complete
    }
}
