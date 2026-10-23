# Tatsächlich ausgeführte Prüfung

Stand: 23.10.2026. Keine physischen Bluetoothgeräte an der Ausführungsumgebung.

## Bestandener eigenständiger App-Build

Commit `b805d9dbf09f6e5d1ef5e5d24c9a7e895dd805a0`, [GitHub Actions 40019804775](https://github.com/p1337/meshtastic-backend/actions/runs/40019804775), Ergebnis **success**.

- Apple Swift 6.1.2, Xcode 16.4 auf macOS-15-Runner.
- 20 XCTest-Methoden erfolgreich über `swift test --parallel`. Die zusätzliche Swift-Testing-Zeile „0 tests“ betrifft die separat nicht verwendete Swift-Testing-Bibliothek, nicht die 20 ausgeführten XCTest-Methoden.
- Projektgenerator reproduzierbar; Info-/Privacy-/Xcode-Property-Lists validiert.
- SwiftUI/CoreBluetooth-App gebaut und tatsächlich auf einem iPhone-16-Pro-Simulator mit iOS 18.5 (22F77) gestartet.
- Smoke-JSON: `hardwareTested=false`, `integrationAvailable=false`, `liveGear=null`, `trainerCommandsSent=0`, `gearCount=24`.
- Simulator-Screenshot heruntergeladen und visuell geprüft: alle vier Tabs sichtbar; Dashboard zeigt fehlende Integration und deaktivierte Gangtasten. Keine erfundenen Geräte/Batterien/Gänge.
- arm64-Geräte-App gebaut; IPA-Inhalt unabhängig gelesen: eigene Bundle-ID `de.p1337.ClickBridge`, MinimumOSVersion 18.0, kein eingebettetes Provisioning-Profil. **Unsigniert, ohne erneute Signierung nicht installierbar.**

Artefakt-ID `12530238545`. Heruntergeladenes ZIP stimmt mit dem GitHub-Digest überein:
`00a1f0e5c0b9db6087aba5ea826fe332813862dd1e641127769140ae135d6498`.

SHA-256 der enthaltenen `ClickBridge-UNSIGNED.ipa`:
`9e310552c2c9c39739e72d7f62b5079c5bc1a79c2cd8d7248a7e95cdfea879c3`.

Ein anfänglicher Buildfehler im Dateischutz-Parameternamen wurde behoben. Danach erfolgreicher Build. Im macOS-Package-Lauf sichtbare ObjC-/MainActor-Kompatibilitätswarnungen werden im nachfolgenden Commit durch ausdrücklich main-queue-gebundene `@preconcurrency`-Conformances bereinigt; dieser nachfolgende Stand benötigt seinen eigenen grünen Lauf.

## Incyclist-Softwarepfad

Sieben Node-Tests lokal tatsächlich bestanden: beide Richtungen, vorhandener interner `sendUpdate`-Aufruf ohne Steigungsüberschreibung, doppelte/alte/ungültige Ereignisse, Sitzungswechsel, Modus-/Adapter-/Busy-Prüfung, Serialisierung/Transportfehler und Queuegrenzen.

Installer auf den exakt geprüften Incyclist-Commit angewendet; lokaler Fork-Commit `962aced` erstellt. Eigenständiges Package, native Brücke, Xcode-Paketverweise, iOS-18-Ziel und RidePage-Einrichtung sind enthalten. Vollständiger Mail-Patch mitgeliefert. Quell-Diff auf Whitespacefehler geprüft. Ein vollständiger nativer Incyclist-Build wird durch den separaten Workflow geprüft; bis zu dessen dokumentiertem Erfolg ist er **nicht bestanden**.

## Nicht getestete Punkte

Alle zehn Hardwareabnahmepunkte in TEST_PLAN.md: **NICHT GETESTET**. Ebenfalls nicht getestet: iOS 27 auf Roberts iPhone, zwei reale gleichzeitige BLE-Verbindungen, linker 60-Sekunden-/24-Stunden-Effekt, echte Widerstandsänderung, erhaltene Streckensimulation, 60-Minuten-Fahrt, physische Reconnects, Anruf, Sperrbildschirm und Systembeendigung.

Noch keine passende Apple-Signierung der zweiten App, kein App-Store-Release und kein Produktverkauf. Ein erfolgreicher Build ersetzt keinen dieser Nachweise.
