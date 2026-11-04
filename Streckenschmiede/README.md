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
- Signierte IPA und OTA-Store-Veröffentlichung
- GPS-Aufzeichnung bei gesperrtem Display / Background-Mode
- Persistente Fahrtenbibliothek
- FTMS-Verbindung und Leistung/Kadenz
- Zwift Click V2 Tastenprotokoll und virtuelle Schaltung
- RLV-Videoimport, automatische Osmo-/Fitmeter-Synchronisierung
- Training/ERG, Apple-TV-App, Apple Look Around

## Build
Workflow: .github/workflows/streckenschmiede-ios.yml
Der Workflow erzeugt derzeit nur nicht signierte Test-Builds. Apple-Code-Signing muss aus der existierenden Store-Infrastruktur übernommen werden. Ein erfolgreicher Build ist noch nicht verifiziert.
