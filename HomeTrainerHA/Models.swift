import Foundation

/// Dernières mesures connues du home trainer.
struct BikeMetrics: Equatable {
    var power: Int?          // W
    var cadence: Int?        // rpm
    var speed: Double?       // km/h
    var heartRate: Int?      // bpm
    var distance: Int?       // m
    var energy: Int?         // kcal
}

enum BLE {
    static let ftms = "1826"
    static let cyclingPower = "1818"
    static let heartRate = "180D"
    static let indoorBikeData = "2AD2"
    static let powerMeasurement = "2A63"
    static let heartRateMeasurement = "2A37"
}

/// Décodage des caractéristiques GATT standard.
enum Parser {
    /// FTMS Indoor Bike Data (0x2AD2).
    static func indoorBikeData(_ d: Data, into m: inout BikeMetrics) {
        var r = Reader(d)
        guard let flags = r.u16() else { return }
        if flags & 0x0001 == 0, let v = r.u16() { m.speed = Double(v) / 100 }   // bit0 inversé
        if flags & 0x0002 != 0 { _ = r.u16() }                                  // vitesse moyenne
        if flags & 0x0004 != 0, let v = r.u16() { m.cadence = Int((Double(v) / 2).rounded()) }
        if flags & 0x0008 != 0 { _ = r.u16() }                                  // cadence moyenne
        if flags & 0x0010 != 0, let v = r.u24() { m.distance = v }
        if flags & 0x0020 != 0 { _ = r.u16() }                                  // résistance
        if flags & 0x0040 != 0, let v = r.i16() { m.power = Int(v) }
        if flags & 0x0080 != 0 { _ = r.i16() }                                  // puissance moyenne
        if flags & 0x0100 != 0 {                                                // énergie
            if let total = r.u16() { m.energy = Int(total) }
            _ = r.u16(); _ = r.u8()
        }
        if flags & 0x0200 != 0, let v = r.u8() { m.heartRate = Int(v) }
    }

    /// Cycling Power Measurement (0x2A63) — la cadence est dérivée des tours de manivelle.
    static func powerMeasurement(_ d: Data, into m: inout BikeMetrics, crank: inout (revs: UInt16, time: UInt16)?) {
        var r = Reader(d)
        guard let flags = r.u16(), let p = r.i16() else { return }
        m.power = Int(p)
        if flags & 0x0001 != 0 { _ = r.u8() }                 // équilibre pédalier
        if flags & 0x0004 != 0 { _ = r.u16() }                // couple cumulé
        if flags & 0x0010 != 0 { _ = r.u32(); _ = r.u16() }   // roue
        if flags & 0x0020 != 0, let revs = r.u16(), let time = r.u16() {
            if let prev = crank {
                let dRevs = Int(revs &- prev.revs)
                let dTime = Int(time &- prev.time)            // 1/1024 s
                if dTime > 0 { m.cadence = Int((Double(dRevs) * 1024 * 60 / Double(dTime)).rounded()) }
                else if dRevs == 0 { /* pas de nouvel évènement */ }
            }
            crank = (revs, time)
        }
    }

    /// Heart Rate Measurement (0x2A37).
    static func heartRate(_ d: Data) -> Int? {
        var r = Reader(d)
        guard let flags = r.u8() else { return nil }
        return flags & 1 == 0 ? r.u8().map(Int.init) : r.u16().map(Int.init)
    }
}

struct Reader {
    private let d: [UInt8]
    private var i = 0
    init(_ data: Data) { d = [UInt8](data) }
    mutating func u8() -> UInt8? { guard i + 1 <= d.count else { return nil }; defer { i += 1 }; return d[i] }
    mutating func u16() -> UInt16? { guard i + 2 <= d.count else { return nil }; defer { i += 2 }; return UInt16(d[i]) | UInt16(d[i+1]) << 8 }
    mutating func i16() -> Int16? { u16().map { Int16(bitPattern: $0) } }
    mutating func u24() -> Int? { guard i + 3 <= d.count else { return nil }; defer { i += 3 }; return Int(d[i]) | Int(d[i+1]) << 8 | Int(d[i+2]) << 16 }
    mutating func u32() -> UInt32? { guard i + 4 <= d.count else { return nil }; defer { i += 4 }; return UInt32(d[i]) | UInt32(d[i+1]) << 8 | UInt32(d[i+2]) << 16 | UInt32(d[i+3]) << 24 }
}
