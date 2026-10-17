# Werkbeleg — gehostete Teamcloud, Entscheidungsstand 17.10.2026

## Bestätigte Produktvorgaben

- Monatspreise pro Betrieb: 5 Personen 9,99 €, 10 Personen 14,99 €, 20 Personen 19,99 €. Der Inhaber wird mitgezählt; diese Interpretation wurde dem Nutzer genannt.
- Projekte mit Berichten und Kommunikation, Einladungen auch über WhatsApp.
- Eigene Cloud-/iCloud-Sicherungen gewünscht. Nutzer fragt, ob wir eine gemeinsame Cloud anbieten sollten und was diese kostet. Noch keine Beauftragung eines kostenpflichtigen Hostinganbieters.

## Empfehlung, noch keine beschlossene Freischaltung

Eine von uns betriebene Teamcloud als Standard, optionaler iCloud-/Dateien-Export als zusätzliche Sicherung. Vorgeschlagene Gesamtspeicherkontingente pro Betrieb: 5 / 10 / 20 GB entsprechend den Paketen. Diese Kontingente sind ein Vorschlag, nicht aktiv eingerichtet. Keine unbegrenzte Speicherzusage.

Einzelne persönliche iCloud-Datenbanken je Mitarbeiter ergeben noch keinen gemeinsamen Projektbestand. Eine reine Apple-Lösung kann CloudKit-Sharing nutzen: Bestand beim Inhaber, Freigaben an Teilnehmer. Aktive iCloud-Accounts sind nötig; die gespeicherten geteilten Daten belasten das Kontingent des Eigentümers. CKShare unterstützt bis zu 100 Teilnehmer, also grundsätzlich auch 20. Für eine unabhängige B2B-Plattform empfehlen wir einen gemeinsamen Firmenmandanten, damit Geschäftsdaten nicht ausschließlich an den privaten Apple-Account eines Inhabers gebunden sind. iCloud-Backup und aktive Datenbanksynchronisation ausdrücklich unterscheiden.

## Verifizierte Preisbasis und Rechenbeispiele

Primärquellen, abgerufen am 17.10.2026:

- Cloudflare R2 Standard: 0,015 US$/GB-Monat, 10 GB-Monate monatlich frei. Schreib-/Leseoperationen separat; direkter R2-Egress ohne Bandbreitenentgelt. https://developers.cloudflare.com/r2/pricing/
- Supabase Pro: ab 25 US$/Monat mit erster Micro-Instanz; unter anderem 100 GB Dateispeicher, danach 0,0213 US$/GB-Monat. Datenbank-, Compute-, Egress- und weitere Limits beachten. https://supabase.com/pricing
- CloudKit-Teilnehmer: https://developer.apple.com/documentation/cloudkit/ckshare
- Quoten bei geteilten Daten: https://developer.apple.com/documentation/cloudkit/ckdatabase/scope/shared

Reiner R2-Speicher, angenommen konstant 100 Betriebe × 5 GB = 500 GB über einen Monat: (500 − 10) × 0,015 = **7,35 US$/Monat insgesamt**. Kein Gesamtbetriebspreis: Datenbank, Authentifizierung, API, Operationen, Sicherungskopien, Support, Steuern und mögliche weitere Dienste sind nicht darin enthalten.

Alternative: Supabase mit demselben 500-GB-Dateibestand: 25 US$ Basis + (500 − 100) × 0,0213 = **33,52 US$/Monat**, sofern die enthaltene erste Compute-Instanz genügt und keine anderen Kontingente überschritten werden. Kein zugesicherter Preis für 100 produktive Betriebe. Nutzerzahl und Datenverkehr müssen gemessen werden. R2 und Supabase-Dateispeicher sind alternative Medienspeicher; deren volle Kapazitäten nicht versehentlich doppelt kalkulieren.

Zwei Sicherungskopien können den tatsächlichen Speicherbedarf erhöhen. Kontingente gelten für den gespeicherten Gesamtbestand, nicht als jeden Monat zusätzlich kostenloses Volumen. Bildkompression und Archivierung vorsehen; Aufbewahrungs-/Löschregeln müssen vor dem Verkauf definiert werden.

## Vor einer Produktionscloud erforderliche Architektur

Der aktuelle Python-Testserver ist **ein Betrieb pro Datenbank**, Token-Authentifizierung, JSON-Workspace bis 30 MiB. Er ist kein fertig gehosteter SaaS-Dienst. Die vorgeschlagenen 5–20 GB lassen sich nicht durch bloßes Anheben dieses JSON-Limits erfüllen.

