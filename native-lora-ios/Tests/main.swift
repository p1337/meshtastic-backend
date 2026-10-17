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

let environment = LabEnvironment(model: "CI-host", os: ProcessInfo.processInfo.operatingSystemVersionString,
                                 appVersion: "0.2.0", build: ProcessInfo.processInfo.environment["GITHUB_RUN_NUMBER"] ?? "local",
                                 simulator: false, processorCount: ProcessInfo.processInfo.processorCount,
                                 memoryMiB: ProcessInfo.processInfo.physicalMemory / 1048576)
let report = LabDiagnostics.run(environment: environment, extended: true)
print(report.text)
precondition(report.failedChecks == 0, "Automated diagnostic regression failed")
precondition(report.noise.count == 30 && report.totalCases > 2000)
precondition(report.checks.first(where: { $0.id == "rf" })?.status == "unsupported")
let roundtrip = try JSONDecoder().decode(LabReport.self, from: report.json())
precondition(roundtrip.totalCases == report.totalCases && !roundtrip.liveRF && !roundtrip.packetDecoder)
if let flag = CommandLine.arguments.firstIndex(of: "--json"), flag + 1 < CommandLine.arguments.count {
    try report.json().write(to: URL(fileURLWithPath: CommandLine.arguments[flag + 1]), options: .atomic)
}
print("PASS: extended diagnostics, 30 AWGN points, input validation and Codable report")
