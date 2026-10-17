# Trace metadata probe, version 0.4.0

The automatic runtime audit now queries only selected metadata on services matching `AppleBasebandPCITraceBackendRaw`. It does not open a user client, read a log, call a driver method, map memory or change the modem. No trace output is identified as RF I/Q.

## Provenance

- Apple's [IOKitLib.h](https://github.com/apple-oss-distributions/IOKitUser/blob/main/IOKitLib.h) defines IOServiceMatching, IOServiceGetMatchingServices, IOIteratorNext, IOObjectRelease and IORegistryEntryCreateCFProperty. The latter returns a retained CF object or NULL; NULL does not distinguish an absent property from access restrictions.
- [Published libIOABP decompilation](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/e26ed4563f78871c59d2d96856756a65d62517e5/usr/lib/libIOABP/libIOABP.m) names TracePipes, SnapshotBufferSize, Code and Name in the trace-client path. It is evidence for that specific older binary, with visible decompiler artifacts, not a verified current driver ABI. No opening type or method selectors are reused.
- IOClass, IOProviderClass and IOUserClientClass are selected IOKit class metadata keys. No arbitrary property dictionary is exported.

## Limits and interpretation

At most 16 service instances and five named properties per instance are queried. Pipe results store at most 64 valid Code/Name pairs from the first 64 entries; class lists store at most 32 entries. Names are limited to 160 Unicode scalars and control characters are removed. Additional dictionary fields, binary values and unknown keys are not exported. The UInt32 numeric fields reject booleans, negative, fractional, nonfinite and out-of-range values. Reported buffer size never drives an allocation and is not converted to RF duration.

Statuses distinguish observed, empty, partial, type_mismatch, not_returned, unavailable and an actual matching-call error. A NULL property result has no invented kern_return or errno. A successful matching result is not represented as permission to open a service.

The simulator explicitly skips physical-service inspection. Native regression tests cover malformed/oversized metadata, bounds, control characters, unsupported keys, missing-value ambiguity and JSON serialization. Simulator integration verifies a skipped physical trace probe, a real foreground 60-second metadata session and zero RF claims. A real phone must provide new metadata before any subsequent access experiment can be justified.

No real-device runtime report is included in this source change. Reports remain local and require the user's explicit share action. The app icon, signing identity and OTA route are retained.
