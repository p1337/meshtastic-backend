# Incyclist integration — source change required

Target: `incyclist/mobile@1969e6442a9ae807b1f9ae0b9cd865400d7d6873` and its existing `incyclist-services` exports. This is **not** a control interface in the released Incyclist application.

`shiftRouter.js` is executed inside Incyclist. It calls `useDeviceRide().sendUpdate({gearDelta})` and never opens a second trainer connection. The UI labels results as a submitted software request. Incyclist currently settles adapter updates with `Promise.allSettled`; a resolved call is not proof of hardware success. The adapter refuses ERG, disabled virtual shifting, multiple/no active control adapters, busy updates, duplicate/stale events and stale ride sessions. It does not change route slope, ERG targets, or the trainer's control ownership.

`ClickBridgeModule.swift` embeds the shared BLE package and provides controller discovery/assignment UI. It has its own restoration namespace; do not simultaneously connect the Clicks from Incyclist's legacy device picker or standalone ClickBridge. Connect only D100 in the usual Incyclist trainer picker.

Apply the supplied patch to the exact pinned Incyclist checkout. The installer copies this whole self-contained Swift Package to `clickbridge-kit/`, adds the Swift/ObjC module and React controls, updates the Xcode project, and raises the integration build to iOS 18. The upstream source remains MIT. App publication still requires a suitable signed Incyclist-derived build and its maintainers' decisions. The standalone ClickBridge signing profile does not sign Incyclist.

```sh
python3 clickbridge-ios/integrations/incyclist/install.py /absolute/path/to/incyclist-mobile
cd /absolute/path/to/incyclist-mobile
npm ci
cd ios
pod install
```

Software routing tests (Node built-ins only):

```sh
node --test clickbridge-ios/integrations/incyclist/shiftRouter.test.cjs
```

The installation script and patch applicability are tested against the pinned checkout. A complete Incyclist native build, React Native 0.83 bridge compatibility, UI placement and real trainer operation must still be validated. Do not market this adapter as a working integration until all ten hardware criteria pass.
