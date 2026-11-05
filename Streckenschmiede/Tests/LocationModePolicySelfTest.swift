import Foundation

private func locationExpect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("Location policy test failed: \(message)\n".utf8))
        exit(1)
    }
}

@main
enum LocationModePolicySelfTest {
    static func main() {
        locationExpect(
            LocationModePolicy.mode(
                isAuthorized: true,
                servicesEnabled: true,
                applicationIsActive: true,
                isRecording: false
            ) == .foregroundLive,
            "the open app must keep live location active before recording"
        )
        locationExpect(
            LocationModePolicy.mode(
                isAuthorized: true,
                servicesEnabled: true,
                applicationIsActive: false,
                isRecording: true
            ) == .recordingBackground,
            "an active ride must keep background location active"
        )
        locationExpect(
            LocationModePolicy.mode(
                isAuthorized: true,
                servicesEnabled: true,
                applicationIsActive: false,
                isRecording: false
            ) == .off,
            "an idle background app must not drain the battery"
        )
        locationExpect(
            LocationModePolicy.mode(
                isAuthorized: false,
                servicesEnabled: true,
                applicationIsActive: true,
                isRecording: true
            ) == .off,
            "authorization remains mandatory"
        )
        print("Location mode policy self-test passed")
    }
}
