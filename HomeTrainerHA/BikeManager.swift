import CoreBluetooth
import SwiftUI

final class BikeManager: NSObject, ObservableObject {
    enum State: Equatable { case idle, scanning, connecting, connected, unavailable(String) }

    @Published var state: State = .idle
    @Published var metrics = BikeMetrics()
    @Published var discovered: [CBPeripheral] = []
    @Published var connectedName: String?

    /// Appelé à chaque nouvelle mesure (sur le main thread).
    var onMetrics: ((BikeMetrics) -> Void)?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var crank: (revs: UInt16, time: UInt16)?
    private let lastKey = "lastPeripheralID"
    private let wanted: [CBUUID] = [BLE.ftms, BLE.cyclingPower].map(CBUUID.init(string:))

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        guard central.state == .poweredOn else { return }
        discovered = []
        state = .scanning
        central.scanForPeripherals(withServices: wanted, options: nil)
    }

    func connect(_ p: CBPeripheral) {
        central.stopScan()
        peripheral = p
        p.delegate = self
        state = .connecting
        central.connect(p)
    }

    func disconnect() {
        UserDefaults.standard.removeObject(forKey: lastKey)
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil; connectedName = nil; state = .idle
        metrics = BikeMetrics(); crank = nil
    }

    private func reconnectLast() {
        guard let s = UserDefaults.standard.string(forKey: lastKey), let id = UUID(uuidString: s),
              let p = central.retrievePeripherals(withIdentifiers: [id]).first else { startScan(); return }
        connect(p)
    }
}

extension BikeManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn: reconnectLast()
        case .unauthorized: state = .unavailable("Autorisation Bluetooth refusée (Réglages iOS)")
        case .poweredOff: state = .unavailable("Bluetooth désactivé")
        default: state = .unavailable("Bluetooth indisponible")
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        if !discovered.contains(where: { $0.identifier == p.identifier }) { discovered.append(p) }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        UserDefaults.standard.set(p.identifier.uuidString, forKey: lastKey)
        connectedName = p.name
        state = .connected
        p.discoverServices(wanted + [CBUUID(string: BLE.heartRate)])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        state = .idle
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        // Reconnexion automatique si la coupure n'est pas volontaire.
        if peripheral != nil { state = .connecting; c.connect(p) }
    }
}

extension BikeManager: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        p.services?.forEach { p.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        let notify = [BLE.indoorBikeData, BLE.powerMeasurement, BLE.heartRateMeasurement].map(CBUUID.init(string:))
        for c in s.characteristics ?? [] where notify.contains(c.uuid) { p.setNotifyValue(true, for: c) }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard let data = c.value else { return }
        var m = metrics
        switch c.uuid.uuidString {
        case BLE.indoorBikeData: Parser.indoorBikeData(data, into: &m)
        case BLE.powerMeasurement: Parser.powerMeasurement(data, into: &m, crank: &crank)
        case BLE.heartRateMeasurement: m.heartRate = Parser.heartRate(data)
        default: return
        }
        metrics = m
        onMetrics?(m)
    }
}
