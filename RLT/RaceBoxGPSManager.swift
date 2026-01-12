//
//  RaceBoxGPSManager.swift
//  RaceLiveTelemetry
//
//  BLE NUS + RaceBox binary protocol (0xB5 0x62 / class 0xFF id 0x01)
//

import Foundation
import CoreBluetooth
import Combine

final class RaceBoxGPSManager: NSObject, ObservableObject {

    // MARK: - Public state (UI/Session)
    enum ConnectionState: Equatable {
        case idle
        case scanning
        case connecting
        case connected(name: String)
        case failed(String)
        case bluetoothOff
    }

    @Published private(set) var state: ConnectionState = .idle

    @Published private(set) var speedKmh: Double? = nil
    @Published private(set) var satellites: Int? = nil
    @Published private(set) var hdop: Double? = nil          // On y met PDOP/100 (proxy) pour compat UI
    @Published private(set) var fixQuality: Int? = nil       // Fix status RaceBox
    @Published private(set) var lastUpdate: Date? = nil

    // NEW: GPS position
    @Published private(set) var latitude: Double? = nil
    @Published private(set) var longitude: Double? = nil
    
    // NEW: Altitude + position
    @Published private(set) var headingDeg: Double? = nil
    @Published private(set) var altitudeM: Double? = nil
    
    // NEW: Battery (0..100)
    @Published private(set) var batteryPercent: Int? = nil
    
    // NEW: Battery (RaceBox Data Message)
    @Published private(set) var isCharging: Bool? = nil



    // MARK: - BLE identifiers (NUS)
    private let nusServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let nusRxUUID      = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    private let nusTxUUID      = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    
    // MARK: - BLE identifiers (Battery Service)
    private let batteryServiceUUID = CBUUID(string: "180F")
    private let batteryLevelUUID   = CBUUID(string: "2A19")

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?

    private var nusTx: CBCharacteristic?
    private var nusRx: CBCharacteristic?
    private var batteryLevelChar: CBCharacteristic?


