# Streckenschmiede

Native Fahrrad-App für iPhone, später optional tvOS. Kostenlos nutzbare Lösungen, keine Abos.

## App (iOS 17+)
**Exakt zwei Hauptreiter:**
- **Aufzeichnung:** GPS-Fahrt mit Distanz, GPX-Export; GPX-Import und Kartenansicht über Apple MapKit (mit Start-/Ziel-Markierung und automatischem Kartenausschnitt)
- **Indoor-Training:** BLE-Gerätesuche für Van Rysel D100, Zwift Click V2 und weitere Geräte

Einstellungen sind über das Zahnradsymbol erreichbar. Design: dunkel, orangefarbene Akzente. FTMS-Steuerung, virtuelle Gänge, RLV, NAS-Videos, FIT/Health, Video-Synchronisation und tvOS sind **noch nicht** implementiert.

## Build und OTA-Installation

Quellcode: [Streckenschmiede/](Streckenschmiede/) · CI: [.github/workflows/streckenschmiede-ios.yml](.github/workflows/streckenschmiede-ios.yml)

Jeder Push auf `streckenschmiede-ios` mit App-/Workflow-Änderungen startet den macOS-Build. Der Workflow:

1. Prüft Swift-Syntax, generiert das Xcode-Projekt und kompiliert die unsignierte iPhone-App.
2. Prüft vorhandene GitHub-Actions-Secrets und verlangt ein **eigenes** Ad-hoc-/Enterprise-Profil für `de.p1337.Streckenschmiede`. Ein Werkbeleg-Profil wird ausdrücklich abgelehnt.
3. Importiert das Signierungszertifikat in einen temporären Keychain, archiviert und exportiert eine signierte IPA.
4. Validiert Bundle-ID, Profil, Ablaufdatum und die tatsächliche Apple-Code-Signatur mit [package_release.py](Streckenschmiede/scripts/package_release.py).
5. Generiert `index.html`, `Streckenschmiede.ipa`, `manifest.plist`, `release.json`; veröffentlicht das Paket mit GitHub Pages **nur nach erfolgreicher Signaturprüfung**.

Der Store soll unter [p1337.github.io/meshtastic-backend](https://p1337.github.io/meshtastic-backend/) erreichbar sein. Die Datei `index.html` im Branch allein veröffentlicht **keine** App.

### Erforderliche Repository-Secrets

- `IOS_CERTIFICATE_BASE64`: Base64-kodiertes iOS-Verteilungszertifikat als P12
- `IOS_CERTIFICATE_PASSWORD`: Passwort des P12
- `IOS_PROVISIONING_PROFILE_BASE64`: Base64-kodiertes Ad-hoc-/Enterprise-Profil **für Streckenschmiede**
- `IOS_TEAM_ID`: Apple-Developer-Team-ID

Die IPA wird nur auf registrierten iPhone-UDIDs (Ad hoc) beziehungsweise bei gültiger Enterprise-Verteilung installiert. Zusätzlich muss GitHub Pages auf **GitHub Actions als Build-/Deploymentquelle** eingestellt sein, damit `actions/deploy-pages` die alte Webseite ersetzen kann.

**Status:** Commit und Quellcode sind auf GitHub verifiziert. Ein erfolgreicher Xcode-Build, gültige Signierung und öffentliche Installation konnten bisher **nicht** verifiziert werden. Die vorhandene Werkbeleg-Seite ist nicht durch bloße Quellcode-Commits ersetzt.

## Schutz bestehender Dateien

Keine fremden oder historischen Dateien löschen. Keine Secrets im Repository ablegen. Die Release-Pipeline überschreibt die öffentliche Webseite nur, wenn eine gültige signierte Streckenschmiede-IPA vorliegt.
