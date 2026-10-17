# Werkbeleg — native Handwerker-App, Pilot 1.0.0

Arbeitsname, keine Markenfreigabe. Eigenständige Implementierung, keine Übernahme von PlanRadar-Code, Bildern oder Texten. Zielgruppe: kleine Betriebe mit bis zu 20 Personen. Weiß/Schwarz, Orange für Aktionen, Gelb für Hinweise.

## Diese Version kann

- Kunden mit Kontaktdaten und Adresse anlegen und bearbeiten.
- Aufträge mit Kunde, Baustellenadresse, zuständiger Person und Erledigt-Status anlegen und bearbeiten.
- Arbeitsberichte mit Text, bis zu zwölf optimierten JPEG-Fotos, einer bis zu zweiminütigen Sprachaufnahme und optionalem GPS-Schnappschuss erstellen.
- Sprachaufnahme über Apples Speech API transkribieren; Verfügbarkeit ist sprach-/geräte-/netzabhängig. Text bleibt korrigierbar. Die API kann Apple-Server verwenden; UI informiert vor der Nutzung.
- Fotozeit bei In-App-Kamera und Importzeit bei importierten Fotos unterscheiden. Keine behauptete EXIF- oder Manipulationsprüfung. Bilder werden auf maximal 1800 px verkleinert; Originaldateien werden nicht archiviert.
- Mehrseitige PDFs mit Firmenname, Kunden-/Auftragsbezug, Text, Fotos, Zeit und optionalem GPS sowie manuell eingetragenem Wetter erstellen und über das Teilen-Menü versenden/speichern.
- Vollständige JSON-Sicherungen inklusive Foto-/Audiodaten exportieren und nach Bestätigung wiederherstellen. In Dateien erreichbare Cloudanbieter können als Speicherziel dienen. Keine automatische iCloud-Datenbanksynchronisation.
- DE/EN/PL für wesentliche Bedienabläufe. Einige technische Diagnose-/Fehlermeldungen sind noch Deutsch; die vollständige Sprachprüfung steht aus.
- Einen optionalen eigenen HTTPS-Teamserver ansprechen. Token im iOS-Schlüsselbund; Server erzwingt Lese-/Schreibrollen und maximal 20 benannte Zugänge. Manueller Abgleich des gemeinsamen Datenstands. Konflikte blockieren Upload, statt fremde Änderungen still zu überschreiben.

## Noch nicht aktiv / Produktionsgrenzen

Kein Server wurde bereitgestellt oder mit echten Nutzern verbunden. Teamfähigkeit wurde gegen lokale synthetische API-Tests geprüft, nicht als 20-Personen-Produktivbetrieb. Versionierte Gesamtsicherung bis 30 MiB ist ein Pilotprotokoll, kein skalierbarer Foto-Cloudspeicher. Kein automatischer Konfliktabgleich, keine Projektberechtigungen, kein Administrator-Frontend, keine automatische Hintergrundsynchronisation und keine Einladungs-E-Mails. Für dauerhaften Betrieb müssen Medien getrennt gespeichert und differenzielle Synchronisation eingeführt werden.

Wetter ist manuell. WeatherKit benötigt eine neu konfigurierte App-ID/Capability und ein passendes Provisioningprofil. Für diesen Test wird das bestehende Profil unverändert verwendet. Keine erdachten Wetterdaten.

Kein manipulationssicherer oder qualifiziert signierter Nachweis, keine rechtliche Beweisgarantie, keine Unterschriftenfunktion. Kein Rechnungssystem, keine Plan-/Mängelverwaltung und keine vollständige Handwerker-ERP.

Pilot ohne Bezahlung. 9,99 €/Monat ist ein Preisvorschlag, kein eingerichtetes Abo. Ob das pro Betrieb für 20 Personen wirtschaftlich tragfähig ist, muss mit Speicherbedarf und Support gemessen werden. Keine unbegrenzte Hosting-/KI-Zusage. StoreKit, Datenschutzunterlagen, Store-Listing und Abrechnung sind vor Veröffentlichung separat einzurichten.

## Installation und Technik

