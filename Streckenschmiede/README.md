# Streckenschmiede – Entwicklungsstand

Verbindlicher Gesamtumfang und Status: [../TODO.md](../TODO.md) · Zielarchitektur und dauerhafte technische Entscheidungen: [ARCHITECTURE.md](ARCHITECTURE.md) · DJI Action 5 Pro Video-/GPS-Sync: [CAMERA_SYNC.md](CAMERA_SYNC.md)

## Ziel
Native iPhone- und später Apple-TV-App für Fahrradaufzeichnung und Indoor-Training, ohne laufendes Abonnement.

## Aktueller iOS-Grundprototyp
- Zwei Hauptreiter: Aufzeichnung und Indoor-Training
- GPS-Aufzeichnung mit Distanz und GPX-Export (nur Vordergrund)
- Erstes modernes Fahrt-Cockpit mit Live-Karte, gefahrenem Track, GPS-Geschwindigkeit, Zeit, Höhe, Auf-/Abstieg und gespeichertem Karten-Zoom
- GPX-Import aus Dateien und Apple-MapKit-Streckenkarte
- BLE-Scan für Van Rysel D100 und Zwift Click V2
- Dunkles Design mit orangefarbenem Akzent

## Noch nicht implementiert
- Vollständig anpassbares Fahrt-Cockpit, alle Sensorwerte und getrennte Zoom-Presets; die erste GPS-/Live-Karten-Ausbaustufe ist vorhanden
- Zielnavigation mit Radweg-/Straßenprofilen, Apple-Fahrradrouting und OSM/Valhalla
- GPS-Aufzeichnung bei gesperrtem Display / Background-Mode
- Persistente Fahrtenbibliothek
- Apple-Watch-Begleit-App, HealthKit-Workout/-Route und Übergabe an Apple Fitness
- Standardisierte BLE-Dienste für Puls, Geschwindigkeit/Kadenz, Leistung, FTMS und mehrere gleichzeitige Sensoren
- FTMS-Verbindung und Leistung/Kadenz
- Zwift Click V2 Tastenprotokoll und virtuelle Schaltung
- DJI Osmo Action 5 Pro Videoimport, QR-/Timecode-/FIT-Synchronisierung und optionale Kamerasteuerung; das technische Konzept ist dokumentiert
- Training/ERG, Apple-TV-App, Apple Look Around

## Build und Veröffentlichung
Workflow: `.github/workflows/streckenschmiede-ios.yml`

Die Pipeline nutzt die vorhandene GitHub-Environment `apple-signing` mit `IOS_DISTRIBUTION_P12_BASE64`, `IOS_P12_PASSWORD` und `IOS_ADHOC_PROFILE_BASE64`. Bundle-ID und Team-ID werden aus dem bestehenden Profil übernommen; dadurch ersetzt die App die frühere Werkbeleg-/LoRaLab-Test-App. Nach Compiler-, Profil- und Signaturprüfung werden IPA, Manifest und Store gemeinsam über GitHub Pages veröffentlicht. Ein fehlgeschlagener Build überschreibt den letzten funktionierenden Store nicht.
