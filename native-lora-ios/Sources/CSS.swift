import Foundation

struct ComplexSample {
    var i: Double
    var q: Double
    static func * (a: Self, b: Self) -> Self {
        Self(i: a.i * b.i - a.q * b.q, q: a.i * b.q + a.q * b.i)
    }
    var power: Double { i * i + q * q }
}

enum CSS {
    static func reference(sf: Int, index: Int) -> ComplexSample {
        let n = Double(1 << sf), t = Double(index)
        let phase = 2 * Double.pi * (t * t / (2 * n) - t / 2)
        return ComplexSample(i: cos(phase), q: sin(phase))
    }
    static func symbol(sf: Int, value: Int) -> [ComplexSample] {
        (0..<(1 << sf)).map { k in
            let phase = 2 * Double.pi * Double(value * k) / Double(1 << sf)
            return reference(sf: sf, index: k) * ComplexSample(i: cos(phase), q: sin(phase))
        }
    }
    // Radix-2 FFT; input must have a power-of-two length.
    static func fft(_ input: [ComplexSample]) -> [ComplexSample] {
        let n = input.count
        precondition(n > 0 && n.nonzeroBitCount == 1)
        var a = input
        var j = 0
        if n > 1 {
            for i in 1..<n {
                var bit = n >> 1
                while j & bit != 0 { j ^= bit; bit >>= 1 }
                j ^= bit
                if i < j { a.swapAt(i, j) }
            }
        }
        var length = 2
        while length <= n {
            let angle = -2 * Double.pi / Double(length)
            let root = ComplexSample(i: cos(angle), q: sin(angle))
            for start in stride(from: 0, to: n, by: length) {
                var w = ComplexSample(i: 1, q: 0)
                for offset in 0..<(length / 2) {
                    let u = a[start + offset]
                    let v = a[start + offset + length / 2] * w
                    a[start + offset] = ComplexSample(i: u.i + v.i, q: u.q + v.q)
                    a[start + offset + length / 2] = ComplexSample(i: u.i - v.i, q: u.q - v.q)
                    w = w * root
                }
            }
            length <<= 1
        }
        return a
    }
    static func decodeAligned(_ samples: [ComplexSample], sf: Int) -> Int {
        precondition(samples.count == 1 << sf)
        let mixed = samples.enumerated().map { k, sample -> ComplexSample in
            let chirp = reference(sf: sf, index: k)
            return sample * ComplexSample(i: chirp.i, q: -chirp.q)
        }
        let bins = fft(mixed)
        return bins.indices.max(by: { bins[$0].power < bins[$1].power }) ?? 0
    }
    static func selfTest() -> String {
        var total = 0, failed = 0
        for sf in 7...12 {
            let size = 1 << sf
            let values = Set([0, 1, 2, size / 4, size / 2, size - 2, size - 1]
                + (0..<16).map { ($0 * 197 + 31) % size }).sorted()
            for value in values {
                total += 1
                if decodeAligned(symbol(sf: sf, value: value), sf: sf) != value { failed += 1 }
            }
        }
        return "\(total) synthetische CSS-Symbole, SF7–SF12: \(failed) Fehler.\nBekannte Symbolgrenzen, kein Paketcodec und kein Funkempfang."
    }
}

struct IQSummary {
    let sampleCount: Int
    let meanPower: Double
    let peakPower: Double
    let firstSF11Symbol: Int?

    static func readCF32LE(_ data: Data) throws -> IQSummary {
        guard !data.isEmpty, data.count % 8 == 0 else { throw IQError.invalidSize }
        guard data.count <= 8 * 1024 * 1024 else { throw IQError.tooLarge }
        var count = 0, sum = 0.0, peak = 0.0
        var first: [ComplexSample] = []
        first.reserveCapacity(2048)
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for offset in stride(from: 0, to: data.count, by: 8) {
                let iBits = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
                let qBits = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self))
                let i = Double(Float(bitPattern: iBits)), q = Double(Float(bitPattern: qBits))
                guard i.isFinite && q.isFinite else { throw IQError.nonFinite }
                let sample = ComplexSample(i: i, q: q)
                let p = sample.power
                sum += p; peak = max(peak, p); count += 1
                if first.count < 2048 { first.append(sample) }
            }
        }
        return IQSummary(sampleCount: count, meanPower: sum / Double(count), peakPower: peak,
                         firstSF11Symbol: first.count == 2048 && peak > 0 ? CSS.decodeAligned(first, sf: 11) : nil)
    }
    enum IQError: LocalizedError {
        case invalidSize, tooLarge, nonFinite
        var errorDescription: String? {
            switch self {
            case .invalidSize: return "CF32LE benötigt I/Q-Paare mit jeweils 8 Byte."
            case .tooLarge: return "Maximal 8 MiB pro Datei."
            case .nonFinite: return "Datei enthält ungültige Float-Werte."
            }
        }
    }
}
