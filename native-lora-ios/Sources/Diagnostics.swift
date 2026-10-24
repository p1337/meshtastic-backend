import Foundation

struct LabEnvironment: Codable {
    var model: String
    var os: String
    var appVersion: String
    var build: String
    var simulator: Bool
    var processorCount: Int
    var memoryMiB: UInt64
}

struct LabCheck: Codable, Identifiable {
    var id: String
    var name: String
    var status: String
    var cases: Int
    var errors: Int
    var milliseconds: Double
    var detail: String
    var metrics: [String: Double] = [:]
}

struct NoiseMeasurement: Codable, Identifiable {
    var sf: Int
    var snrDB: Double
    var trials: Int
    var errors: Int
    var id: String { "\(sf):\(snrDB)" }
}

struct LabReport: Codable {
    var schemaVersion = 2
    var runID = UUID().uuidString
    var createdUTC = Date().ISO8601Format()
    var environment: LabEnvironment
    var extended: Bool
    var checks: [LabCheck]
    var noise: [NoiseMeasurement]
    var totalMilliseconds: Double
    var liveRF = false
    var packetDecoder = false
    var sampleSource = "synthetic-software-only"
    var failedChecks: Int { checks.filter { $0.status == "failed" }.count }
    var totalCases: Int { checks.reduce(0) { $0 + $1.cases } }

    func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
    var text: String {
        var lines = ["LoRa Lab · automatischer Software-Testbericht", createdUTC,
                     "\(environment.model) · iOS/OS \(environment.os)",
                     "Version \(environment.appVersion) (\(environment.build)) · Simulator: \(environment.simulator)",
                     "\(totalCases) Fälle · \(failedChecks) fehlgeschlagene Prüfgruppen",
                     "Laufzeit: \(String(format: "%.1f", totalMilliseconds)) ms",
                     "Live-RF: nicht verfügbar. Kein Paketcodec. Quelle: synthetisch."]
        lines += checks.map { "[\($0.status)] \($0.name): \($0.cases) Fälle, \($0.errors) Abweichungen. \($0.detail)" }
        lines += noise.map { "AWGN SF\($0.sf), \($0.snrDB) dB: \($0.errors)/\($0.trials) Symbolfehler" }
        lines.append("Die AWGN-Messung ist keine Empfangsempfindlichkeit oder RF-Link-Budget-Messung.")
        return lines.joined(separator: "\n")
    }
}

struct SeededNoise {
    var state: UInt64 = 0x15A17C55
    mutating func uniform() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return (Double(state >> 11) + 0.5) / 9007199254740992.0
    }
    mutating func gaussianPair() -> ComplexSample {
        let radius = sqrt(-2 * log(uniform()))
        let angle = 2 * Double.pi * uniform()
        return ComplexSample(i: radius * cos(angle), q: radius * sin(angle))
    }
}