1. Gemeinsame Plattform mit getrennten Firmenmandanten. Organisation, Mitgliedschaft und Rolle serverseitig prüfen; alle Projekte/Kunden/Berichte/Nachrichten einem Firmenmandanten zuordnen. Zugriff eines fremden Betriebs muss auch bei erratenen IDs scheitern.
2. Datenbank enthält Metadaten. JPEG-/Audiodateien kommen in privaten Objektspeicher. Keine großen Base64-Dateien in jeder Datenbanksynchronisation. Übertragungen vom Dateisystem streamen; Downloads nach Bedarf und lokale Cachegrenzen.
3. Benutzeranmeldung, Widerruf, Wiederherstellung und Eigentümerwechsel als echte Produktabläufe. Bisherige Admin-Tokens und manuelle CLI-Paketwahl sind nur Pilotmechanismen.
4. Chat mit paginierten Änderungen oder Echtzeitkanal. Der Pilot ruft im geöffneten Chat alle zehn Sekunden den gesamten bisherigen Projektverlauf ab; dies nicht unverändert auf viele Betriebe skalieren. Chatverkehr kann mehr kosten als Speicher. Reconnect/Offline-Nachlieferung über Cursor und idempotente Nachrichten-IDs.
5. Datensatzweise Synchronisation für Berichte statt ganzer JSON-Snapshots. Konflikte nachvollziehbar lösen; Fotos separat hochladen. Offline-Warteschlange und Wiederholungen testen.
6. Abogröße über serverseitig verifizierten Kaufstatus bestimmen. Plätze inklusive ausstehender Einladungen atomar prüfen. Kein Vertrauen in ein vom Client ausgewähltes Preisschild. App-Store-Produkte und Zahlungsprüfung noch nicht aktiv.
7. Speicherverbrauch pro Betrieb erfassen; Kontingent vor Upload reservieren, bei Abbruch zurückgeben. Größere Datenmengen dürfen nicht erst beim PDF-/Backup-Export den Arbeitsspeicher sprengen.
8. EU-Datenregion und Vertrags-/Datenschutzanforderungen vor der Anbieterbuchung prüfen. Backups und Wiederherstellung tatsächlich testen; getrennte Datenbank- und Medienbackups berücksichtigen.

## Nächster konkreter Schritt

Version 1.1.0 (Build 20) wurde erfolgreich signiert und per OTA veröffentlicht. Version 1.1.1 (Build 21) wurde ebenfalls erfolgreich signiert und per OTA veröffentlicht. Der Simulator bestätigte die lokale Speech-Anfragerichtlinie ohne Netzwerk-Fallback, sechs PDF-Seiten, Datenspeicherung, Backup-Roundtrip und Bildgrößenbegrenzung. Kamera, Mikrofon und reale Erkennungsqualität wurden nicht im Simulator getestet. Die öffentliche IPA und ihr SHA-256 wurden abgeglichen: 3b15105546caa7dc764def6e9986981a3cadd2a61a00c1753d5c4a07b69ab167. Buildnachweis: https://github.com/p1337/meshtastic-backend/actions/runs/39054073759 . Installation: https://p1337.github.io/meshtastic-backend/?build=21 . Danach Hostingvariante und Betreiberkonto auswählen. Ohne eingerichtetes Providerkonto, Datenregion, Zugang und Kostenfreigabe keine bezahlten Dienste anlegen und keinen aktiven Cloudbetrieb behaupten. Zunächst einen Firmenmandanten mit zwei echten Geräten prüfen; dann Trennung zwischen zwei Betrieben und Last-/Speichermessungen. iCloud-Unterstützung in der derzeitigen App ist Export in Dateien, noch kein CloudKit-Sync.


## Konkret vorbereiteter Stand

Unter `werkbeleg-cloud/` liegen eine Supabase-Migration und PostgreSQL-16-Tests für die Mandantentrennung, Rechte, Einladungen und private Medien. Das ist noch keine bereitgestellte Cloud und noch keine native Supabase-Anbindung. Direkte Uploads sind bis zur Implementierung eines geprüften Uploadwegs gesperrt. Für neue Testbetriebe sind 100 MB Reservierung vorgesehen; die kommerziellen 5/10/20-GB-Kontingente sind weiterhin nur vorgeschlagen. Supabase wurde als verfügbare Anbindung gefunden und zum Installieren/Verbinden angeboten; eine Verbindung ist bislang nicht bestätigt. Kein kostenpflichtiger Tarif wurde gebucht.


## Verbindliche neue Vorgabe: Europa

Geschäftsdaten sollen in Europa liegen. Bevorzugte feste Projektregion: Frankfurt (eu-central-1), nicht globale automatische Regionswahl. Datenbank, Auth-Kerndaten, Fotos, Audio, Medienbackups und Verarbeitungspfade prüfen. Supabase beschreibt explizite Ausnahmen (CDN, Support, Konto-/Betriebsmetadaten): https://supabase.com/legal/privacy-resources/data-residency-and-transfers-faq . EU-only ist daher noch nicht nachgewiesen; vor echtem Upload passende Konfiguration oder alternativ EU-gehosteten Dienst wählen. Es wurde kein Kundenbestand hochgeladen. Native Version 1.1.1 verwendet nur lokale Spracherkennung ohne Netzwerk-Fallback. GitHub enthält Quellcode und synthetische Tests, keine Kundenberichte.

## Nachgewiesene Cloud-Grundlagentests

Am 17.10.2026 bestanden 31 Prüfungen in einer isolierten PostgreSQL-16-Testdatenbank: Mandantentrennung, Leser-/Schreiberrollen, unveränderliche Autor-/Zeitfelder, Paket- und Platzgrenzen einschließlich offener Einladungen, einmalige und ablaufende Einladungen, private Medien, Speicherreservierung und gesperrte ungeprüfte Uploads. CI-Nachweis: https://github.com/p1337/meshtastic-backend/actions/runs/39054073801 . Dies prüft die SQL-Regeln mit synthetischen Daten; kein Nachweis einer realen Supabase-Anmeldung, eines echten Medienuploads oder einer vollständigen EU-Datenresidenz.
