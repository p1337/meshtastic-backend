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

Ein anfänglicher Buildfehler im Dateischutz-Parameternamen wurde behoben. Danach erfolgreicher Build. Die ObjC-/MainActor-Kompatibilitätswarnungen sind im nachfolgenden Stand durch ausdrücklich main-queue-gebundene `@preconcurrency`-Conformances bereinigt.

## Erneut bestandener aktueller Softwarestand

Commit `321372f965cddf2bb31253f81fb8c9c4085f5d44`, [GitHub Actions 40022206773](https://github.com/p1337/meshtastic-backend/actions/runs/40022206773): **success**. Enthält die vollständige Dokumentation, den nativen Integrationsvorschlag, die Lizenzansicht und die korrigierten Actor-Conformances.

Erneut bestanden: 20 Swift-XCTest-Methoden, sieben Node-Routingtests, deterministische Projektgenerierung, echte Simulator-App mit Screenshot/Smoke-JSON sowie unsignierte Geräte-IPA. Das neue Beweisartefakt ist `12531337019`, ZIP-Digest `0e2be05b31ccdf9e36a8d703432705076cf0ed4bfcbb2a1b39c5cb12a75de034`.

Dieses ZIP erneut unabhängig heruntergeladen und den Digest abgeglichen. Die IPA enthält einen arm64-Mach-O sowie den Drittanbieter-Lizenzhinweis. SHA-256 der aktuellen unsignierten IPA: `3a3c24fe15a541894b8e5982600fc6f28b61d49fb01d25fb1c0a4042c6423a15`. Aktuelles Unit-Test-Log: 20 XCTest-Methoden, keine Swift-Quellcodewarnungen.

Der separate Signing-Audit bestätigt vorhandene Zertifikat-/Passwortwerte und ein gültiges Ad-hoc-Profil, aber `matchingProfile=false` für `de.p1337.ClickBridge`. Es wurde keine signierte zweite App erzeugt. Das ist ein tatsächlicher technischer Blocker für die vorhandene OTA-Installation.

## Incyclist-Softwarepfad

Sieben Node-Tests lokal tatsächlich bestanden: beide Richtungen, vorhandener interner `sendUpdate`-Aufruf ohne Steigungsüberschreibung, doppelte/alte/ungültige Ereignisse, Sitzungswechsel, Modus-/Adapter-/Busy-Prüfung, Serialisierung/Transportfehler und Queuegrenzen.

Installer auf den exakt geprüften Incyclist-Commit angewendet; aktueller lokaler Fork-Commit `fbaf403` erstellt. Eigenständiges Package, native Brücke, Xcode-Paketverweise, iOS-18-Ziel und RidePage-Einrichtung sind enthalten. Vollständiger Mail-Patch auf einem zweiten sauberen Worktree tatsächlich geprüft und angewendet; dort die sieben Routingtests ebenfalls bestanden. Quell-Diff auf Whitespacefehler geprüft. Ein vollständiger nativer Incyclist-Build wird durch den separaten Workflow geprüft; bis zu dessen dokumentiertem Erfolg ist er **nicht bestanden**.

Der erste Integrationslauf `40021687860` fand eine TypeScript-Deklarationsabweichung (`ICyclingMode` deklariert `getConfig()`, aber nicht `isSIM()`). Der Adapter verwendet jetzt die deklarierte Konfiguration. Es wurde keine Typprüfung unterdrückt und kein unsicherer Cast als Reparatur eingesetzt. Folgeprüfung: `40022206781`.

Dieser Folgelauf wurde durch eine zusätzliche PR-Auslösung abgebrochen. Das heruntergeladene Artefakt `12531209463` wurde unabhängig geprüft (ZIP-SHA-256 `67bdeda4751933a291a2d95440771d4fb7ef193df6bcd58ff39e34b1a05f2115`). Es belegt: sieben Routingtests bestanden, TypeScript-Prüfung ohne Fehler, CocoaPods mit 120 installierten Pods abgeschlossen; der native Build befand sich noch in der Kompilierung. Kein fertiges Incyclist-Binary daraus abgeleitet. Die drei Workflows verwenden ab `e4e4440` nur passende Branch-Pushes und manuelle Auslösung, damit reine Dokumentations-Updates keine erneuten PR-Builds starten.

## Tatsächlich bestandene native Brückenkompilierung

Commit `80342d06d825f2c1c437bfbf4c2ef4e9d15eec6a`, [GitHub Actions 40025744713](https://github.com/p1337/meshtastic-backend/actions/runs/40025744713), Job `120661364592`: **success**.

`check-react-bridge.sh` lädt die im geprüften Incyclist-Lockfile festgelegten React-Native-0.83.10-Header, prüft deren npm-SHA-512-Integrität, baut das echte ClickBridge-Swift-Package für arm64-iOS-Simulator und kompiliert die tatsächliche Swift-/Objective-C-Brücke gegen diese Header. Keine Mock-API oder erfundenen React-Deklarationen. Das anfängliche fehlende Header-Namespace sowie eine Kollision mit dem Standardheader `float.h` im Prüfharness sind behoben.

Dies prüft Syntax und Typen, **nicht** das vollständige Incyclist-Linking, die Modulregistrierung zur Laufzeit oder Hardware. Der vollständige neue Build `40025436038` wartet zum Zeitpunkt dieses Eintrags noch auf einen macOS-Runner und bleibt unbestanden.

Beweisartefakt der bestandenen Brückenprüfung: `12532118690`, ZIP-SHA-256 `c183513ab7c1a1b54ea128b319fd8b7cf65f59c2c71d591b688331837a23d691`.

## Erneute Prüfung des ausgelieferten Integrationspatches

Der aktuelle `mobile.patch` wurde zusätzlich auf einem neu angelegten, sauberen Worktree von `incyclist/mobile@1969e6442a9ae807b1f9ae0b9cd865400d7d6873` mit `git apply --check` geprüft und angewendet. Danach `git diff --check` und alle sieben Node-Routingtests erfolgreich. Alle 14 eingebetteten Core-/BLE-/Brücken-/Router-/Paket-/Lizenzdateien stimmen bytegenau mit dem aktuellen ClickBridge-Quellstand überein.

SHA-256 des geprüften Patches: `d6853e1b4b966138962fdc5b7253999715028ff44ca8f13ebfdb32c2f6678b75`.

## Abschließender erneuter App-Lauf

[Lauf 40025436023](https://github.com/p1337/meshtastic-backend/actions/runs/40025436023), Commit `e4e44400a46da17d6e3c8515e47ae4197c34d5af`: Softwarejob `120660320674` und Signing-Audit `120660320998` beide **success**. Alle Schritte einschließlich Swift-/Routingtests, Projektgenerierung, Simulatorstart, unsignierter Geräte-IPA und Artefakt-Upload erfolgreich. Der Lauf verwendet die korrigierte CI-Fehlerweitergabe (`set -euo pipefail`). Der Produktquellcode entspricht dem zuvor unabhängig heruntergeladenen und geprüften Stand; die spätere Header-Harness-Korrektur wurde separat in Lauf `40025744713` geprüft.

## Nicht getestete Punkte

Alle zehn Hardwareabnahmepunkte in TEST_PLAN.md: **NICHT GETESTET**. Ebenfalls nicht getestet: iOS 27 auf Roberts iPhone, zwei reale gleichzeitige BLE-Verbindungen, linker 60-Sekunden-/24-Stunden-Effekt, echte Widerstandsänderung, erhaltene Streckensimulation, 60-Minuten-Fahrt, physische Reconnects, Anruf, Sperrbildschirm und Systembeendigung.

Noch keine passende Apple-Signierung der zweiten App, kein App-Store-Release und kein Produktverkauf. Ein erfolgreicher Build ersetzt keinen dieser Nachweise.
