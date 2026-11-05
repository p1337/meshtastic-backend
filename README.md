# Streckenschmiede

Native Fahrrad-App für iPhone, später optional tvOS. Kostenlos nutzbare Lösungen, keine Abos.

Verbindlicher Gesamtumfang und Abnahmestatus: [TODO.md](TODO.md) · Technische Zielarchitektur: [Streckenschmiede/ARCHITECTURE.md](Streckenschmiede/ARCHITECTURE.md)

## App (iOS 17+)
**Exakt zwei Hauptreiter:**
- **Aufzeichnung:** bildschirmfüllendes Karten-Cockpit mit Positionspfeil im
  unteren Drittel und großem Vorausblick; Live-Position läuft bei geöffneter
  App dauerhaft, während Trackpunkte erst nach Start geschrieben werden;
  eine breite orange Haupttaste „Aufzeichnung starten“ beginnt die Speicherung;
  Puls, Kadenz, Leistung und Sensorakku stehen kompakt im oberen Cockpit;
  84-Punkte-Kartensteuerung mit Minus links, Zentrieren mittig und Plus rechts;
  Ebenenknopf rechts oben für Apple Karte, Satellit, Hybrid, Online-OSM und
  die offene Fahrradkarte CyclOSM;
  erster Zielplaner mit Adress-/POI-Suche, Apple-Fahrradrouten und Alternativen;
  einstellbare GPS-Auto-Pause mit Verzögerung, Hysterese und sicherem Vorrang
  der manuellen Pause;
  GPS-Fahrt mit Pause/Fortsetzen, atomarer Notfall-Wiederherstellung, Distanz
  und GPX-Export; GPX-Import und Kartenansicht über Apple MapKit
- **Indoor-Training:** gleichzeitige BLE-Sensorverbindungen mit Puls, Tempo,
  Kadenz, Leistung, FTMS-Livewerten und Akku sowie erste begrenzte
  FTMS-Steuerung für D100-kompatible Trainer mit ERG, Widerstand, Steigung,
  Pause und Not-Stopp

Einstellungen sind über das Zahnradsymbol erreichbar. Design: dunkel, orangefarbene Akzente. Der derzeitige Build ist nur ein Grundprototyp. Das verbindliche Ziel umfasst ein modernes Fahrt-Cockpit, Live-Navigation mit Radweg-/Straßenprofilen und einstellbaren Zoomstufen, OSM-Option, Apple Watch/HealthKit/Apple Fitness, mehrere gleichzeitige Fahrradsensoren, D100/FTMS, Click V2 und die dokumentierten Historien-/Analysefunktionen. Diese Punkte sind in [TODO.md](TODO.md) einzeln aufgeführt und überwiegend **noch nicht implementiert**.

## Build und OTA-Installation

Quellcode: [Streckenschmiede/](Streckenschmiede/) · CI: [.github/workflows/streckenschmiede-ios.yml](.github/workflows/streckenschmiede-ios.yml)

Jeder Push auf `streckenschmiede-ios` mit App-/Workflow-Änderungen startet den macOS-Build. Der Workflow:

1. Prüft Swift-Syntax, generiert das Xcode-Projekt und kompiliert die unsignierte iPhone-App.
2. Verwendet die bereits bewährte Signierumgebung `apple-signing` und deren drei bestehenden Environment-Secrets. Team-ID und Bundle-ID werden aus dem vorhandenen Profil gelesen; Streckenschmiede ersetzt dadurch die frühere Test-App auf den registrierten Geräten.
3. Importiert dieselbe Apple-Distribution-Identität in einen temporären Keychain, archiviert und exportiert eine signierte IPA.
4. Validiert Bundle-ID, Profil, Ablaufdatum und die tatsächliche Apple-Code-Signatur mit [package_release.py](Streckenschmiede/scripts/package_release.py).
5. Generiert `index.html`, `Streckenschmiede.ipa`, `manifest.plist`, `release.json`; veröffentlicht das Paket mit GitHub Pages **nur nach erfolgreicher Signaturprüfung**.

Der Store soll unter [p1337.github.io/meshtastic-backend](https://p1337.github.io/meshtastic-backend/) erreichbar sein. Die Datei `index.html` im Branch allein veröffentlicht **keine** App.

### Bestehende Environment-Secrets

- `IOS_DISTRIBUTION_P12_BASE64`: Base64-kodiertes Apple-Distribution-P12
- `IOS_P12_PASSWORD`: Passwort des P12
- `IOS_ADHOC_PROFILE_BASE64`: Base64-kodiertes bestehendes Ad-hoc-Profil

Secretwerte werden nie ausgegeben. Team, Profil-UUID, Zertifikatsbindung und die konkrete Bundle-ID werden im Runner aus dem Profil validiert. Die IPA wird nur auf den dort registrierten iPhone-UDIDs installiert. GitHub Pages bleibt auf **GitHub Actions als Build-/Deploymentquelle** eingestellt.

Historische Referenz: Die identische Signierumgebung und dieselben drei Secret-Namen haben Werkbeleg und LoRaLab mehrfach erfolgreich signiert und per Pages veröffentlicht. Ein Streckenschmiede-Release gilt trotzdem erst nach erfolgreichem aktuellem Workflow, Signaturprüfung und Abruf der veröffentlichten OTA-Dateien als fertig.

## Schutz bestehender Dateien

Keine fremden oder historischen Dateien löschen. Keine Secrets im Repository ablegen. Die Release-Pipeline überschreibt die öffentliche Webseite nur, wenn eine gültige signierte Streckenschmiede-IPA vorliegt.
