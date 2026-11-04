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
    var speedKmh: Double?
    var batteryPercent: Int?
    var manufacturer: String?
    var model: String?

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
    @Published private(set) var batteryPercent: Int?

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
            desiredConnections.remove(id)
            manager.cancelPeripheralConnection(peripheral)
        } else {
            desiredConnections.insert(id)
            records[id]?.connectionState = "Verbindet"
            publishDevices()
            manager.connect(peripheral)
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
                if measurement.pedalPowerBalancePercent != nil { balanceSource = id }
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
            case "2A29": records[id]?.manufacturer = decodedString(data)
            case "2A24": records[id]?.model = decodedString(data)
            default: break
            }
            publishDevices()
        } catch SensorParseError.truncated {
            status = "Unvollständiges Sensorpaket von \(displayName(for: peripheral))"
        } catch {
            status = "Sensordaten konnten nicht gelesen werden"
        }
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
                speedKmh: nil,
                batteryPercent: nil,
                manufacturer: nil,
                model: nil
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
