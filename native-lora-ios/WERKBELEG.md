# Werkbeleg — native Handwerker-App, Pilot 1.1.1

Arbeitsname, keine Markenfreigabe. Eigenständige Implementierung, keine Übernahme von PlanRadar-Code, Bildern oder Texten. Zielgruppe: kleine Betriebe mit bis zu 20 Personen. Weiß/Schwarz, Orange für Aktionen, Gelb für Hinweise.

## Diese Version kann

- Kunden mit Kontaktdaten und Adresse anlegen und bearbeiten.
- Aufträge mit Kunde, Baustellenadresse, zuständiger Person und Erledigt-Status anlegen und bearbeiten.
- Arbeitsberichte mit Text, bis zu zwölf optimierten JPEG-Fotos, einer bis zu zweiminütigen Sprachaufnahme und optionalem GPS-Schnappschuss erstellen.
- Sprachaufnahme über Apples Speech API transkribieren; Verfügbarkeit ist sprach-/geräte-/netzabhängig. Text bleibt korrigierbar. Seit 1.1.1 ausschließlich lokale Erkennung: Unterstützung wird geprüft und requiresOnDeviceRecognition gesetzt. Kein Netzwerk-Fallback; sonst nur Audioaufnahme/manueller Text.
- Fotozeit bei In-App-Kamera und Importzeit bei importierten Fotos unterscheiden. Keine behauptete EXIF- oder Manipulationsprüfung. Bilder werden auf maximal 1800 px verkleinert; Originaldateien werden nicht archiviert.
- Mehrseitige PDFs mit Firmenname, Kunden-/Auftragsbezug, Text, Fotos, Zeit und optionalem GPS sowie manuell eingetragenem Wetter erstellen und über das Teilen-Menü versenden/speichern.
- Vollständige JSON-Sicherungen inklusive Foto-/Audiodaten exportieren und nach Bestätigung wiederherstellen. In Dateien erreichbare Cloudanbieter können als Speicherziel dienen. Keine automatische iCloud-Datenbanksynchronisation.
- DE/EN/PL für wesentliche Bedienabläufe. Einige technische Diagnose-/Fehlermeldungen sind noch Deutsch; die vollständige Sprachprüfung steht aus.
- Einen optionalen eigenen HTTPS-Teamserver ansprechen. Token im iOS-Schlüsselbund; Server erzwingt Lese-/Schreibrollen und maximal 20 benannte Zugänge. Manueller Abgleich des gemeinsamen Datenstands. Konflikte blockieren Upload, statt fremde Änderungen still zu überschreiben.

## Noch nicht aktiv / Produktionsgrenzen

Kein Server wurde bereitgestellt oder mit echten Nutzern verbunden. Teamfähigkeit wurde gegen lokale synthetische API-Tests geprüft, nicht als 20-Personen-Produktivbetrieb. Versionierte Gesamtsicherung bis 30 MiB ist ein Pilotprotokoll, kein skalierbarer Foto-Cloudspeicher. Kein automatischer Konfliktabgleich, keine Projektberechtigungen, kein vollständiges Administrator-Portal, keine automatische Hintergrundsynchronisation der Berichte und kein automatischer E-Mail-Versand. Für dauerhaften Betrieb müssen Medien getrennt gespeichert und differenzielle Synchronisation eingeführt werden.

Wetter ist manuell. WeatherKit benötigt eine neu konfigurierte App-ID/Capability und ein passendes Provisioningprofil. Für diesen Test wird das bestehende Profil unverändert verwendet. Keine erdachten Wetterdaten.

Kein manipulationssicherer oder qualifiziert signierter Nachweis, keine rechtliche Beweisgarantie, keine Unterschriftenfunktion. Kein Rechnungssystem, keine Plan-/Mängelverwaltung und keine vollständige Handwerker-ERP.

Pilot ohne Bezahlung. Die festgelegten Monatspakete pro Betrieb sind: bis 5 Personen 9,99 €, bis 10 Personen 14,99 €, bis 20 Personen 19,99 €. Inhaber zählt mit. Das sind noch keine eingerichteten App-Store-Abos. Ob das pro Betrieb für 20 Personen wirtschaftlich tragfähig ist, muss mit Speicherbedarf und Support gemessen werden. Keine unbegrenzte Hosting-/KI-Zusage. StoreKit, Datenschutzunterlagen, Store-Listing und Abrechnung sind vor Veröffentlichung separat einzurichten.

## Installation und Technik