SwiftUI, iOS 17+, keine Fremdpakete. `Werkbeleg/Model.swift` enthält das Foundation-Datenmodell; `Store.swift` Speicherung/Teamclient/Keychain; `Capture.swift` Kamera, Aufnahme, GPS, PDF; `App.swift` UI.

Technischer Bundle-Identifier bleibt für Roberts bestehendes Testprofil `de.p1337.LoRaLab`, Target/Scheme `LoRaLab`. Sichtbarer Name und Icon sind Werkbeleg. Installation ersetzt deshalb die alte LoRa-App. Die ursprünglichen LoRa-Quellen bleiben in `Sources/` und im Git-Verlauf erhalten, werden nicht mehr in das App-Target kompiliert. Das LoRa-Forschungsprojekt bleibt gestoppt.

Pipeline `.github/workflows/native-lora-ipa.yml`: Server-Tests → Foundation-Tests → nativer iOS-Simulator mit synthetischem Persistenz-/Backup-/PDF-Test → Apple-Distribution-AdHoc-Signierung → Signaturprüfung → bestehende HTTPS-Installationsseite. Dateiname der IPA bleibt aus Kompatibilitätsgründen `LoRaLab-Apple-signed.ipa`. Kamera/Mikrofon/GPS-Berechtigungen müssen auf einem echten iPhone getestet werden; Simulator-Smoke beweist diese nicht.

## Teamserver auf eigenem NAS/Server

Python 3.11+, keine Zusatzpakete:

```sh
cd native-lora-ios/team-server
python3 server.py --database /private-data/werkbeleg.sqlite3 --add-member Robert --role editor
python3 server.py --database /private-data/werkbeleg.sqlite3 --add-member Office --role reader
python3 server.py --database /private-data/werkbeleg.sqlite3 --port 8787
```

Bei `--add-member` wird einmal der Token ausgegeben. Privat übertragen, nie committen. Erneutes Anlegen desselben Namens rotiert den Token; `--revoke-member NAME` entzieht Zugriff. Jeder Mitarbeiter braucht einen eigenen Token. Rollen sind betriebsweit, nicht projektbezogen. Eine Datenbank pro Betrieb, keine öffentlich registrierbaren Konten.

Server bindet nur `127.0.0.1`. Reverse Proxy mit gültigem HTTPS-Zertifikat, Bodylimit 30 MiB, Rate-Limit und abgesicherten Dateirechten erforderlich. Proxy muss `/workspace` unverändert weiterreichen. App akzeptiert nur HTTPS. Betreiber übernimmt Hosting, Benutzerverwaltung, Datenschutz und SQLite-Backups. SQLite per Backup-API sichern, nicht während Schreibzugriffen blind die DB-Datei ohne WAL kopieren. Keine automatische Bereitschaft für Internet-Produktivbetrieb behaupten.

In Büro: HTTPS-Basis-URL und persönlichen Token eintragen, sicher speichern, synchronisieren. Auf einem leeren Server darf genau ein Startgerät den ersten Datenstand hochladen. Weitere Geräte zuerst den Teamstand laden. Bei Konflikt lokale Sicherung exportieren und anschließend Teamstand laden; gewünschte lokale Änderungen anschließend übertragen. Der lokale Stand wird dabei ersetzt, nicht zusammengeführt.

Tests: `python3 -m unittest discover -s native-lora-ios/team-server -p 'test_*.py' -v`. Native Kompilierung/Simulator auf dem GitHub-macOS-Runner; Linux kann das iOS-Binary nicht bauen.

## Nächste Produktstufe

1. Echtes iPhone: Kunden→Auftrag→Foto/Sprachaufnahme→Textprüfung→PDF→Cloud-Sicherung durchlaufen; auch verweigerte Berechtigungen und Flugmodus.
2. Eigenen HTTPS-Teamserver einrichten; zwei echte Geräte mit separaten Tokens und absichtlichem Versionskonflikt prüfen.
3. Für 20 Personen: Medien-Objektspeicher, Änderungen pro Datensatz, Konfliktauflösung, Rollen-/Einladungsoberfläche und strukturierte Berichtsvorlagen ergänzen.
4. WeatherKit mit korrekter Attribution, Sprachprüfung DE/EN/PL, Datenschutz und Bezahlmodell erst danach aktivieren.
