import Foundation

private func autoPauseExpect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) {
    guard condition() else {
        FileHandle.standardError.write(Data("AutoPauseController test failed: \(message)\n".utf8))
        exit(1)
    }
}

@main
enum AutoPauseControllerSelfTest {
    static func main() {
        let base = Date(timeIntervalSince1970: 2_000_000_000)
        let enabled = AutoPauseConfiguration(
            enabled: true,
            pauseBelowKmh: 2.5,
            pauseDelaySeconds: 8
        )
        let controller = AutoPauseController()

        autoPauseExpect(
            controller.evaluate(speedKmh: 1, at: base, configuration: enabled) == .none,
            "low-speed timer starts without immediate pause"
        )
        autoPauseExpect(
            controller.evaluate(speedKmh: 1, at: base.addingTimeInterval(7), configuration: enabled) == .none,
            "pause delay is respected"
        )
        autoPauseExpect(
            controller.evaluate(speedKmh: 1, at: base.addingTimeInterval(8), configuration: enabled) == .pause,
            "sustained low speed pauses"
        )
        autoPauseExpect(controller.isAutomaticallyPaused, "automatic owner is visible")
        autoPauseExpect(
            controller.evaluate(speedKmh: 3.9, at: base.addingTimeInterval(9), configuration: enabled) == .none,
            "resume hysteresis rejects GPS jitter"
        )
        autoPauseExpect(
            controller.evaluate(speedKmh: 4, at: base.addingTimeInterval(10), configuration: enabled) == .resume,
            "movement resumes automatically"
        )

        controller.manualPause()
        autoPauseExpect(
            controller.evaluate(speedKmh: 30, at: base.addingTimeInterval(11), configuration: enabled) == .none,
            "manual pause cannot be overridden by movement"
        )
        controller.manualResume()
        autoPauseExpect(
            controller.evaluate(speedKmh: 1, at: base.addingTimeInterval(20), configuration: enabled) == .none,
            "manual resume resets the low-speed timer"
        )
        autoPauseExpect(
            controller.evaluate(speedKmh: 1, at: base.addingTimeInterval(28), configuration: enabled) == .pause,
            "second low-speed period pauses"
        )
        let disabled = AutoPauseConfiguration(
            enabled: false,
            pauseBelowKmh: 2.5,
            pauseDelaySeconds: 8
        )
        autoPauseExpect(
            controller.evaluate(speedKmh: 0, at: base.addingTimeInterval(29), configuration: disabled) == .resume,
            "disabling auto-pause releases an automatic pause"
        )
        print("AutoPauseController self-test passed")
    }
}