SwiftUI, iOS 17+, keine Fremdpakete. `Werkbeleg/Model.swift` enthält das Foundation-Datenmodell; `Store.swift` Speicherung/Teamclient/Keychain; `Capture.swift` Kamera, Aufnahme, GPS, PDF; `App.swift` UI; `Collaboration.swift` Projektchat, Teamverwaltung, Einladungen und Pakete.

Technischer Bundle-Identifier bleibt für Roberts bestehendes Testprofil `de.p1337.LoRaLab`, Target/Scheme `LoRaLab`. Sichtbarer Name und Icon sind Werkbeleg. Installation ersetzt deshalb die alte LoRa-App. Die ursprünglichen LoRa-Quellen bleiben in `Sources/` und im Git-Verlauf erhalten, werden nicht mehr in das App-Target kompiliert. Das LoRa-Forschungsprojekt bleibt gestoppt.

Pipeline `.github/workflows/native-lora-ipa.yml`: Server-Tests → Foundation-Tests → nativer iOS-Simulator mit synthetischem Persistenz-/Backup-/PDF-Test → Apple-Distribution-AdHoc-Signierung → Signaturprüfung → bestehende HTTPS-Installationsseite. Dateiname der IPA bleibt aus Kompatibilitätsgründen `LoRaLab-Apple-signed.ipa`. Kamera/Mikrofon/GPS-Berechtigungen müssen auf einem echten iPhone getestet werden; Simulator-Smoke beweist diese nicht.

## Teamserver auf eigenem NAS/Server

Python 3.11+, keine Zusatzpakete:

```sh
cd native-lora-ios/team-server
python3 server.py --database /private-data/werkbeleg.sqlite3 --plan 5 --add-member Robert --role admin
python3 server.py --database /private-data/werkbeleg.sqlite3 --add-member Office --role reader
python3 server.py --database /private-data/werkbeleg.sqlite3 --port 8787
```

Bei `--add-member` wird einmal der Token ausgegeben. Privat übertragen, nie committen. Erneutes Anlegen desselben Namens rotiert den Token; `--revoke-member NAME` entzieht Zugriff. Paketgröße mit `--plan 5`, `--plan 10` oder `--plan 20` beim Start setzen; dies ist eine Pilotkonfiguration, kein bezahlter Lizenznachweis. Jeder Mitarbeiter braucht einen eigenen Token. Rollen sind betriebsweit, nicht projektbezogen. Eine Datenbank pro Betrieb, keine öffentlich registrierbaren Konten.

Server bindet nur `127.0.0.1`. Reverse Proxy mit gültigem HTTPS-Zertifikat, Bodylimit 30 MiB, Rate-Limit und abgesicherten Dateirechten erforderlich. Proxy muss `/workspace` unverändert weiterreichen. App akzeptiert nur HTTPS. Betreiber übernimmt Hosting, Benutzerverwaltung, Datenschutz und SQLite-Backups. SQLite per Backup-API sichern, nicht während Schreibzugriffen blind die DB-Datei ohne WAL kopieren. Keine automatische Bereitschaft für Internet-Produktivbetrieb behaupten.

In Büro: HTTPS-Basis-URL und persönlichen Token eintragen, sicher speichern, synchronisieren. Auf einem leeren Server darf genau ein Startgerät den ersten Datenstand hochladen. Weitere Geräte zuerst den Teamstand laden. Bei Konflikt lokale Sicherung exportieren und anschließend Teamstand laden; gewünschte lokale Änderungen anschließend übertragen. Der lokale Stand wird dabei ersetzt, nicht zusammengeführt.

Tests: `python3 -m unittest discover -s native-lora-ios/team-server -p 'test_*.py' -v`. Native Kompilierung/Simulator auf dem GitHub-macOS-Runner; Linux kann das iOS-Binary nicht bauen.

## Nächste Produktstufe

1. Echtes iPhone: Kunden→Auftrag→Foto/Sprachaufnahme→Textprüfung→PDF→Cloud-Sicherung durchlaufen; auch verweigerte Berechtigungen und Flugmodus.
2. Eigenen HTTPS-Teamserver einrichten; zwei echte Geräte mit separaten Tokens und absichtlichem Versionskonflikt prüfen.
3. Für 20 Personen: Medien-Objektspeicher, Änderungen pro Datensatz, Konfliktauflösung, vollständiges Adminportal und strukturierte Berichtsvorlagen ergänzen.
4. WeatherKit mit korrekter Attribution, Sprachprüfung DE/EN/PL, Datenschutz und Bezahlmodell erst danach aktivieren.

