import CoreBluetooth
import Combine
import Foundation

struct SensorDeviceSnapshot: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rssi: Int
    var connectionState: String
    var services: [String]
    var heartRateBpm: Int?
    var cadenceRpm: Double?
    var powerWatts: Int?
    var pedalBalancePercent: Double?
    var speedKmh: Double?
    var temperatureCelsius: Double?
    var batteryPercent: Int?
    var manufacturer: String?
    var model: String?
    var canControlFTMS: Bool

    var isConnected: Bool { connectionState == "Verbunden" }
}

final class SensorHub: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published private(set) var status = "Bluetooth wird gestartet"
    @Published private(set) var devices: [SensorDeviceSnapshot] = []
    @Published private(set) var heartRateBpm: Int?
    @Published private(set) var cadenceRpm: Double?
    @Published private(set) var powerWatts: Int?
    @Published private(set) var speedKmh: Double?
    @Published private(set) var pedalBalancePercent: Double?
    @Published private(set) var resistanceLevel: Double?
    @Published private(set) var temperatureCelsius: Double?
    @Published private(set) var batteryPercent: Int?
    @Published private(set) var trainerDeviceID: UUID?
    @Published private(set) var trainerName: String?
    @Published private(set) var trainerControlStatus = "Kein steuerbarer FTMS-Trainer gewählt"
    @Published private(set) var trainerCapabilities = FTMSTargetCapabilities()
    @Published private(set) var trainerResistanceRange: FTMSValueRange?
    @Published private(set) var trainerInclinationRange: FTMSValueRange?
    @Published private(set) var trainerPowerRange: FTMSValueRange?
    @Published private(set) var trainerHasControl = false
    @Published private(set) var trainerCommandInFlight = false
    @Published private(set) var trainerIsRunning = false
    @Published private(set) var trainerTargetResistance: Double?
    @Published private(set) var trainerTargetPower: Int?
    @Published private(set) var trainerTargetGrade: Double?

    var wheelCircumferenceMeters = 2.105

    private var manager: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var records: [UUID: SensorDeviceSnapshot] = [:]
    private var desiredConnections: Set<UUID> = []
    private var revolutionStates: [UUID: RevolutionState] = [:]
    private var heartRateSource: UUID?
    private var cadenceSource: UUID?
    private var powerSource: UUID?
    private var speedSource: UUID?
    private var batterySource: UUID?
    private var balanceSource: UUID?
    private var resistanceSource: UUID?
    private var temperatureSource: UUID?
    private var ftmsControlPoints: [UUID: CBCharacteristic] = [:]
    private var ftmsCapabilities: [UUID: FTMSTargetCapabilities] = [:]
    private var ftmsResistanceRanges: [UUID: FTMSValueRange] = [:]
    private var ftmsInclinationRanges: [UUID: FTMSValueRange] = [:]
    private var ftmsPowerRanges: [UUID: FTMSValueRange] = [:]
    private var trainerPendingCommand: FTMSControlCommand?
    private var trainerCommandTimeout: DispatchWorkItem?

    private static let supportedServices: [CBUUID] = [
        CBUUID(string: "180D"), CBUUID(string: "1816"), CBUUID(string: "1818"),
        CBUUID(string: "1826"), CBUUID(string: "180F"), CBUUID(string: "180A"),
        CBUUID(string: "181A"), CBUUID(string: "1819")
    ]

    override init() {
        super.init()
        manager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "de.p1337.Streckenschmiede.SensorHub"]
        )
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: status = "Bluetooth bereit"
        case .poweredOff: status = "Bluetooth ist ausgeschaltet"
        case .unauthorized: status = "Bluetooth-Zugriff nicht erlaubt"
        case .unsupported: status = "Bluetooth LE nicht unterstützt"
        case .resetting: status = "Bluetooth wird zurückgesetzt"
        case .unknown: status = "Bluetooth-Status unbekannt"
        @unknown default: status = "Bluetooth nicht verfügbar"
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] else {
            return
        }
        for peripheral in restored {
            peripheral.delegate = self
            peripherals[peripheral.identifier] = peripheral
            desiredConnections.insert(peripheral.identifier)
            ensureRecord(for: peripheral, name: peripheral.name, rssi: 0)
            updateConnectionState(for: peripheral)
            if peripheral.state == .connected {
                peripheral.discoverServices(Self.supportedServices)
            }
        }
        status = "Sensorverbindungen wiederhergestellt"
    }

    func scan() {
        guard manager.state == .poweredOn else {
            status = "Bluetooth nicht bereit"
            return
        }
        manager.stopScan()
        manager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        status = "Suche nach Fahrradsensoren"
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self else { return }
            self.manager.stopScan()
            if self.status == "Suche nach Fahrradsensoren" {
                self.status = self.devices.isEmpty
                    ? "Keine Bluetooth-Geräte gefunden"
                    : "\(self.devices.count) Geräte gefunden"
            }
        }
    }

    func toggleConnection(_ id: UUID) {
        guard let peripheral = peripherals[id] else { return }
        if peripheral.state == .connected || peripheral.state == .connecting {
            if trainerDeviceID == id, trainerIsRunning {
                trainerControlStatus = "Zuerst den Trainer mit Not-Stopp anhalten"
                return
            }
            desiredConnections.remove(id)
            manager.cancelPeripheralConnection(peripheral)
        } else {
            desiredConnections.insert(id)
            records[id]?.connectionState = "Verbindet"
            publishDevices()
            manager.connect(peripheral)
        }
    }

    func selectTrainer(_ id: UUID) {
        guard let peripheral = peripherals[id], peripheral.state == .connected,
              records[id]?.canControlFTMS == true,
              ftmsControlPoints[id] != nil else {
            trainerControlStatus = "FTMS-Steuerung dieses Geräts ist noch nicht bereit"
            return
        }
        guard !trainerCommandInFlight else {
            trainerControlStatus = "Der laufende Trainerbefehl muss zuerst bestätigt werden"
            return
        }
        guard !trainerIsRunning || trainerDeviceID == id else {
            trainerControlStatus = "Den bisherigen Trainer zuerst mit Not-Stopp anhalten"
            return
        }
        trainerCommandTimeout?.cancel()
        trainerPendingCommand = nil
        trainerDeviceID = id
        trainerName = displayName(for: peripheral)
        trainerHasControl = false
        trainerIsRunning = false
        trainerTargetResistance = nil
        trainerTargetPower = nil
        trainerTargetGrade = nil
        publishTrainerMetadata(for: id)
        trainerControlStatus = (trainerName ?? "Trainer") + " gewählt – Steuerung anfordern"
    }

    func requestTrainerControl() { sendTrainerCommand(.requestControl) }
    func startTrainer() { sendTrainerCommand(.startOrResume) }
    func pauseTrainer() { sendTrainerCommand(.pause) }
    func emergencyStopTrainer() { sendTrainerCommand(.stop) }
    func setTrainerResistance(_ value: Double) { sendTrainerCommand(.setResistance(value)) }
    func setTrainerPower(_ watts: Int) { sendTrainerCommand(.setPower(watts)) }

    func setTrainerGrade(_ percent: Double) {
        if trainerCapabilities.indoorBikeSimulation {
            sendTrainerCommand(.setSimulationGrade(percent))
        } else {
            sendTrainerCommand(.setInclination(percent))
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        ensureRecord(for: peripheral, name: peripheral.name ?? advertisedName, rssi: RSSI.intValue)
        if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            addServiceNames(serviceUUIDs, to: peripheral.identifier)
        }
        peripherals[peripheral.identifier] = peripheral
        peripheral.delegate = self
        publishDevices()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        updateConnectionState(for: peripheral)
        status = "\(displayName(for: peripheral)) verbunden"
        peripheral.discoverServices(Self.supportedServices)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        desiredConnections.remove(peripheral.identifier)
        records[peripheral.identifier]?.connectionState = "Fehler"
        publishDevices()
        status = error?.localizedDescription ?? "Sensorverbindung fehlgeschlagen"
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        updateConnectionState(for: peripheral)
        clearLiveValues(from: peripheral.identifier)
        clearTrainerSelection(deviceID: peripheral.identifier)
        records[peripheral.identifier]?.canControlFTMS = false
        ftmsControlPoints.removeValue(forKey: peripheral.identifier)
        ftmsCapabilities.removeValue(forKey: peripheral.identifier)
        ftmsResistanceRanges.removeValue(forKey: peripheral.identifier)
        ftmsInclinationRanges.removeValue(forKey: peripheral.identifier)
        ftmsPowerRanges.removeValue(forKey: peripheral.identifier)
        publishDevices()
        if desiredConnections.contains(peripheral.identifier), central.state == .poweredOn {
            records[peripheral.identifier]?.connectionState = "Verbindet"
            publishDevices()
            central.connect(peripheral)
        } else if let error {
            status = "Sensor getrennt: \(error.localizedDescription)"
        } else {
            status = "Sensor getrennt"
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            status = "Dienste nicht lesbar: \(error.localizedDescription)"
            return
        }
        let services = peripheral.services ?? []
        addServiceNames(services.map(\.uuid), to: peripheral.identifier)
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            status = "Sensordaten nicht lesbar: \(error.localizedDescription)"
            return
        }
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid.uuidString.uppercased() == "2AD9",
               characteristic.properties.contains(.write) {
                ftmsControlPoints[peripheral.identifier] = characteristic
            }
            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid.uuidString.uppercased() == "2AD9" else { return }
        let id = peripheral.identifier
        if let error {
            records[id]?.canControlFTMS = false
            publishDevices()
            if trainerDeviceID == id {
                trainerControlStatus = "FTMS-Bestätigungen nicht verfügbar: \(error.localizedDescription)"
            }
            return
        }
        records[id]?.canControlFTMS = characteristic.isNotifying
        publishDevices()
        if trainerDeviceID == id, !characteristic.isNotifying {
            loseTrainerControl("FTMS-Bestätigungen wurden deaktiviert")
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let data = characteristic.value else { return }
        let id = peripheral.identifier
        do {
            switch characteristic.uuid.uuidString.uppercased() {
            case "2A37":
                let measurement = try BikeSensorParser.heartRate(data)
                records[id]?.heartRateBpm = measurement.beatsPerMinute
                heartRateBpm = measurement.beatsPerMinute
                heartRateSource = id
            case "2A5B":
                updateRevolutions(
                    try BikeSensorParser.cyclingSpeedAndCadence(data),
                    deviceID: id
                )
            case "2A63":
                let measurement = try BikeSensorParser.cyclingPower(data)
                records[id]?.powerWatts = measurement.watts
                powerWatts = measurement.watts
                powerSource = id
                pedalBalancePercent = measurement.pedalPowerBalancePercent
                if let balance = measurement.pedalPowerBalancePercent {
                    records[id]?.pedalBalancePercent = balance
                    balanceSource = id
                }
                updateRevolutions(
                    RevolutionMeasurement(
                        wheelRevolutions: measurement.wheelRevolutions,
                        wheelEventTime: measurement.wheelEventTime,
                        crankRevolutions: measurement.crankRevolutions,
                        crankEventTime: measurement.crankEventTime
                    ),
                    deviceID: id
                )
            case "2AD2":
                let measurement = try BikeSensorParser.indoorBikeData(data)
                if let value = measurement.speedKmh { records[id]?.speedKmh = value; speedKmh = value; speedSource = id }
                if let value = measurement.cadenceRpm { records[id]?.cadenceRpm = value; cadenceRpm = value; cadenceSource = id }
                if let value = measurement.powerWatts { records[id]?.powerWatts = value; powerWatts = value; powerSource = id }
                if let value = measurement.heartRateBpm { records[id]?.heartRateBpm = value; heartRateBpm = value; heartRateSource = id }
                if let value = measurement.resistanceLevel {
                    resistanceLevel = value
                    resistanceSource = id
                }
            case "2A19":
                let level = try BikeSensorParser.batteryLevel(data)
                records[id]?.batteryPercent = level
                batteryPercent = level
                batterySource = id
            case "2A6E":
                let value = try BikeSensorParser.temperatureCelsius(data)
                records[id]?.temperatureCelsius = value
                temperatureCelsius = value
                temperatureSource = id
            case "2A29": records[id]?.manufacturer = decodedString(data)
            case "2A24": records[id]?.model = decodedString(data)
            case "2ACC":
                ftmsCapabilities[id] = try FTMSControlCodec.targetCapabilities(data)
                if trainerDeviceID == id { publishTrainerMetadata(for: id) }
            case "2AD5":
                ftmsInclinationRanges[id] = try FTMSControlCodec.valueRange(data, resolution: 0.1)
                if trainerDeviceID == id { publishTrainerMetadata(for: id) }
            case "2AD6":
                ftmsResistanceRanges[id] = try FTMSControlCodec.valueRange(data, resolution: 0.1)
                if trainerDeviceID == id { publishTrainerMetadata(for: id) }
            case "2AD8":
                ftmsPowerRanges[id] = try FTMSControlCodec.valueRange(data, resolution: 1)
                if trainerDeviceID == id { publishTrainerMetadata(for: id) }
            case "2AD9":
                handleTrainerResponse(try FTMSControlCodec.response(data), deviceID: id)
            case "2ADA":
                handleTrainerStatus(try FTMSControlCodec.machineStatus(data), deviceID: id)
            default: break
            }
            publishDevices()
        } catch SensorParseError.truncated {
            status = "Unvollständiges Sensorpaket von \(displayName(for: peripheral))"
        } catch {
            status = "Sensordaten konnten nicht gelesen werden"
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid.uuidString.uppercased() == "2AD9",
              trainerDeviceID == peripheral.identifier,
              trainerPendingCommand != nil else { return }
        if let error {
            failTrainerCommand("Trainerbefehl konnte nicht gesendet werden: \(error.localizedDescription)")
        }
    }

    private func sendTrainerCommand(_ command: FTMSControlCommand) {
        guard !trainerCommandInFlight else {
            trainerControlStatus = "Der vorige Trainerbefehl wartet noch auf Bestätigung"
            return
        }
        guard let id = trainerDeviceID,
              let peripheral = peripherals[id], peripheral.state == .connected,
              let controlPoint = ftmsControlPoints[id],
              records[id]?.canControlFTMS == true else {
            trainerControlStatus = "Kein steuerbarer FTMS-Trainer verbunden"
            return
        }
        if command != .requestControl, !trainerHasControl {
            trainerControlStatus = "Zuerst die Trainersteuerung anfordern"
            return
        }
        do {
            let payload = try FTMSControlCodec.encode(
                command,
                capabilities: ftmsCapabilities[id] ?? FTMSTargetCapabilities(),
                resistanceRange: ftmsResistanceRanges[id],
                inclinationRange: ftmsInclinationRanges[id],
                powerRange: ftmsPowerRanges[id]
            )
            trainerPendingCommand = command
            trainerCommandInFlight = true
            trainerControlStatus = "\(command.title) …"
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, self.trainerPendingCommand == command else { return }
                self.failTrainerCommand("Keine Bestätigung vom Trainer – Befehl abgebrochen")
            }
            trainerCommandTimeout?.cancel()
            trainerCommandTimeout = timeout
            peripheral.writeValue(payload, for: controlPoint, type: .withResponse)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
        } catch FTMSControlError.unsupported {
            trainerControlStatus = "Diese Funktion meldet der Trainer nicht als unterstützt"
        } catch FTMSControlError.rangeUnavailable {
            trainerControlStatus = "Der Trainer hat seinen zulässigen Wertebereich noch nicht geliefert"
        } catch FTMSControlError.outOfRange {
            trainerControlStatus = "Der Zielwert liegt außerhalb des sicheren Trainerbereichs"
        } catch {
            trainerControlStatus = "Trainerbefehl konnte nicht vorbereitet werden"
        }
    }

    private func handleTrainerResponse(_ response: FTMSControlResponse, deviceID: UUID) {
        guard trainerDeviceID == deviceID, let command = trainerPendingCommand else { return }
        guard response.requestOpcode == command.opcode else {
            trainerControlStatus = "Unerwartete FTMS-Antwort – warte auf den laufenden Befehl"
            return
        }
        trainerCommandTimeout?.cancel()
        trainerCommandTimeout = nil
        trainerPendingCommand = nil
        trainerCommandInFlight = false
        guard response.result == .success else {
            if response.result == .controlNotPermitted { trainerHasControl = false }
            trainerControlStatus = response.result.message
            return
        }
        switch command {
        case .requestControl:
            trainerHasControl = true
            trainerControlStatus = "Trainersteuerung übernommen"
        case .startOrResume:
            trainerIsRunning = true
            trainerControlStatus = "Trainer läuft"
        case .stop:
            trainerIsRunning = false
            trainerControlStatus = "Trainer gestoppt"
        case .pause:
            trainerIsRunning = false
            trainerControlStatus = "Trainer pausiert"
        case let .setResistance(value):
            trainerTargetResistance = value
            trainerControlStatus = String(format: "Widerstand %.1f bestätigt", value)
        case let .setPower(watts):
            trainerTargetPower = watts
            trainerControlStatus = "ERG \(watts) W bestätigt"
        case let .setInclination(percent), let .setSimulationGrade(percent):
            trainerTargetGrade = percent
            trainerControlStatus = String(format: "Steigung %.1f %% bestätigt", percent)
        }
    }

    private func handleTrainerStatus(_ trainerStatus: FTMSMachineStatus, deviceID: UUID) {
        guard trainerDeviceID == deviceID else { return }
        switch trainerStatus {
        case .reset:
            trainerIsRunning = false
            trainerControlStatus = "Trainer wurde zurückgesetzt"
        case .stopped:
            trainerIsRunning = false
            trainerControlStatus = "Trainer wurde am Gerät gestoppt"
        case .paused:
            trainerIsRunning = false
            trainerControlStatus = "Trainer wurde am Gerät pausiert"
        case .safetyStop:
            trainerIsRunning = false
            trainerControlStatus = "Sicherheitsstopp am Trainer"
        case .started:
            trainerIsRunning = true
            trainerControlStatus = "Trainer wurde am Gerät gestartet"
        case .controlPermissionLost:
            loseTrainerControl("Trainersteuerung wurde von einem anderen Gerät übernommen")
        case .other:
            break
        }
    }

    private func publishTrainerMetadata(for id: UUID) {
        trainerCapabilities = ftmsCapabilities[id] ?? FTMSTargetCapabilities()
        trainerResistanceRange = ftmsResistanceRanges[id]
        trainerInclinationRange = ftmsInclinationRanges[id]
        trainerPowerRange = ftmsPowerRanges[id]
    }

    private func failTrainerCommand(_ message: String) {
        trainerCommandTimeout?.cancel()
        trainerCommandTimeout = nil
        trainerPendingCommand = nil
        trainerCommandInFlight = false
        trainerControlStatus = message
    }

    private func loseTrainerControl(_ message: String) {
        failTrainerCommand(message)
        trainerHasControl = false
        trainerIsRunning = false
    }

    private func clearTrainerSelection(deviceID: UUID) {
        guard trainerDeviceID == deviceID else { return }
        loseTrainerControl("Trainer getrennt – Steuerung und Ziele wurden verworfen")
        trainerDeviceID = nil
        trainerName = nil
        trainerCapabilities = FTMSTargetCapabilities()
        trainerResistanceRange = nil
        trainerInclinationRange = nil
        trainerPowerRange = nil
        trainerTargetResistance = nil
        trainerTargetPower = nil
        trainerTargetGrade = nil
    }

    private func updateRevolutions(_ measurement: RevolutionMeasurement, deviceID: UUID) {
        var state = revolutionStates[deviceID] ?? RevolutionState()
        if let revolutions = measurement.wheelRevolutions,
           let eventTime = measurement.wheelEventTime,
           let previousRevolutions = state.wheelRevolutions,
           let previousEventTime = state.wheelEventTime,
           revolutions >= previousRevolutions {
            let revolutionDelta = revolutions - previousRevolutions
            let tickDelta = eventTime &- previousEventTime
            if tickDelta > 0 {
                let seconds = Double(tickDelta) / 1_024
                let value = Double(revolutionDelta) * wheelCircumferenceMeters / seconds * 3.6
                if value.isFinite, value >= 0, value <= 126 {
                    records[deviceID]?.speedKmh = value
                    speedKmh = value
                    speedSource = deviceID
                }
            }
        }
        if let revolutions = measurement.crankRevolutions,
           let eventTime = measurement.crankEventTime,
           let previousRevolutions = state.crankRevolutions,
           let previousEventTime = state.crankEventTime {
            let revolutionDelta = revolutions &- previousRevolutions
            let tickDelta = eventTime &- previousEventTime
            if tickDelta > 0 {
                let value = Double(revolutionDelta) * 60 * 1_024 / Double(tickDelta)
                if value.isFinite, value >= 0, value <= 300 {
                    records[deviceID]?.cadenceRpm = value
                    cadenceRpm = value
                    cadenceSource = deviceID
                }
            }
        }
        state.wheelRevolutions = measurement.wheelRevolutions ?? state.wheelRevolutions
        state.wheelEventTime = measurement.wheelEventTime ?? state.wheelEventTime
        state.crankRevolutions = measurement.crankRevolutions ?? state.crankRevolutions
        state.crankEventTime = measurement.crankEventTime ?? state.crankEventTime
        revolutionStates[deviceID] = state
    }

    private func ensureRecord(for peripheral: CBPeripheral, name: String?, rssi: Int) {
        let id = peripheral.identifier
        if records[id] == nil {
            records[id] = SensorDeviceSnapshot(
                id: id,
                name: name ?? "Unbekanntes Gerät",
                rssi: rssi,
                connectionState: connectionName(peripheral.state),
                services: [],
                heartRateBpm: nil,
                cadenceRpm: nil,
                powerWatts: nil,
                pedalBalancePercent: nil,
                speedKmh: nil,
                temperatureCelsius: nil,
                batteryPercent: nil,
                manufacturer: nil,
                model: nil,
                canControlFTMS: false
            )
        } else {
            if let name, !name.isEmpty { records[id]?.name = name }
            records[id]?.rssi = rssi
        }
    }

    private func updateConnectionState(for peripheral: CBPeripheral) {
        ensureRecord(for: peripheral, name: peripheral.name, rssi: records[peripheral.identifier]?.rssi ?? 0)
        records[peripheral.identifier]?.connectionState = connectionName(peripheral.state)
        publishDevices()
    }

    private func addServiceNames(_ uuids: [CBUUID], to id: UUID) {
        var names = Set(records[id]?.services ?? [])
        for uuid in uuids {
            if let name = serviceName(uuid) { names.insert(name) }
        }
        records[id]?.services = names.sorted()
    }

    private func publishDevices() {
        devices = records.values.sorted {
            if $0.isConnected != $1.isConnected { return $0.isConnected }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func clearLiveValues(from id: UUID) {
        if heartRateSource == id { heartRateBpm = nil; heartRateSource = nil }
        if cadenceSource == id { cadenceRpm = nil; cadenceSource = nil }
        if powerSource == id {
            powerWatts = nil
            powerSource = nil
        }
        if balanceSource == id { pedalBalancePercent = nil; balanceSource = nil }
        if resistanceSource == id { resistanceLevel = nil; resistanceSource = nil }
        if speedSource == id { speedKmh = nil; speedSource = nil }
        if temperatureSource == id { temperatureCelsius = nil; temperatureSource = nil }
        if batterySource == id { batteryPercent = nil; batterySource = nil }
    }

    private func displayName(for peripheral: CBPeripheral) -> String {
        records[peripheral.identifier]?.name ?? peripheral.name ?? "Sensor"
    }

    private func decodedString(_ data: Data) -> String? {
        String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func connectionName(_ state: CBPeripheralState) -> String {
        switch state {
        case .connected: return "Verbunden"
        case .connecting: return "Verbindet"
        case .disconnecting: return "Trennt"
        case .disconnected: return "Getrennt"
        @unknown default: return "Unbekannt"
        }
    }

    private func serviceName(_ uuid: CBUUID) -> String? {
        switch uuid.uuidString.uppercased() {
        case "180D": return "Puls"
        case "1816": return "Tempo/Kadenz"
        case "1818": return "Leistung"
        case "1826": return "FTMS"
        case "180F": return "Batterie"
        case "180A": return "Geräteinfo"
        case "181A": return "Umgebung"
        case "1819": return "Navigation"
        default: return nil
        }
    }
}

private struct RevolutionState {
    var wheelRevolutions: UInt32?
    var wheelEventTime: UInt16?
    var crankRevolutions: UInt16?
    var crankEventTime: UInt16?
}
