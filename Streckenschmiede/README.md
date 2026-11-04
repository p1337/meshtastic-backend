# Streckenschmiede – Entwicklungsstand

Verbindlicher Gesamtumfang und Status: [../TODO.md](../TODO.md) · Zielarchitektur und dauerhafte technische Entscheidungen: [ARCHITECTURE.md](ARCHITECTURE.md) · [Routen/Karten/Integrationen](ROUTES_MAPS_INTEGRATIONS.md) · [RLV-Kompatibilität](RLV_COMPATIBILITY.md) · [eigene Grafiken](ARTWORK.md) · DJI Action 5 Pro Video-/GPS-Sync: [CAMERA_SYNC.md](CAMERA_SYNC.md)

## Ziel
Native iPhone- und später Apple-TV-App für Fahrradaufzeichnung und Indoor-Training, ohne laufendes Abonnement.

## Aktueller iOS-Grundprototyp
- Zwei Hauptreiter: Aufzeichnung und Indoor-Training
- GPS-Aufzeichnung mit Distanz, GPX-Export, manueller Pause/Fortsetzung,
  getrennter Gesamt-/Fahrt-/Pausenzeit und atomarem Wiederherstellungsstand
- Hintergrund-Ortung ist für eine laufende Fahrt konfiguriert; die echte
  Sperrbildschirm- und Langzeittestfahrt steht noch aus
- Erstes modernes Fahrt-Cockpit mit Live-Karte, gefahrenem Track, GPS-Geschwindigkeit, Zeit, Höhe, Auf-/Abstieg und gespeichertem Karten-Zoom
- Erster DJI-Action-5-Pro-Sync-Bildschirm mit Start-/Checkpoint-/End-QR, Fahrt-ID, UTC, Fahrtzeit, Prüfsumme und optionaler GPS-Position
- GPX-Import aus Dateien sowie Empfang über „Öffnen mit“/Teilen aus WhatsApp, Komoot und anderen Apps
- Live-Karte mit geplanter GPX-Linie, Fahrtrichtung/Vorausblick, großem Zentrieren-Knopf und Handschuh-Zoompresets
- Eigenes orange/schwarzes Corporate-Zeichen mit mittigem Rennrad-Vorderrad,
  steiler Gabel und angeschnittenem Rennlenker; separates Routenmotiv als Hero-Asset
- Mehrere gleichzeitige BLE-Verbindungen mit State Restoration sowie Live-Parsern
  für Heart Rate, Cycling Speed/Cadence, Cycling Power, FTMS Indoor Bike,
  Battery und Device Information; echte Sensorabnahme steht noch aus
- Dunkles Design mit orangefarbenem Akzent

## Noch nicht implementiert
- Vollständig anpassbares Fahrt-Cockpit, alle Sensorwerte und getrennte Zoom-Presets; die erste GPS-/Live-Karten-Ausbaustufe ist vorhanden
- Zielnavigation mit Radweg-/Straßenprofilen, Apple-Fahrradrouting und OSM/Valhalla
- Reale Abnahme der GPS-Aufzeichnung bei gesperrtem Display und nach einem
  erzwungenen App-/Telefonneustart
- Persistente Fahrtenbibliothek
- Apple-Watch-Begleit-App, HealthKit-Workout/-Route und Übergabe an Apple Fitness
- Vollständige Hardwareabnahme, dauerhafte Fahrradzuordnung und Quellenpriorität
  für standardisierte BLE-Sensoren
- FTMS-Steuerung für Widerstand, Steigung und ERG; FTMS-Livewerte sind vorhanden
- Zwift Click V2 Tastenprotokoll und virtuelle Schaltung
- DJI Osmo Action 5 Pro Videoimport, QR-/Timecode-/FIT-Synchronisierung und optionale Kamerasteuerung; das technische Konzept ist dokumentiert
- Offline-Vektorkarten/OSM-Fahrradstil, Komoot-Kontosync und freiwillige Gruppenpositionen; Grenzen und Providerentscheidung sind dokumentiert
- Training/ERG, Apple-TV-App, Apple Look Around

## Build und Veröffentlichung
Workflow: `.github/workflows/streckenschmiede-ios.yml`

Die Pipeline nutzt die vorhandene GitHub-Environment `apple-signing` mit `IOS_DISTRIBUTION_P12_BASE64`, `IOS_P12_PASSWORD` und `IOS_ADHOC_PROFILE_BASE64`. Bundle-ID und Team-ID werden aus dem bestehenden Profil übernommen; dadurch ersetzt die App die frühere Werkbeleg-/LoRaLab-Test-App. Nach Compiler-, Profil- und Signaturprüfung werden IPA, Manifest und Store gemeinsam über GitHub Pages veröffentlicht. Ein fehlgeschlagener Build überschreibt den letzten funktionierenden Store nicht.
