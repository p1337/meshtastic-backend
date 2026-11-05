import Foundation

private func cockpitExpect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("Cockpit configuration test failed: \(message)\n".utf8))
        exit(1)
    }
}

@main
enum CockpitConfigurationSelfTest {
    static func main() {
        cockpitExpect(
            CockpitConfiguration.allowedFieldCounts == [1, 2, 4, 6, 8],
            "only the five requested field counts may be offered"
        )
        cockpitExpect(
            CockpitConfiguration.defaultFields.count == CockpitConfiguration.maximumFieldCount,
            "every configurable slot needs a stable default"
        )
        cockpitExpect(
            Set(CockpitConfiguration.defaultFields.map(\.rawValue)).count
                == CockpitConfiguration.maximumFieldCount,
            "defaults should not duplicate fields"
        )
        cockpitExpect(
            CockpitConfiguration.normalizedFieldCount(4) == 4,
            "supported counts must remain unchanged"
        )
        cockpitExpect(
            CockpitConfiguration.normalizedFieldCount(3) == 6,
            "corrupt counts must fall back to the compact six-field layout"
        )
        cockpitExpect(
            CockpitConfiguration.field(rawValue: "heartRate", slot: 0) == .heartRate,
            "valid saved field identifiers must restore"
        )
        cockpitExpect(
            CockpitConfiguration.field(rawValue: "removed-field", slot: 7) == .power,
            "unknown identifiers must use the slot default"
        )
        print("Cockpit configuration self-test passed")
    }
}
