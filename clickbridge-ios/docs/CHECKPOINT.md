# Fortsetzbarer Arbeitsstand

Stand: 23.10.2026. Dieser Stand wird mit jedem wesentlichen Ergebnis aktualisiert und im Git-Branch gesichert. Ein Abbruch der Chat-Oberfläche bedeutet nicht, dass die hier verlinkten Commits verloren sind.

## Ablage und Auftrag

- Repository: https://github.com/p1337/meshtastic-backend
- Branch: `codex/clickbridge-ios`; eigenständige zweite App unter `clickbridge-ios/`.
- Review: https://github.com/p1337/meshtastic-backend/pull/1 (Entwurf, nicht gemergt).
- Kein neues Repository: Mit dem verfügbaren Zugang lassen sich neue Repository-/Apple-Signing-Schlüssel nicht vollständig einrichten. Daher die ausdrücklich erlaubte bestehende Werkbeleg-Ablage.
- Eigene Bundle-ID `de.p1337.ClickBridge`; bestehende App und deren Installationspfad werden nicht ersetzt.

## Implementiert und gesichert

CoreBluetooth-Verbindungsverwaltung für zwei getrennte Controller-UUIDs, dauerhafte Links-/Rechtszuordnung, GATT-Discovery, dokumentierte Initialisierung, strenger Paketdecoder, Batteriestatus, Firmwareinformationen, begrenzter Reconnect, Diagnoseexport und SwiftUI-App. Konfigurierbare Ganglogik nimmt ohne bestätigten Ausgabepfad keinen wirksamen Gangwechsel an.

Die native Incyclist-Integration liegt als vollständiger, versionsgebundener Quellpatch vor. Sie führt Schaltaufträge durch den bestehenden internen Incyclist-`sendUpdate({gearDelta})`-Pfad. Der unveränderte App-Store-Build hat keinen nachgewiesenen externen Schalteingang. Deshalb ist die eigenständige App gegen diesen Build noch keine funktionierende Gangschaltung.

Quell- und Dokumentationsmeilensteine:

| Commit | Inhalt |
| --- | --- |
| `2b3ded7` | Machbarkeit und Quellprüfung |
| `876cc0c` | BLE-Paketdecoder und Zwei-Controller-Verwaltung |
| `318972b` | Ganglogik und SwiftUI-Oberfläche |
| `57974bc` | Unit-Tests, Xcode-Generierung und CI |
| `dc353e5` | Vollständiger Incyclist-Patch, Dokumentation und Signing-Prüfung |
| `321372f` | Tatsächliche TypeScript-Schnittstelle korrigiert; aktuelle App-Prüfung bestanden |
| `cf1e672` | Zusätzliche Prüfung der nativen React-Native-Brücke |

## Tatsächlich bestanden

[CI-Lauf 40022206773](https://github.com/p1337/meshtastic-backend/actions/runs/40022206773): **20 Swift-XCTest-Methoden und sieben Node-Routingtests bestanden**, Xcode-Projekt reproduzierbar generiert, echte Simulator-App gebaut und gestartet, Screenshot geprüft, unsignierte arm64-Geräte-IPA gebaut und unabhängig auf Inhalt und SHA-256 geprüft. Details und Prüfsummen: [VALIDATION.md](VALIDATION.md).

Dies sind Softwareprüfungen. Keine simulierten Controller wurden als echte Hardwaremessung ausgegeben.

## Offen und konkret blockiert

1. **Alle zehn Hardware-Abnahmepunkte sind NICHT GETESTET.** Hier sind kein reales iPhone, keine Click-V2-Controller und kein D100 angeschlossen. iOS 27, zwei gleichzeitige Verbindungen, Hintergrundverhalten und 60-Minuten-Fahrt müssen am Gerät geprüft werden. Anleitung: [TEST_PLAN.md](TEST_PLAN.md).
2. **Separate Apple-Signierung fehlt.** Vorhandene Zertifikat-/Passwortwerte und ein nicht abgelaufenes Ad-hoc-Profil wurden erkannt. Das Profil passt nicht zu `de.p1337.ClickBridge`. Es wurde keine signierte oder installierbare zweite IPA erzeugt.
3. **Vollständiger Incyclist-Nativbuild noch nicht bestanden.** Der erste Lauf fand einen TypeScript-Fehler; dieser ist korrigiert. Folgelauf `40022206781` wurde nach ungefähr 20 Minuten von einem weiteren PR-Ereignis abgebrochen. Ein Abbruch ist kein bestandener Build.
4. Der zusätzliche kleine Brücken-Compilecheck fand zunächst einen fehlenden echten React-Native-Header im Prüfharness (`RCTDeprecation.h`). Die Header-Aufbereitung ist korrigiert; die tatsächliche Swift-/ObjC-Brücke muss anschließend ohne Ersatzdeklarationen kompilieren.
5. Die Workflows werden auf Branch-Push statt zusätzlicher PR-Auslösung umgestellt, damit reine Dokumentations-Updates keine laufenden Nativbuilds erneut abbrechen.

## Nächste konkrete Arbeit

CI-Korrekturen sichern; Ergebnisse des schnellen Brücken-Compilechecks auswerten; Protokoll des abgebrochenen Vollbuilds herunterladen; vollständigen Incyclist-Build fertig prüfen; jeden neuen Compilerfehler beheben und diesen Stand aktualisieren. Danach PR-Beschreibung und VALIDATION.md mit belegten Ergebnissen abgleichen.

Kein Live-Schalten, keine D100-Koexistenz und keine Verkaufsreife werden aus diesen Softwareprüfungen abgeleitet. Dafür gelten weiterhin alle Hardwarekriterien des Auftrags.
