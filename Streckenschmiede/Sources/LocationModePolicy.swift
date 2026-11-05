import Foundation

enum LocationActivityMode: Equatable {
    case off
    case foregroundLive
    case recordingBackground
}

enum LocationModePolicy {
    static func mode(
        isAuthorized: Bool,
        servicesEnabled: Bool,
        applicationIsActive: Bool,
        isRecording: Bool
    ) -> LocationActivityMode {
        guard isAuthorized, servicesEnabled else { return .off }
        if isRecording { return .recordingBackground }
        return applicationIsActive ? .foregroundLive : .off
    }
}
