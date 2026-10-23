#if canImport(CoreBluetooth)
import Foundation
import Combine
@preconcurrency import CoreBluetooth
import ClickBridgeCore

public struct ControllerSnapshot: Identifiable {
    public let id: UUID
    public var name: String
    public var suggestedSide: ControllerSide?
    public var assignedSide: ControllerSide?
    public var phase: SessionPhase = .discovered
    public var battery: Int?
    public var firmware: String?
    public var hardware: String?
    public var rssi: Int?
    public var issue: String?
    public var lastInput: Date?
    public var lastButton: String?
    public var gatt: [String] = []
    public var shortID: String { String(id.uuidString.suffix(8)) }
}

@MainActor private final class PeripheralSession {
    let peripheral: CBPeripheral
    var snapshot: ControllerSnapshot
    var machine = SessionMachine()
    var tracker = ButtonTracker()
    var reconnect = ReconnectPolicy()
    var service: CBService?
    var write: CBCharacteristic?
    var subscriptions: Set<CBUUID> = []
    var writes: [Data] = []
    var deadline: DispatchWorkItem?
    var retry: DispatchWorkItem?
    var handshakeStarted = false
    var connectedAt: Date?
    var lastKeepAlive: Date?

    init(_ peripheral: CBPeripheral, name: String) {
        self.peripheral = peripheral
        snapshot = ControllerSnapshot(id: peripheral.identifier, name: name)
    }
    func resetTransport() {
        deadline?.cancel(); retry?.cancel()
        service = nil; write = nil; subscriptions.removeAll(); writes.removeAll()
        handshakeStarted = false; connectedAt = nil; lastKeepAlive = nil
        tracker.reset(); snapshot.lastInput = nil; snapshot.lastButton = nil
    }
}

