# Werkbeleg — continuation instructions

The user stopped the LoRa research. Current task is a native iPhone work-documentation product for small trades businesses, up to 20 staff, initially DACH/Poland/English. Working name Werkbeleg, not trademark-cleared. Palette: white, black, orange, yellow. Read WERKBELEG.md for the actual feature boundary. Never call backup exports cloud sync or a tested pilot a production-ready 20-seat service.

Compile only the five files in Werkbeleg/. Sources/ contains the stopped LoRa app and is retained for history. Keep technical bundle de.p1337.LoRaLab and scheme LoRaLab for the existing Apple AdHoc profile. Visible identity is Werkbeleg. Existing apple-signing secrets and github-pages environment are sufficient for the test pipeline; do not ask the user to recreate them. Source branch codex/native-lora-ios in p1337/meshtastic-backend; master remains untouched.

Foundation model validation runs as a native command-line Swift test. Team server tests run Python unittest using only synthetic fixtures. Simulator runs the app with --werkbeleg-smoke and exports Werkbeleg-Smoke.json with persistence, attachment backup roundtrip and multi-page PDF checks. It must not claim camera/microphone/GPS have been tested. Normal launches do not create demo customers or reports. Do not publish customer files, tokens, device identifiers or signing material to the public repository.

Local workspace: Application Support/Werkbeleg/workspace.json, atomic Data writes with complete file protection. No automatic upload. Team access token goes in Keychain, not UserDefaults; only URL/author/language are ordinary preferences. Team snapshots have optimistic integer versions; GET then PUT with compare-and-swap. A conflict must never silently overwrite. Server is single-business, up to 20 named tokens, admin/editor/reader roles, 30 MiB snapshot limit, 10 server-side history revisions. No internet server has been provisioned. App requires HTTPS. Reverse proxy and backup configuration belong to deployment; Python HTTP listener stays localhost.

Before production prioritize authenticated multi-device integration tests, storage growth/differential synchronization, data recovery, per-record conflict handling, audio playback experience and camera/GPS/speech permission errors on real devices. Automatic weather, logos, app-store subscription and store publication are not implemented. Do not invent Apple WeatherKit entitlements or set them without matching signed provisioning. Prices are proposals only, not a configured StoreKit subscription.

Native build/signature/OTA scripts are intentionally reused. Display/UI version currently 1.1.1 (pilot); GitHub run number is build number. Source sharing and publishing Apple-signed test builds are authorized by the user. Test one reviewed commit first to avoid canceling a slow simulator job through redundant pushes.


## Version 1.1 direction

User defined exact monthly per-business tiers: up to 5 people €9.99; 10 €14.99; 20 €19.99. Count includes owner (stated assumption). Billing remains unconfigured. Default server seat cap 5, CLI --plan 5/10/20. Owner bootstrap --role admin; normal editor/reader cannot invite. Pending invites reserve seats, expire in 48h, hash-only, single-use. Native TeamView handles admin create + WhatsApp share (wa.me/?text=), with user choosing recipient and confirming send. Never send on user's behalf from MCP tools without explicit recipient instruction.

ProjectChatView polls every 10 seconds in foreground only. Messages table independent of workspace CAS versions; authors derived server-side, idempotent UUIDs, 4000 chars, 10000 messages cap. GET workspace injects chat from the table, PUT strips cached messages to prevent snapshot upload from erasing chat. Legacy 1.0 backups decode missing messages as []. StoreKit is not implemented; don't present these tier cards as active subscriptions.

Invites use public HTTPS join.html with code in fragment, no token in query/server logs. Static page forwards only on user gesture to werkbeleg://join (Info.plist custom scheme). App displays server domain and replacement warning before redeeming. Existing local data must be backed up. New users still need an installable signed app; the existing AdHoc profile has one registered iPhone only. No server or multi-device production deployment has been provisioned.


EU requirement: business data should be stored in Europe, preferred fixed region Frankfurt eu-central-1. Supabase regional database/storage/backups do not guarantee that all CDN/support/metadata processing stays in EU; do not claim EU-only service without validating all paths. Version 1.1.1 enforces on-device Speech: check supportsOnDeviceRecognition before requesting transcription, then requiresOnDeviceRecognition=true. No server fallback; unsupported languages retain audio/manual entry. Never re-enable network speech by default.