enum LabDiagnostics {
    static func run(environment: LabEnvironment, extended: Bool = false) -> LabReport {
        let started = Date()
        var checks: [LabCheck] = []
        func check(_ id: String, _ title: String, _ detail: String, _ body: () -> (Int, Int)) {
            let begin = Date(); let (count, errors) = body()
            checks.append(LabCheck(id: id, name: title, status: errors == 0 ? "passed" : "failed",
                                   cases: count, errors: errors, milliseconds: Date().timeIntervalSince(begin) * 1000,
                                   detail: detail))
        }
        check("fft", "FFT gegen analytische Referenz", "Einzelton-Bins und Impuls, unabhängig vom Chirp-Modulator.") {
            var errors = 0
            for bin in [0, 1, 13, 64, 127] {
                let tone = (0..<128).map { k -> ComplexSample in
                    let a = 2 * Double.pi * Double(bin * k) / 128
                    return ComplexSample(i: cos(a), q: sin(a))
                }
                let spectrum = CSS.fft(tone)
                if abs(spectrum[bin].i - 128) > 1e-7 || abs(spectrum[bin].q) > 1e-7 { errors += 1 }
                if spectrum.enumerated().contains(where: { $0.offset != bin && $0.element.power > 1e-12 }) { errors += 1 }
            }
            let impulse = [ComplexSample(i: 1, q: 0)] + Array(repeating: ComplexSample(i: 0, q: 0), count: 127)
            if !CSS.fft(impulse).allSatisfy({ abs($0.i - 1) < 1e-10 && abs($0.q) < 1e-10 }) { errors += 1 }
            return (6, errors)
        }
        check("clean", "CSS SF7–SF12", "Saubere Symbole bei bekannten Symbolgrenzen; kein LoRa-Pakettest.") {
            var count = 0, errors = 0
            for sf in 7...12 {
                let n = 1 << sf
                let values = Set((0..<(extended ? 256 : 64)).map { ($0 * 197 + 31) % n } + [0, 1, n / 2, n - 1])
                for value in values {
                    count += 1
                    if CSS.decodeAligned(CSS.symbol(sf: sf, value: value), sf: sf) != value { errors += 1 }
                }
            }
            return (count, errors)
        }
        check("gain-phase", "Pegel und Phasendrehung", "Vier lineare Pegel und drei Phasen; synthetisch, ohne AGC oder ADC.") {
            var count = 0, errors = 0
            for sf in 7...12 {
                for amplitude in [0.01, 0.1, 1.0, 10.0] {
                    for phase in [0.0, Double.pi / 2, Double.pi] {
                        let rotation = ComplexSample(i: amplitude * cos(phase), q: amplitude * sin(phase))
                        let samples = CSS.symbol(sf: sf, value: 37).map { $0 * rotation }
                        count += 1
                        if CSS.decodeAligned(samples, sf: sf) != 37 { errors += 1 }
                    }
                }
            }
            return (count, errors)
        }
        check("frequency", "Frequenzversatz", "Erwartete Binverschiebung bei 0, ±0,25, ±1 und ±4 FFT-Bins. Keine automatische Frequenzkorrektur.") {
            var count = 0, errors = 0
            for sf in 7...12 {
                let n = 1 << sf
                for offset in [-4.0, -1, -0.25, 0, 0.25, 1, 4] {
                    let samples = CSS.symbol(sf: sf, value: 37).enumerated().map { k, sample in
                        let angle = 2 * Double.pi * offset * Double(k) / Double(n)
                        return sample * ComplexSample(i: cos(angle), q: sin(angle))
                    }
                    let expected = (37 + Int(offset.rounded()) + n) % n
                    count += 1
                    if CSS.decodeAligned(samples, sf: sf) != expected { errors += 1 }
                }
            }
            return (count, errors)
        }
        check("timing", "Verschobene Symbolgrenzen", "Zyklische Verschiebung und analytische Binverschiebung. Keine Präambel- oder Paketsynchronisation.") {
            var count = 0, errors = 0
            for sf in 7...12 {
                let n = 1 << sf, source = CSS.symbol(sf: sf, value: 37)
                for shift in [1, 7, n / 8, n - 1] {
                    let shifted = (0..<n).map { source[($0 + shift) % n] }
                    count += 1
                    if CSS.decodeAligned(shifted, sf: sf) != (37 + shift) % n { errors += 1 }
                }
            }
            return (count, errors)
        }
        var noise = [NoiseMeasurement](); var random = SeededNoise()
        let noiseStart = Date()
        for sf in 7...12 {
            for snr in [-18.0, -12, -6, 0, 10] {
                let trials = extended ? 32 : 8
                let sigma = sqrt(pow(10, -snr / 10) / 2)
                var errors = 0
                for trial in 0..<trials {
                    let value = (trial * 173 + 37) % (1 << sf)
                    let samples = CSS.symbol(sf: sf, value: value).map { sample -> ComplexSample in
                        let z = random.gaussianPair()
                        return ComplexSample(i: sample.i + sigma * z.i, q: sample.q + sigma * z.q)
                    }
                    if CSS.decodeAligned(samples, sf: sf) != value { errors += 1 }
                }
                noise.append(NoiseMeasurement(sf: sf, snrDB: snr, trials: trials, errors: errors))
            }
        }
        let highSNRErrors = noise.filter { $0.snrDB == 10 }.reduce(0) { $0 + $1.errors }
        checks.append(LabCheck(id: "noise", name: "Rauschen: AWGN-Messreihe", status: highSNRErrors == 0 ? "passed" : "failed",
                               cases: noise.reduce(0) { $0 + $1.trials }, errors: highSNRErrors,
                               milliseconds: Date().timeIntervalSince(noiseStart) * 1000,
                               detail: "30 Messpunkte, feste Zufallsfolge. Nur +10 dB wird auf Fehlerfreiheit geprüft; Fehler bei niedrigem SNR sind Messergebnisse."))
        check("cf32", "CF32LE und Eingabegrenzen", "Bekannte Bytes, leere/abgeschnittene Daten, NaN/Inf, Stille und 8-MiB-Grenze.") {
            var errors = 0
            do {
                let fixture = Data([0,0,0x80,0x3f,0,0,0,0, 0,0,0,0,0,0,0x80,0x3f])
                let v = try IQSummary.readCF32LE(fixture)
                if v.sampleCount != 2 || v.meanPower != 1 || v.peakPower != 1 { errors += 1 }
                if try IQSummary.readCF32LE(Data(repeating: 0, count: 2048 * 8)).firstSF11Symbol != nil { errors += 1 }
            } catch { errors += 1 }
            let bad = [Data(), Data([0]), Data(repeating: 0, count: 9),
                       Data([0,0,0x80,0x7f,0,0,0,0]), Data([0,0,0xc0,0x7f,0,0,0,0]),
                       Data(repeating: 0, count: 8 * 1024 * 1024 + 8)]
            for data in bad {
                do { _ = try IQSummary.readCF32LE(data); errors += 1 } catch { }
            }
            return (8, errors)
        }
        check("analyzer", "Dateianalyse gegen bekannte Referenz", "CF32-Demodulation bei Fs=BW; Sampleratenfehler, Stille und falsche Daten werden getrennt behandelt.") {
            var errors = 0
            do {
                let data = IQAnalysis.fixture(sf: 11, value: 173)
                let v = try IQAnalysis.analyze(data, sampleRate: 250_000, bandwidth: 250_000, sf: 11)
                if v.symbolBin != 173 || abs(v.meanPower - 1) > 1e-6 { errors += 1 }
                let mismatched = try IQAnalysis.analyze(data, sampleRate: 500_000, bandwidth: 250_000, sf: 11)
                if mismatched.symbolBin != nil { errors += 1 }
                let silent = try IQAnalysis.analyze(Data(repeating: 0, count: 2048 * 8), sampleRate: 250_000, bandwidth: 250_000, sf: 11)
                if silent.symbolBin != nil { errors += 1 }
                do { _ = try IQAnalysis.analyze(data, sampleRate: 0, bandwidth: 250_000, sf: 11); errors += 1 } catch { }
            } catch { errors += 1 }
            return (4, errors)
        }
        let benchmarkStart = Date()
        let frame = CSS.symbol(sf: 11, value: 173)
        for _ in 0..<32 { _ = CSS.decodeAligned(frame, sf: 11) }
        let elapsed = Date().timeIntervalSince(benchmarkStart) * 1000
        checks.append(LabCheck(id: "benchmark", name: "DSP-Laufzeit", status: "measured", cases: 32, errors: 0,
                               milliseconds: elapsed, detail: "32 ausgerichtete SF11-Symbole; keine Aussage über Echtzeit-Funkempfang.",
                               metrics: ["millisecondsPerSymbol": elapsed / 32]))
        checks.append(LabCheck(id: "rf", name: "Interner Funkzugang", status: "unsupported", cases: 0, errors: 0,
                               milliseconds: 0, detail: "Kein nachgewiesener RF-I/Q-Zugang. Kein Sendetest und keine Funkaufnahme."))
        return LabReport(environment: environment, extended: extended, checks: checks, noise: noise,
                         totalMilliseconds: Date().timeIntervalSince(started) * 1000)
    }
}

struct IQAnalysis: Codable {
    var sampleCount: Int
    var sampleRate: Double
    var bandwidth: Double
    var sf: Int
    var meanPower: Double
    var peakPower: Double
    var dcI: Double
    var dcQ: Double
    var nearFullScaleFraction: Double
    var symbolBin: Int?
    var peakEnergyFraction: Double?
    var note: String
    var duration: Double { Double(sampleCount) / sampleRate }

    static func analyze(_ data: Data, sampleRate: Double, bandwidth: Double, sf: Int) throws -> Self {
        guard sampleRate.isFinite, sampleRate > 0, [125_000.0, 250_000, 500_000].contains(bandwidth), (7...12).contains(sf) else {
            throw AnalysisError.invalidConfiguration
        }
        let summary = try IQSummary.readCF32LE(data)
        var sumI = 0.0, sumQ = 0.0, nearFullScale = 0
        var frame = [ComplexSample](); let n = 1 << sf
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for offset in stride(from: 0, to: data.count, by: 8) {
                let i = Double(Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))))
                let q = Double(Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self))))
                sumI += i; sumQ += q
                if abs(i) >= 0.999 || abs(q) >= 0.999 { nearFullScale += 1 }
                if frame.count < n { frame.append(ComplexSample(i: i, q: q)) }
            }
        }
        var bin: Int?, fraction: Double?
        var note = "Nur erstes ausgerichtetes Symbol; kein Paketnachweis."
        if abs(sampleRate - bandwidth) > 0.001 {
            note = "Keine Chirp-Auswertung: Fs muss hier BW entsprechen. Keine ungefilterte Dezimation."
        } else if frame.count < n || frame.allSatisfy({ $0.power == 0 }) {
            note = "Keine Chirp-Auswertung: zu wenige Samples oder Stille."
        } else {
            let spectrum = CSS.fft(frame.enumerated().map { k, sample -> ComplexSample in
                let chirp = CSS.reference(sf: sf, index: k)
                return sample * ComplexSample(i: chirp.i, q: -chirp.q)
            })
            let index = spectrum.indices.max { spectrum[$0].power < spectrum[$1].power }!
            let energy = spectrum.reduce(0) { $0 + $1.power }
            if energy > 0 { bin = index; fraction = spectrum[index].power / energy }
        }
        return Self(sampleCount: summary.sampleCount, sampleRate: sampleRate, bandwidth: bandwidth, sf: sf,
                    meanPower: summary.meanPower, peakPower: summary.peakPower,
                    dcI: sumI / Double(summary.sampleCount), dcQ: sumQ / Double(summary.sampleCount),
                    nearFullScaleFraction: Double(nearFullScale) / Double(summary.sampleCount),
                    symbolBin: bin, peakEnergyFraction: fraction, note: note)
    }

    static func fixture(sf: Int, value: Int) -> Data {
        var data = Data()
        for sample in CSS.symbol(sf: sf, value: value) {
            for number in [sample.i, sample.q] {
                var bits = Float(number).bitPattern.littleEndian
                withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
            }
        }
        return data
    }

    enum AnalysisError: LocalizedError {
        case invalidConfiguration
        var errorDescription: String? { "Samplerate muss positiv sein; SF7–SF12 und BW125/250/500 sind zulässig." }
    }
}