    // MARK: - Packet FIFO
    private var rxBuffer = Data()
    private var bytesRxTotal: Int = 0

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }
    
    // MARK: - Auto-reconnect
    @Published var autoReconnectEnabled: Bool = true

    private var manuallyStopped: Bool = false
    private var reconnectAttempt: Int = 0
    private var reconnectWorkItem: DispatchWorkItem? = nil
    private var connectedName: String? = nil

    // MARK: - Public API

    func start() {
        guard central.state == .poweredOn else {
            state = (central.state == .poweredOff) ? .bluetoothOff : .failed("Bluetooth indisponible")
            return
        }
        manuallyStopped = false
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        reconnectAttempt = 0

        resetTelemetry()
        bytesRxTotal = 0
        rxBuffer.removeAll(keepingCapacity: true)

        state = .scanning
        debugPrint("🔎 RaceBox scan started...")

        // Scan non filtré (robuste)
        central.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])

        // Timeout scan
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self else { return }
            if case .scanning = self.state {
                self.central.stopScan()
                self.state = .failed("RaceBox introuvable (scan timeout)")
                debugPrint("⏱️ RaceBox scan timeout")

                if !self.manuallyStopped {
                    self.scheduleReconnect(reason: "scan timeout")
                }
            }
        }
    }

    func stop() {
        // Empêche toute reconnexion automatique
        manuallyStopped = true
        reconnectAttempt = 0
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        connectedName = nil

        central.stopScan()

        if let p = peripheral {
            central.cancelPeripheralConnection(p)
        }

        peripheral = nil
        nusTx = nil
        nusRx = nil
        batteryLevelChar = nil
        rxBuffer.removeAll(keepingCapacity: false)

        resetTelemetry()
        state = .idle
        debugPrint("🛑 RaceBox stop (manual)")
    }




    // MARK: - Helpers

    private func resetTelemetry() {
        speedKmh = nil
        satellites = nil
        hdop = nil
        fixQuality = nil
        lastUpdate = nil

        latitude = nil
        longitude = nil

        headingDeg = nil
        altitudeM = nil

        batteryPercent = nil
        isCharging = nil
    }

    private func scheduleReconnect(reason: String) {
        guard autoReconnectEnabled, !manuallyStopped else { return }
        guard central.state == .poweredOn else { return }

        reconnectWorkItem?.cancel()

        // backoff: 2s, 4s, 6s, 8s, 10s, 12s (max)
        reconnectAttempt += 1
        let delay = min(2.0 * Double(reconnectAttempt), 12.0)

        debugPrint("🔁 Reconnect scheduled in \(delay)s — reason:", reason)

        let item = DispatchWorkItem { [weak self] in
            self?.start()
        }
        reconnectWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: - Incoming bytes -> packets -> decode

    private func handleIncoming(bytes: Data) {
        bytesRxTotal += bytes.count
        rxBuffer.append(bytes)

        // Parse FIFO for complete packets
        parsePacketsFromBuffer()
    }

    private func parsePacketsFromBuffer() {
        // Packet format:
        // [0]=0xB5 [1]=0x62 [2]=class [3]=id [4..5]=lenLE [payload len] [CK_A][CK_B]
        while true {
            if rxBuffer.count < 8 { return }

            // Sync search
            if !(rxBuffer[0] == 0xB5 && rxBuffer[1] == 0x62) {
                if let idx = rxBuffer.firstIndex(of: 0xB5),
                   idx + 1 < rxBuffer.count,
                   rxBuffer[idx + 1] == 0x62 {
                    rxBuffer.removeSubrange(0..<idx)
                } else {
                    rxBuffer.removeAll(keepingCapacity: true)
                    return
                }
                continue
            }

            let msgClass = rxBuffer[2]
            let msgId    = rxBuffer[3]
            let len      = Int(UInt16(rxBuffer[4]) | (UInt16(rxBuffer[5]) << 8))

            let totalLen = 6 + len + 2
            if rxBuffer.count < totalLen { return }

            let packet = rxBuffer.prefix(totalLen)
            rxBuffer.removeSubrange(0..<totalLen)

            guard verifyChecksum(packet) else {
                debugPrint("⚠️ RaceBox checksum invalid (class=\(msgClass), id=\(msgId), len=\(len))")
                continue
            }

            // RaceBox Data Message: class 0xFF id 0x01 len 80
            if msgClass == 0xFF && msgId == 0x01 && len == 80 {
                decodeRaceBoxDataMessage(packet)
            } else {
                // Tu peux logger ici si tu veux voir d’autres messages
                // debugPrint("ℹ️ Packet class=\(String(format:"%02X", msgClass)) id=\(String(format:"%02X", msgId)) len=\(len)")
                continue
            }
        }
    }

    private func verifyChecksum(_ packet: Data) -> Bool {
        // UBX checksum over class..payload (index 2 to end-3)
        guard packet.count >= 8 else { return false }

        let ckRange = packet.index(packet.startIndex, offsetBy: 2)..<packet.index(packet.endIndex, offsetBy: -2)
        var ckA: UInt8 = 0
        var ckB: UInt8 = 0
        for b in packet[ckRange] {
            ckA &+= b
            ckB &+= ckA
        }

        return ckA == packet[packet.count - 2] && ckB == packet[packet.count - 1]
    }

    private func decodeRaceBoxDataMessage(_ packet: Data) {
        // Packet: [B5 62][class id][lenL lenH][payload][ckA ckB]
        // Offsets used below are PAYLOAD offsets (0..79) per RaceBox specification.
        let payloadStart = 6

        func u8p(_ off: Int) -> UInt8 {
            packet[payloadStart + off]
        }
        func u16lep(_ off: Int) -> UInt16 {
            let i = payloadStart + off
            return UInt16(packet[i]) | (UInt16(packet[i + 1]) << 8)
        }
        func u32lep(_ off: Int) -> UInt32 {
            let i = payloadStart + off
            return UInt32(packet[i]) |
                   (UInt32(packet[i + 1]) << 8) |
                   (UInt32(packet[i + 2]) << 16) |
                   (UInt32(packet[i + 3]) << 24)
        }
        func i32lep(_ off: Int) -> Int32 {
            Int32(bitPattern: u32lep(off))
        }

        // Time (UTC) in payload
        let year   = Int(u16lep(4))
        let month  = Int(u8p(6))
        let day    = Int(u8p(7))
        let hour   = Int(u8p(8))
        let minute = Int(u8p(9))
        let second = Int(u8p(10))

        // Fix & satellites
        let fixStatus = Int(u8p(20))
        let svs       = Int(u8p(23))

        // Position (deg * 1e7)
        let lonRaw = Double(i32lep(24))
        let latRaw = Double(i32lep(28))

        // Speed (mm/s)
        let speedMmPerSec = Double(i32lep(48))

        // PDOP factor 100
        let pdopRaw = Double(u16lep(64))
        
        // Battery status (payload offset 67)
        // Mini / Mini S: MSB=charging, lower 7 bits = battery %
        // Micro: field = input voltage * 10 (on ne gère pas ici)
        let batt = u8p(67)
        let charging = (batt & 0x80) != 0
        let percent = Int(batt & 0x7F)

        if (0...100).contains(percent) {
            batteryPercent = percent
            isCharging = charging
        } else {
            batteryPercent = nil
            isCharging = nil
        }
        
        // Heading (deg * 1e5) — offset payload 52 (souvent) : i32
        let headingRaw = Double(i32lep(52))
        let heading = headingRaw / 100_000.0

        // Altitude (mm) — offset payload 32 (souvent) : i32
        let altRawMm = Double(i32lep(32))
        let altitude = altRawMm / 1000.0

        // Publish (avec garde-fous)
        if heading.isFinite, heading >= -360, heading <= 720 {
            headingDeg = (heading.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        }

        if altitude.isFinite, altitude > -1000, altitude < 10000 {
            altitudeM = altitude
        }

        // Publish fields
        fixQuality = fixStatus
        satellites = svs

        longitude = lonRaw / 10_000_000.0
        latitude  = latRaw / 10_000_000.0

        speedKmh = max(0, speedMmPerSec) * 0.0036
        hdop = pdopRaw / 100.0

        // lastUpdate (best effort)
        if (2000...2100).contains(year),
           (1...12).contains(month),
           (1...31).contains(day),
           (0...23).contains(hour),
           (0...59).contains(minute),
           (0...60).contains(second) {
            var dc = DateComponents()
            dc.calendar = Calendar(identifier: .gregorian)
            dc.timeZone = TimeZone(secondsFromGMT: 0)
            dc.year = year
            dc.month = month
            dc.day = day
            dc.hour = hour
            dc.minute = minute
            dc.second = second
            lastUpdate = dc.date ?? Date()
        } else {
            lastUpdate = Date()
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension RaceBoxGPSManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            debugPrint("✅ Bluetooth poweredOn")
        case .poweredOff:
            state = .bluetoothOff
            debugPrint("⚠️ Bluetooth poweredOff")
        default:
            state = .failed("Bluetooth indisponible")
            debugPrint("⚠️ Bluetooth unavailable:", central.state.rawValue)
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        let name = (peripheral.name ?? "").lowercased()
        guard name.contains("racebox") else { return }

        debugPrint("🟢 RaceBox detected:", peripheral.name ?? "unknown", "RSSI:", RSSI)

        central.stopScan()
        resetTelemetry()
        bytesRxTotal = 0
        rxBuffer.removeAll(keepingCapacity: true)

        self.peripheral = peripheral
        peripheral.delegate = self

        state = .connecting
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let name = peripheral.name ?? "RaceBox"
        connectedName = name
        state = .connecting
        debugPrint("🔗 Connected to:", name)
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        state = .failed(error?.localizedDescription ?? "Connexion échouée")
        debugPrint("❌ Fail to connect:", error?.localizedDescription ?? "unknown")
        scheduleReconnect(reason: "fail to connect")
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        nusTx = nil
        nusRx = nil
        self.peripheral = nil
        batteryLevelChar = nil
        connectedName = nil

        if manuallyStopped {
            state = .idle
            debugPrint("🔌 Disconnected (manual stop)")
            return
        }

        state = .failed(error?.localizedDescription ?? "Déconnecté")
        debugPrint("🔌 Disconnected:", error?.localizedDescription ?? "no error")

        scheduleReconnect(reason: "didDisconnectPeripheral")
    }
}

// MARK: - CBPeripheralDelegate
extension RaceBoxGPSManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            state = .failed(error.localizedDescription)
            debugPrint("❌ didDiscoverServices error:", error.localizedDescription)
            return
        }

        guard let services = peripheral.services else { return }
        debugPrint("🔵 Services BLE découverts :")
        for s in services {
            debugPrint(" - \(s.uuid.uuidString)")
        }
        
        // NEW: Battery service (optionnel)
        if let batt = services.first(where: { $0.uuid == batteryServiceUUID }) {
            peripheral.discoverCharacteristics([batteryLevelUUID], for: batt)
        }

        guard let nus = services.first(where: { $0.uuid == nusServiceUUID }) else {
            state = .failed("Service NUS introuvable")
            debugPrint("❌ NUS service not found")
            return
        }

        peripheral.discoverCharacteristics([nusRxUUID, nusTxUUID], for: nus)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error {
            state = .failed(error.localizedDescription)
            debugPrint("❌ didDiscoverCharacteristics error:", error.localizedDescription)
            return
        }

        guard let chars = service.characteristics else { return }

        // NUS
        if service.uuid == nusServiceUUID {
            if let tx = chars.first(where: { $0.uuid == nusTxUUID }) {
                nusTx = tx
                peripheral.setNotifyValue(true, for: tx)
                debugPrint("✅ NUS TX notify demandé")
            }

            if let rx = chars.first(where: { $0.uuid == nusRxUUID }) {
                nusRx = rx
                debugPrint("✅ NUS RX disponible")
            }
            
            if nusTx != nil && nusRx != nil {
                state = .connected(name: connectedName ?? "RaceBox")
            }

            return
        }

        // Battery
        if service.uuid == batteryServiceUUID {
            if let level = chars.first(where: { $0.uuid == batteryLevelUUID }) {
                batteryLevelChar = level

                // Si notify dispo, on l'active; sinon on read une fois
                if level.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: level)
                }
                peripheral.readValue(for: level)
                debugPrint("🔋 Battery level char ready")
            }
            return
        }
    }


    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            debugPrint("❌ Notify state error:", error.localizedDescription)
            return
        }
        debugPrint("🔔 Notify state for \(characteristic.uuid.uuidString): \(characteristic.isNotifying)")
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            debugPrint("❌ didUpdateValueFor error:", error.localizedDescription)
            return
        }

        // NUS telemetry
        if characteristic.uuid == nusTxUUID, let data = characteristic.value {
            handleIncoming(bytes: data)
            return
        }

        // Battery level (0..100)
        if characteristic.uuid == batteryLevelUUID, let data = characteristic.value, let b = data.first {
            let v = Int(b)
            if (0...100).contains(v) {
                batteryPercent = v
            }
            return
        }
    }
}
