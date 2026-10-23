# ClickBridge iOS

Native SwiftUI-App und wiederverwendbares Swift Package für zwei Zwift Click V2.

**Entwicklungsstand: BLE-Prototyp. Keine nachgewiesene Schaltung der unveränderten Incyclist-App auf demselben iPhone. Kein Verkaufsrelease.**

Die App sucht Controller, verwaltet zwei unabhängige BLE-Sitzungen, ordnet links/rechts dauerhaft zu und protokolliert GATT, Tastencodes, Firmware und Batterie. Ganglogik und ein konkreter eingebetteter Incyclist-Adapter sind getrennt implementiert. Es gibt keinen parallelen Trainerzugriff.

## Bauen

macOS mit Xcode 16+ und Python 3, keine externen Swift-Abhängigkeiten:

```sh
cd clickbridge-ios
swift test
python3 scripts/generate_project.py
xcodebuild -project ClickBridge.xcodeproj -scheme ClickBridge -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Projektgenerierung benötigt weder Homebrew noch XcodeGen. `scripts/test-simulator.sh` baut und startet die tatsächliche App im Simulator und exportiert einen Screenshot; dieser ist kein BLE-Hardwaretest. GitHub Actions baut auch eine unsignierte Geräte-IPA. Eine zweite, separat installierbare App benötigt ein zu `de.p1337.ClickBridge` passendes Provisioning-Profil.

## Geräteprüfung

App öffnen, Bluetooth erlauben, beide Clicks aufwecken, „Suchen“ wählen. Geräte anhand der Herstellerdaten oder durch einzelne Tastentests zuordnen. Bei gleichen Namen die angezeigte lokale Kennung verwenden. Nach Handshake je Seite die Schaltfläche drücken und Diagnose exportieren. Der Standalone-Modus zeigt „Keine Incyclist-Verbindung“ und bestätigt keine Gänge.

Die Incyclist-Integration läuft als eingebettetes Modul in einer geänderten Incyclist-App. Anleitung, Patch und automatische Patch-Prüfung: `integrations/incyclist/` und `docs/INCYCLIST_INTEGRATION.md`. Die unveränderte App-Store-App erhält dadurch keine neue Schnittstelle.

## Dokumentation

- [Aktueller, fortsetzbarer Arbeitsstand](docs/CHECKPOINT.md)
- [Machbarkeit](docs/FEASIBILITY.md)
- [Architektur](docs/ARCHITECTURE.md)
- [BLE-Protokoll](docs/BLE_PROTOCOL.md)
- [Testplan und Hardwareabnahme](docs/TEST_PLAN.md)
- [Kompatibilität](docs/COMPATIBILITY.md)
- [Signierung](docs/SIGNING.md)
- [Veröffentlichung und Lizenzen](docs/COMMERCIALIZATION.md)
- [Tatsächliche Testergebnisse](docs/VALIDATION.md)

Kein Konto, kein Netzwerkdienst, kein Abonnement, keine Werbung. Proprietäre BikeControl-/GPL-Codebestandteile sind nicht enthalten. MIT-Protokollreferenzen werden in `THIRD_PARTY_NOTICES.md` genannt. Zwift und Incyclist sind Marken ihrer jeweiligen Inhaber; dieses Projekt ist unabhängig.
