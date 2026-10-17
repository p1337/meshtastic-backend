# Werkbeleg 1.2.0 — Build 24

Stand 17.10.2026. Source commit: 07a7c8cdf9ebab9c7fe0982524d45c930aa3c645. The native build, simulator smoke test, Apple Distribution signature check and GitHub Pages deployment completed successfully: https://github.com/p1337/meshtastic-backend/actions/runs/39060462363 . Installation: https://p1337.github.io/meshtastic-backend/?build=24 .

## Bedienung

Kunden → Kunden übernehmen → Datei auswählen → Felder prüfen → Vorschau → Übernehmen. CSV/TSV/Text, XLSX and vCard are read on device. Unknown columns can be mapped or ignored; possible duplicates are deselected. Selecting a duplicate explicitly adds another record, never overwrites the existing customer. The last import can be undone selectively: changed customers and customers referenced by projects are retained. Search and customer detail pages include structured contact/address metadata and related projects.

Example: WERKBELEG_KUNDEN_VORLAGE.csv contains two fictional customers only. Maximum source file 10 MiB, 10,000 customers, 80 columns, 4096 characters/field. XLSX ZIP expansion is bounded to 40 MiB. Legacy XLS, encrypted/macro workbooks and formula sheets require a CSV or values-only XLSX export. XLSX reads cell values rather than arbitrary display formats: keep postal codes and customer numbers as text and inspect the preview. No vendor API synchronisation is active.

## Tests actually completed

- 41 native Foundation/import regression assertions: model validation and backup roundtrip, CSV quoting/newlines, leading zeros, Windows-1250, vCard multiple phone numbers, duplicates, selective undo, independent deflated/stored OOXML fixtures, formula/entity/invalid-reference/truncated/corrupt ZIP rejection.
- Native simulator launched the actual app. Workflow assertions required disk persistence, backup roundtrip, multipage PDF, photo pixel size, local-only speech request policy, customer import/undo and separate local team areas. No camera/microphone or live cloud was tested. The unsigned simulator uses an explicitly isolated token test double; success does not prove real iPhone Keychain ACLs. That test double is excluded from the signed device build.
- 50 PostgreSQL assertions passed: https://github.com/p1337/meshtastic-backend/actions/runs/39060337905 . Coverage includes tenant isolation, roles, immutable org IDs even for dual membership, atomic insert-only admin import, recipient-bound invite codes, membership revocation, private media, quotas and unique server-only subscription ownership.
- The macOS build verified Apple Distribution authority, matching Ad Hoc profile and arm64 iOS device binary. The profile supports the one registered iPhone. Deployment job 117479409001 succeeded.

Evidence artifacts from run 39060462363: native diagnostics 12111262305; simulator diagnostics 12111277942; Apple-signed IPA 12111069283. Their archive digests are available from GitHub. Additional local artifact downloads and screenshot inspection stalled in the execution environment and were not completed. Do not claim an independently re-downloaded public IPA hash or visually inspected final screenshot. Installation and actual Keychain/capture behavior on Robert's iPhone still require confirmation.

## Separation and release boundaries

Each server/personal-token combination uses its own local Contexts directory. Earlier pilot data remains in the local area; connecting a team does not automatically upload it. Late responses after a context change are rejected. Full backup restore is local-only.

Old anonymous invitation joining is deliberately disabled in native 1.2 pending authenticated recipient integration. SQL migration 002 provides bound invitations and membership revocation, but the hosted native sign-in/verified-recipient flow is not connected. This must not be advertised as active WhatsApp onboarding.

No Supabase account connection or live cloud was provisioned, no customer data uploaded, no paid plan purchased. Missing production work: native hosted Auth and record/media sync, trusted upload/finalisation, actual Apple purchase verification/webhooks/billing, real multi-device/provider integration, independent security review and verified European processing paths. The subscription table alone is not purchase verification. This build is an installable local-first pilot, not production SaaS certification or a 100% security guarantee.