## Erweiterung 1.1: Projekte, Kommunikation und Einladungen

Aufträge heißen in der Oberfläche jetzt Projekte. Jedes Projekt hat Berichte und einen separaten Textchat. Im geöffneten Chat werden Nachrichten alle zehn Sekunden abgerufen; kein Push und keine Hintergrundzustellung. Senden setzt einen erreichbaren Teamserver und Schreibrechte voraus. Ein lokal neu angelegtes Projekt wird vor der ersten Nachricht synchronisiert.

Chat-Nachrichten werden auf dem Server atomar separat gespeichert. Zwei Sender können gleichzeitig schreiben, ohne den kompletten Berichtsdatenstand zu ersetzen. Nachrichten-IDs machen Wiederholungen idempotent. Autor kommt vom angemeldeten Token und wird nicht aus einem frei gesetzten Nachrichtenfeld übernommen. Maximal 4.000 Zeichen je Nachricht und 10.000 Nachrichten insgesamt im Pilot. Reine Textnachrichten; Medien stehen im Arbeitsbericht. Workspace-Sicherungen enthalten die zuletzt abgerufenen Nachrichten; der Server-DB-Backup enthält alle.

In Büro → Team verwalten kann der Inhaber/Admin einen namentlichen Editor oder Leser einladen. Standardpaket: fünf Personen einschließlich Inhaber. Offene, nicht abgelaufene Einladungen reservieren je einen Platz. Codes gelten 48 Stunden, sind einmal verwendbar und werden nur gehasht gespeichert. Leser und normale Editoren können keine Einladungen erzeugen. Paketbegrenzungen werden am Server geprüft, nicht nur durch die App-Oberfläche.

Der Button ›Per WhatsApp einladen‹ öffnet den offiziellen wa.me-Teilenweg mit vorgefülltem Einladungstext. Empfänger und Versand bestätigt der Nutzer. Alternativ gibt es das iOS-Teilen-Menü. Kein automatischer WhatsApp-Versand und keine Business-API nötig. Primärquelle: https://faq.whatsapp.com/5913398998672934 .

Geteilt wird ein HTTPS-Link auf `join.html`. Der Einladungscode liegt im URL-Fragment und wird nicht an GitHub Pages übertragen. Die Seite enthält keine Analyse-/Drittanbieterskripte. Der Nutzer öffnet per Button den registrierten `werkbeleg://join`-Link; ohne App ist ein Installationslink vorhanden. Einladungsannahme fragt ausdrücklich nach dem Serverwechsel und dem Ersatz lokaler Daten. Vorher exportieren; eine automatische temporäre Sicherung ersetzt kein externes Backup.

Ein erreichbarer eigener HTTPS-Server wurde weiterhin nicht eingerichtet. Deshalb sind reale Einladungen und Kommunikation noch nicht zwischen echten Teilnehmern verifiziert. Das AdHoc-Testprofil enthält derzeit nur Roberts Gerät; weitere Tester brauchen registrierte Geräte oder später eine passende TestFlight-/App-Store-Verteilung. Keine Behauptung einer produktiven Teamfreischaltung allein durch eine Einladung.

Preise: 5 Personen 9,99 € / Monat; 10 Personen 14,99 € / Monat; 20 Personen 19,99 € / Monat, jeweils pro Betrieb inkl. Inhaber. Länderpreise/MwSt.-Darstellung und StoreKit-Abwicklung sind vor Verkauf zu konfigurieren. Kein Kaufbutton, keine aktive Belastung und keine automatische Abo-Freischaltung im Pilot.


## Datenregion-Vorgabe

Nutzer verlangt Geschäftsdaten in Europa; bevorzugte Region Frankfurt eu-central-1. Speicher, Datenbank, Audio und Backups müssen vor gehosteter Nutzung passend konfiguriert werden. Ein EU-Projekt bei Supabase garantiert laut Anbieter nicht automatisch EU-only-Verarbeitung von CDN/Support/Metadaten. Keine solche Garantie in der App ausgeben. Native 1.1.1 nutzt lokale Spracherkennung nur bei supportsOnDeviceRecognition=true und requiresOnDeviceRecognition=true; kein Audio-Upload zur Erkennung als Fallback. Geräte-/Sprachverfügbarkeit real prüfen. Quellen: https://supabase.com/legal/privacy-resources/data-residency-and-transfers-faq ; https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition .
