import Foundation

let output = CSS.selfTest()
print(output)
precondition(output.contains(": 0 Fehler."))
// Independent FFT check: a unit impulse has a constant spectrum.
let impulse = [ComplexSample(i: 1, q: 0)] + Array(repeating: ComplexSample(i: 0, q: 0), count: 127)
precondition(CSS.fft(impulse).allSatisfy { abs($0.i - 1) < 1e-10 && abs($0.q) < 1e-10 })
// Independent CF32LE fixture, including a deliberately unaligned Data buffer.
let bytes: [UInt8] = [0x00,0x00,0x80,0x3f,0,0,0,0, 0,0,0,0,0,0,0x80,0x3f]
let summary = try IQSummary.readCF32LE(Data(bytes))
precondition(summary.sampleCount == 2 && summary.meanPower == 1 && summary.peakPower == 1)
for bad in [Data(), Data([0]), Data([0,0,0x80,0x7f,0,0,0,0])] {
    do { _ = try IQSummary.readCF32LE(bad); fatalError("Invalid input accepted") }
    catch { print("Invalid input correctly rejected:", error.localizedDescription) }
}
print("PASS: CSS roundtrip, FFT impulse, CF32LE parser and invalid-input handling")
