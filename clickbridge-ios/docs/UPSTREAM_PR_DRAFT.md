# Prepared upstream proposal (not submitted)

Target: incyclist/mobile. Base: `1969e6442a9ae807b1f9ae0b9cd865400d7d6873`.

Title: **Embed a native Click V2 input provider while retaining Incyclist trainer ownership**

Incyclist's audited BLE controller implementation does not explicitly recognise the Click V2 FC82 service and independent left/right types. A companion app on the same iPhone cannot supply touch/HID input through public iOS APIs. This proposal embeds a small Swift/CoreBluetooth provider in the iOS application and routes its button events to the existing `DeviceRideService.sendUpdate({gearDelta})` path. It opens no second trainer connection and changes no route slope or ERG target.

The patch includes explicit controller assignment, per-device connections, a bounded decoder, lifecycle restoration, diagnostics and a ride-scoped React Native adapter. The adapter rejects stale/duplicate events, disabled virtual shifting, ERG, paused/missing/multiple control targets and concurrent updates. It labels a resolved Incyclist call as a submitted software request, not a physical trainer acknowledgement.

Validation completed and remaining: portable Swift unit tests and Node routing tests; patch applied against the pinned source. A complete React Native native integration build and the ten real iPhone/Click V2/D100 acceptance tests are still required. The left Click V2's firmware-dependent time lock remains a blocker for a promise of unrestricted offline operation. This should remain a draft until hardware evidence is attached.

Tradeoff: this experimental integration build raises iOS minimum to 18.0; maintainers should decide whether an availability-gated iOS 15.5-compatible BLE-only package is preferable before merging. Configurable ClickBridge ratios are not forced into existing Incyclist cycling modes; its own gear table remains authoritative.

Patch: `integrations/incyclist/mobile.patch`. License: new provider MIT, upstream MIT notices retained. No BikeControl proprietary/non-commercial code or GPL SwiftControl code copied. No Apple signing keys, API keys or real device IDs are part of the patch.