/// One central, independent per-peripheral sessions. Never connects to trainers.
@MainActor public final class ControllerHub: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published public private(set) var devices: [ControllerSnapshot] = []
    @Published public private(set) var bluetoothStatus = "Bluetooth wird initialisiert"
    @Published public private(set) var scanning = false
    @Published public private(set) var registry: ControllerRegistry
    public let log: DiagnosticLog
    public var onButton: ((UUID, ControllerSide, ButtonEvent) -> Void)?
    public var debounce: TimeInterval = 0.08
    public var longPress: TimeInterval = 0.6
    private var central: CBCentralManager!
    private var sessions: [UUID: PeripheralSession] = [:]
    private var wanted: Set<UUID>
    private let defaults: UserDefaults
    private let namespace: String
    private var scanWanted = false
    private static let notifyID = CBUUID(string: ClickGATT.notify)
    private static let indicateID = CBUUID(string: ClickGATT.indicate)
    private static let services = [CBUUID(string: ClickGATT.service), CBUUID(string: ClickGATT.legacyService)]

    public init(namespace: String = "ClickBridge") {
        self.namespace = namespace
        defaults = .standard
        if let data = defaults.data(forKey: namespace + ".registry"),
           let stored = try? JSONDecoder().decode(ControllerRegistry.self, from: data),
           stored.left == nil || stored.left != stored.right {
            registry = stored
        } else { registry = ControllerRegistry() }
        wanted = Set((defaults.stringArray(forKey: namespace + ".wanted") ?? []).compactMap(UUID.init(uuidString:)))
        log = DiagnosticLog(namespace: namespace)
        super.init()
        central = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionRestoreIdentifierKey: namespace + ".central.v1",
            CBCentralManagerOptionShowPowerAlertKey: true
        ])
    }

    public func scan() {
        scanWanted = true
        guard central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: Self.services, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanning = true; log.record("BLE", "Suche nach FC82 / Legacy-Service")
    }
    public func stopScan() { scanWanted = false; central.stopScan(); scanning = false }

    public func assign(_ id: UUID, to side: ControllerSide) throws {
        try registry.assign(id, to: side)
        persist(); publish(); log.record("Zuordnung", "\(side.rawValue) = \(short(id))")
        connect(id)
    }
    public func forget(_ side: ControllerSide) {
        if let id = registry.id(for: side) { disconnect(id) }
        registry.remove(side); persist(); publish()
    }
    public func connect(_ id: UUID) {
        guard let session = sessions[id], registry.side(for: id) != nil else { return }
        wanted.insert(id); persist(); session.reconnect.succeeded(); session.retry?.cancel()
        connectSession(session)
    }
    private func connectSession(_ session: PeripheralSession) {
        guard central.state == .poweredOn, wanted.contains(session.peripheral.identifier) else { return }
        if session.peripheral.state == .connecting { return }
        if session.peripheral.state == .connected {
            if session.machine.phase == .attention { configure(session) }
            return
        }
        session.resetTransport()
        _ = session.machine.advance(to: .connecting)
        session.snapshot.issue = nil
        central.connect(session.peripheral, options: nil)
        log.record("BLE", "Verbinden \(short(session.peripheral.identifier))")
        deadline(session, after: 25, message: "Verbindungsaufbau ohne Antwort")
        publish()
    }
    public func disconnect(_ id: UUID) {
        wanted.remove(id); persist()
        guard let session = sessions[id] else { return }
        session.resetTransport(); _ = session.machine.advance(to: .disconnected)
        central.cancelPeripheralConnection(session.peripheral); publish()
    }

    /// Call when foreground resumes. This performs no continuous background scheduling.
    public func checkHealth() {
        for session in sessions.values where session.peripheral.state == .connected {
            if session.machine.phase == .receiving || session.machine.phase == .awaitingInput {
                if let connected = session.connectedAt, Date().timeIntervalSince(connected) > 60,
                   registry.side(for: session.peripheral.identifier) == .left {
                    session.snapshot.issue = "Linken Controller jetzt testen: zeitabhängige Sperre ist möglich."
                }
                if Date().timeIntervalSince(session.lastKeepAlive ?? .distantPast) > 20 {
                    enqueue(ClickGATT.readDeviceInfo, session)
                    session.lastKeepAlive = Date()
                }
            }
        }
        publish()
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(registry) { defaults.set(data, forKey: namespace + ".registry") }
        defaults.set(wanted.map(\.uuidString), forKey: namespace + ".wanted")
    }
    private func short(_ id: UUID) -> String { String(id.uuidString.suffix(8)) }
    private func publish() {
        devices = sessions.values.map {
            $0.snapshot.phase = $0.machine.phase
            $0.snapshot.assignedSide = registry.side(for: $0.peripheral.identifier)
            return $0.snapshot
        }.sorted { $0.id.uuidString < $1.id.uuidString }
    }
    private func fail(_ session: PeripheralSession, _ message: String) {
        session.deadline?.cancel(); session.machine.fail(message); session.snapshot.issue = message
        session.tracker.reset(); session.writes.removeAll()
        log.record("Fehler", "\(short(session.peripheral.identifier)): \(message)"); publish()
    }
    private func deadline(_ session: PeripheralSession, after seconds: TimeInterval, message: String) {
        session.deadline?.cancel()
        let task = DispatchWorkItem { [weak self, weak session] in
            guard let self, let session else { return }
            self.fail(session, message)
            if session.peripheral.state == .connecting { self.central.cancelPeripheralConnection(session.peripheral) }
        }
        session.deadline = task
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: task)
    }
    private func configure(_ session: PeripheralSession) {
        session.resetTransport()
        session.machine = SessionMachine()
        _ = session.machine.advance(to: .connecting)
        _ = session.machine.advance(to: .discovering)
        session.connectedAt = Date(); session.snapshot.issue = nil; session.snapshot.gatt = []
        session.peripheral.delegate = self
        session.peripheral.discoverServices(nil)
        deadline(session, after: 20, message: "GATT-Discovery unvollständig")
        publish()
    }
    private func scheduleReconnect(_ session: PeripheralSession) {
        guard wanted.contains(session.peripheral.identifier), central.state == .poweredOn else { return }
        guard let delay = session.reconnect.nextDelay() else {
            fail(session, "Wiederverbindung nach 8 Versuchen gestoppt. Erneut verbinden."); return
        }
        log.record("Reconnect", "\(short(session.peripheral.identifier)) in \(Int(delay)) s; Ausführung im Hintergrund nicht garantiert")
        let task = DispatchWorkItem { [weak self, weak session] in
            guard let self, let session else { return }
            self.connectSession(session)
        }
        session.retry = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            bluetoothStatus = "Bluetooth bereit"
            let identifiers = wanted.filter { registry.side(for: $0) != nil }
            for peripheral in central.retrievePeripherals(withIdentifiers: Array(identifiers)) {
                if sessions[peripheral.identifier] == nil {
                    sessions[peripheral.identifier] = PeripheralSession(peripheral, name: peripheral.name ?? "Zwift Click")
                }
                if let session = sessions[peripheral.identifier] {
                    if peripheral.state == .connected { configure(session) } else { connectSession(session) }
                }
            }
            if scanWanted { scan() }
        case .poweredOff: bluetoothStatus = "Bluetooth ausgeschaltet"
        case .unauthorized: bluetoothStatus = "Bluetooth-Zugriff verweigert · iOS-Einstellungen prüfen"
        case .unsupported: bluetoothStatus = "Bluetooth nicht unterstützt"
        case .resetting: bluetoothStatus = "Bluetooth wird zurückgesetzt"
        default: bluetoothStatus = "Bluetooth-Status unbekannt"
        }
        if central.state != .poweredOn {
            scanning = false
            for session in sessions.values {
                session.resetTransport(); _ = session.machine.advance(to: .disconnected)
            }
        }
        log.record("BLE", bluetoothStatus); publish()
    }
    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        for peripheral in restored {
            let session = PeripheralSession(peripheral, name: peripheral.name ?? "Zwift Click")
            sessions[peripheral.identifier] = session; peripheral.delegate = self
            guard wanted.contains(peripheral.identifier), registry.side(for: peripheral.identifier) != nil else {
                central.cancelPeripheralConnection(peripheral); continue
            }
            if peripheral.state == .connected { configure(session) }
            else { _ = session.machine.advance(to: .connecting) }
        }
        log.record("Restoration", "\(restored.count) Peripherals wiederhergestellt; GATT wird neu geprüft")
        publish()
    }
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let manufacturer = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let identity = manufacturer.flatMap { ManufacturerIdentity(data: $0) }
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Unbekannt"
        guard identity != nil || name.lowercased().contains("zwift click") else { return }
        let session = sessions[peripheral.identifier] ?? PeripheralSession(peripheral, name: name)
        session.snapshot.suggestedSide = identity?.side
        session.snapshot.rssi = RSSI.intValue
        sessions[peripheral.identifier] = session
        log.record("Gefunden", "\(name) \(short(peripheral.identifier)) Typ=\(identity?.side.rawValue ?? "unbekannt")")
        if wanted.contains(peripheral.identifier) { connectSession(session) }
        publish()
    }
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let session = sessions[peripheral.identifier] else { return }
        guard wanted.contains(peripheral.identifier) else { central.cancelPeripheralConnection(peripheral); return }
        log.record("BLE", "Verbunden \(short(peripheral.identifier))")
        configure(session)
    }
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard let session = sessions[peripheral.identifier] else { return }
        session.resetTransport(); _ = session.machine.advance(to: .disconnected)
        session.snapshot.issue = error?.localizedDescription ?? "Verbindung fehlgeschlagen"
        log.record("Fehler", session.snapshot.issue!); scheduleReconnect(session); publish()
    }
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard let session = sessions[peripheral.identifier] else { return }
        session.resetTransport(); _ = session.machine.advance(to: .disconnected)
        session.snapshot.issue = error?.localizedDescription
        log.record("BLE", "Getrennt \(short(peripheral.identifier)): \(error?.localizedDescription ?? "ohne Systemfehler")")
        scheduleReconnect(session); publish()
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let session = sessions[peripheral.identifier], session.machine.phase == .discovering else { return }
        if let error { fail(session, error.localizedDescription); return }
        let services = peripheral.services ?? []
        session.service = services.first { $0.uuid == Self.services[0] } ?? services.first { $0.uuid == Self.services[1] }
        guard session.service != nil else { fail(session, "FC82 / proprietärer Service fehlt. Firmware oder Sperre prüfen."); return }
        for service in services {
            session.snapshot.gatt.append("Service \(service.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
        _ = session.machine.advance(to: .subscribing); publish()
    }
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let session = sessions[peripheral.identifier] else { return }
        guard session.machine.phase != .disconnected, session.machine.phase != .attention else { return }
        if let error { fail(session, error.localizedDescription); return }
        for characteristic in service.characteristics ?? [] {
            let uuid = characteristic.uuid
            let description = "\(uuid.uuidString) properties=0x\(String(characteristic.properties.rawValue, radix: 16))"
            session.snapshot.gatt.append(description); log.record("GATT", "\(short(peripheral.identifier)) \(description)")
            if service === session.service {
                if uuid == CBUUID(string: ClickGATT.write) { session.write = characteristic }
                if uuid == Self.notifyID || uuid == Self.indicateID {
                    guard characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) else {
                        fail(session, "Notify/Indicate-Eigenschaft fehlt: \(uuid)"); return
                    }
                    if characteristic.isNotifying { session.subscriptions.insert(uuid) }
                    else { peripheral.setNotifyValue(true, for: characteristic) }
                }
            }
            if [ClickGATT.battery, ClickGATT.firmware, ClickGATT.hardware].contains(uuid.uuidString) {
                if characteristic.properties.contains(.read) { peripheral.readValue(for: characteristic) }
                if uuid == CBUUID(string: ClickGATT.battery), characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        }
        tryInitialize(session); publish()
    }
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard let session = sessions[peripheral.identifier] else { return }
        if let error { fail(session, error.localizedDescription); return }
        if characteristic.uuid == Self.notifyID || characteristic.uuid == Self.indicateID {
            guard characteristic.service === session.service else { return }
            guard characteristic.isNotifying else { fail(session, "Protokoll-Subscription beendet"); return }
            session.subscriptions.insert(characteristic.uuid); tryInitialize(session)
        }
        publish()
    }
    private func tryInitialize(_ session: PeripheralSession) {
        guard !session.handshakeStarted, session.machine.phase == .subscribing, session.write != nil,
              session.subscriptions.contains(Self.notifyID), session.subscriptions.contains(Self.indicateID) else { return }
        session.handshakeStarted = true
        _ = session.machine.advance(to: .initializing)
        enqueue(ClickGATT.initialize, session)
        deadline(session, after: 10, message: "Kein RideOn-Handshake. Firmware/Sperre prüfen; keine Tastenausgabe freigegeben.")
    }
    private func enqueue(_ data: Data, _ session: PeripheralSession) {
        guard data == ClickGATT.initialize || data == ClickGATT.readDeviceInfo else {
            fail(session, "Nicht freigegebenes Kommando blockiert"); return
        }
        guard session.writes.count < 4 else { fail(session, "BLE-Schreibwarteschlange voll"); return }
        session.writes.append(data); flush(session)
    }
    private func flush(_ session: PeripheralSession) {
        guard let characteristic = session.write, session.peripheral.state == .connected else { return }
        let noResponse = characteristic.properties.contains(.writeWithoutResponse)
        guard noResponse || characteristic.properties.contains(.write) else { fail(session, "Schreib-Characteristic nicht beschreibbar"); return }
        while let data = session.writes.first {
            if noResponse && !session.peripheral.canSendWriteWithoutResponse { return }
            let type: CBCharacteristicWriteType = noResponse ? .withoutResponse : .withResponse
            guard data.count <= session.peripheral.maximumWriteValueLength(for: type) else { fail(session, "Kommando größer als ATT-Schreibgrenze"); return }
            session.writes.removeFirst()
            session.peripheral.writeValue(data, for: characteristic, type: type)
            log.record("TX", "\(short(session.peripheral.identifier)) \(data.hex) (Transportauftrag, keine Ausführungsbestätigung)")
            if !noResponse { return }
        }
    }
    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        if let session = sessions[peripheral.identifier] { flush(session) }
    }
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let session = sessions[peripheral.identifier] else { return }
        if let error { fail(session, error.localizedDescription) } else { flush(session) }
    }
    public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard let session = sessions[peripheral.identifier] else { return }
        log.record("GATT", "Services invalidiert \(short(peripheral.identifier)); erneute Discovery")
        configure(session)
    }
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let session = sessions[peripheral.identifier] else { return }
        if let error { log.record("GATT-Fehler", error.localizedDescription); return }
        guard let data = characteristic.value else { return }
        let uuid = characteristic.uuid
        if uuid == CBUUID(string: ClickGATT.battery) {
            if data.count == 1, let value = data.first, value <= 100 { session.snapshot.battery = Int(value) }
            else { log.record("Paketfehler", "Ungültiger Standard-Batteriestatus") }
        } else if uuid == CBUUID(string: ClickGATT.firmware) {
            session.snapshot.firmware = String(data: data, encoding: .utf8)
        } else if uuid == CBUUID(string: ClickGATT.hardware) {
            session.snapshot.hardware = String(data: data, encoding: .utf8)
        } else if (uuid == Self.notifyID || uuid == Self.indicateID), characteristic.service === session.service {
            log.record("RX", "\(short(peripheral.identifier)) \(uuid.uuidString) \(data.prefix(512).hex)")
            do { process(try ClickPacketDecoder.decode(data), session) }
            catch { log.record("Paketfehler", "\(short(peripheral.identifier)) \(error)") }
        }
        publish()
    }
    private func process(_ packet: ClickPacket, _ session: PeripheralSession) {
        switch packet {
        case .handshake:
            guard session.machine.phase == .initializing else { return }
            session.deadline?.cancel(); session.reconnect.succeeded()
            _ = session.machine.advance(to: .awaitingInput)
            log.record("Protokoll", "Handshake erhalten \(short(session.peripheral.identifier)); Tasten und Langzeitbetrieb noch zu prüfen")
        case .encryptionRequired: fail(session, "Verschlüsselter Handshake erforderlich; Firmware hier nicht unterstützt.")
        case .buttons(let all, let bitmap):
            guard session.machine.phase == .awaitingInput || session.machine.phase == .receiving,
                  let side = registry.side(for: session.peripheral.identifier) else { return }
            let pressed = Set(all.filter { $0.side == side })
            session.tracker.debounce = debounce; session.tracker.longPress = longPress
            let events = session.tracker.update(pressed, at: ProcessInfo.processInfo.systemUptime)
            for event in events {
                if event.phase == .down {
                    session.snapshot.lastInput = Date(); session.snapshot.lastButton = event.button.label
                    session.snapshot.issue = nil; _ = session.machine.advance(to: .receiving)
                }
                log.record("Taste", "\(side.rawValue) \(event.button.label) \(event.phase.rawValue) Dauer=\(event.duration) bitmap=\(String(bitmap, radix: 16))")
                onButton?(session.peripheral.identifier, side, event)
            }
        case .battery(let level): session.snapshot.battery = level
        case .stopped: fail(session, "Controller meldet Protokoll-Stop. Zeitabhängige Click-V2-Sperre möglich.")
        case .lostControl: fail(session, "Controller meldet Kontrollverlust.")
        case .idle: break
        case .unknown(let opcode, _): log.record("Unbekannt", "Opcode 0x\(String(opcode, radix: 16)); keine Aktion")
        }
    }
}
#endif
