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
                                 appVersion: "0.4.0", build: ProcessInfo.processInfo.environment["GITHUB_RUN_NUMBER"] ?? "local",
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

// Timed diagnostics must never turn waiting or metadata into an RF recording.
for seconds in [Double.nan, Double.infinity, -1, 0, 301] {
    do { _ = try AccessSession(seconds: seconds, startedUTC: "test"); fatalError("Invalid duration accepted") }
    catch { }
}
var session = try AccessSession(seconds: 60, startedUTC: "2026-10-17T00:00:00Z")
try session.record(elapsed: 0, utc: "t0", technologies: ["LTE", "LTE"])
precondition(session.observations[0].radioTechnologies == ["LTE"])
for time in [Double.nan, Double.infinity, -1, 0] {
    do { try session.record(elapsed: time, utc: "invalid", technologies: []); fatalError("Invalid timestamp accepted") }
    catch { }
}
try session.record(elapsed: 5, utc: "t5", technologies: [])
precondition(session.state == "running" && session.metadataGaps == 1)
try session.record(elapsed: 60, utc: "t60", technologies: ["NR"])
precondition(session.state == "completed" && session.observations.count == 3)
precondition(session.maximumMetadataGap == 55 && session.metadataGaps == 2)
precondition(session.rfIQSamples == 0 && !session.rfCaptureAvailable && session.rfCenterFrequencyHz == nil)
do { try session.record(elapsed: 61, utc: "late", technologies: []); fatalError("Completed session accepted data") }
catch { }
session.stop(interrupted: true)
precondition(session.state == "completed")
var interrupted = try AccessSession(seconds: 60, startedUTC: "test")
try interrupted.record(elapsed: 0, utc: "test", technologies: [])
interrupted.stop(interrupted: true)
precondition(interrupted.state == "interrupted" && interrupted.elapsed == 0)
var cancelled = try AccessSession(seconds: 60, startedUTC: "test")
cancelled.stop(interrupted: false)
precondition(cancelled.state == "cancelled")
let encodedSession = try JSONEncoder().encode(session)
let decodedSession = try JSONDecoder().decode(AccessSession.self, from: encodedSession)
precondition(decodedSession.observations.count == 3 && decodedSession.rfIQSamples == 0 && !decodedSession.rfCaptureAvailable)
let audit = RuntimeAudit.run(environment: environment)
precondition(!audit.rfIQSourceVerified && audit.rfIQSamples == 0 && audit.modemCommandsSent == 0 && audit.driverConnectionsOpened == 0)
precondition(audit.probes.contains { $0.id == "iq" && $0.status == "unverified" })
let decodedAudit = try JSONDecoder().decode(RuntimeAuditReport.self, from: JSONEncoder().encode(audit))
precondition(decodedAudit.source == "read-only-runtime-observations")
print("PASS: honest session state, monotonic timing, metadata gaps, cancellation/background interruption, no RF claims and audit serialization")

// Treat metadata as untrusted input; do not accept Bool, fractional or oversized sizes.
precondition(TracePropertyDecoder.decode(key: "TracePipes", value: nil).status == "not_returned")
precondition(TracePropertyDecoder.decode(key: "TracePipes", value: []).status == "empty")
precondition(TracePropertyDecoder.decode(key: "TracePipes", value: "not-an-array").status == "type_mismatch")
let invalidTraceSizes: [Any] = [true, -1, 1.5, Double.nan, Double.infinity, 4294967296.0, "1024", NSNull()]
for bad in invalidTraceSizes {
    precondition(TracePropertyDecoder.decode(key: "SnapshotBufferSize", value: bad).status == "type_mismatch")
}
let validTraceSizes: [UInt32] = [0, 4096, UInt32.max]
for good in validTraceSizes {
    let p = TracePropertyDecoder.decode(key: "SnapshotBufferSize", value: NSNumber(value: good))
    precondition(p.status == "observed" && p.observations == ["\(good)"])
}
let cleanPipe: [String: Any] = ["Code": 7, "Name": "DIAG\nCHANNEL\u{0}"]
let decodedPipe = TracePropertyDecoder.decode(key: "TracePipes", value: [cleanPipe], instance: 2)
precondition(decodedPipe.id == "trace:2:TracePipes" && decodedPipe.status == "observed")
precondition(decodedPipe.observations == ["#0 · Code 7 · DIAGCHANNEL"])
let malformed = TracePropertyDecoder.decode(key: "TracePipes", value: [cleanPipe, ["Code": true, "Name": "bad"], ["Code": -1, "Name": "bad"], ["Code": 3], 99])
precondition(malformed.status == "partial" && malformed.observations.count == 1)
let manyPipes = Array(repeating: ["Code": 1, "Name": String(repeating: "x", count: 10000)] as [String: Any], count: 80)
let limited = TracePropertyDecoder.decode(key: "TracePipes", value: manyPipes)
precondition(limited.status == "partial" && limited.observations.count == 64)
precondition(limited.observations.allSatisfy { $0.count < 200 })
let names = TracePropertyDecoder.decode(key: "IOUserClientClass", value: Array(repeating: "TestClass", count: 40))
precondition(names.status == "partial" && names.observations.count == 32)
precondition(TracePropertyDecoder.decode(key: "SerialNumber", value: "must-not-export").status == "unsupported")
precondition(TracePropertyDecoder.decode(key: "IOClass", value: Data([1,2,3])).observations.isEmpty)
let decodedProbe = try JSONDecoder().decode(AccessProbe.self, from: JSONEncoder().encode(limited))
precondition(decodedProbe.observations.count == 64 && decodedProbe.status == "partial")
precondition(audit.probes.contains { $0.id == "trace:inventory" && $0.status == "unavailable" })
print("PASS: bounded trace metadata, nil ambiguity, numeric boundaries, malformed records, control characters, allowlist and Codable")
