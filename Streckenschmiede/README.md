# Streckenschmiede – Entwicklungsstand

## Ziel
Native iPhone- und später Apple-TV-App für Fahrradaufzeichnung und Indoor-Training, ohne laufendes Abonnement.

## Erste iOS-Testversion
- Zwei Hauptreiter: Aufzeichnung und Indoor-Training
- GPS-Aufzeichnung mit Distanz und GPX-Export (nur Vordergrund)
- GPX-Import aus Dateien und Apple-MapKit-Streckenkarte
- BLE-Scan für Van Rysel D100 und Zwift Click V2
- Dunkles Design mit orangefarbenem Akzent

## Noch nicht implementiert
- GPS-Aufzeichnung bei gesperrtem Display / Background-Mode
- Persistente Fahrtenbibliothek
- FTMS-Verbindung und Leistung/Kadenz
- Zwift Click V2 Tastenprotokoll und virtuelle Schaltung
- RLV-Videoimport, automatische Osmo-/Fitmeter-Synchronisierung
- Training/ERG, Apple-TV-App, Apple Look Around

## Build und Veröffentlichung
Workflow: `.github/workflows/streckenschmiede-ios.yml`

Die Pipeline nutzt die vorhandene GitHub-Environment `apple-signing` mit `IOS_DISTRIBUTION_P12_BASE64`, `IOS_P12_PASSWORD` und `IOS_ADHOC_PROFILE_BASE64`. Bundle-ID und Team-ID werden aus dem bestehenden Profil übernommen; dadurch ersetzt die App die frühere Werkbeleg-/LoRaLab-Test-App. Nach Compiler-, Profil- und Signaturprüfung werden IPA, Manifest und Store gemeinsam über GitHub Pages veröffentlicht. Ein fehlgeschlagener Build überschreibt den letzten funktionierenden Store nicht.
