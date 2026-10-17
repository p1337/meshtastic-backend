# Werkbeleg: Kundenimport und Trennung zahlender Betriebe

Stand: 17.10.2026. Verbindliche Nutzervorgaben: Kundendatenbestand pro bezahltem Betriebszugang; kein Zugriff zwischen fremden Betriebszugängen; Datenhaltung Europa. Dieses Dokument beschreibt Anforderungen und recherchierte Importwege, keine bereits fertigen Funktionen.

## 1. Produkt- und Kontogrenze

Ein Betriebsabo bezahlt einen Firmenbereich (Mandanten) mit 5 / 10 / 20 Personen für 9,99 / 14,99 / 19,99 Euro monatlich. Eingeladene Mitarbeiter arbeiten im selben Kundenbestand dieses Betriebs; jeder hat eine eigene Anmeldung. Nicht für jeden Mitarbeiter eine neue, getrennte Kundenkartei anlegen. Ein fremder Betrieb bekommt weder Suchtreffer, Kundenzahlen, Dateien noch Nachrichten des anderen.

Eine eigene logische Kundendatenbank je Betrieb ist verpflichtend. Eine eigene physische PostgreSQL-Instanz pro Abo ist damit nicht automatisch erforderlich. Ziel für die Standardpakete: gemeinsames Datenbanksystem mit erzwungener Mandantentrennung plus separaten privaten Dateipfaden. Getrennte physische Instanzen wären eine zusätzliche Betriebsvariante mit höherem Verwaltungsaufwand, keine absolute Sicherheitsgarantie. Niemals im Vertrieb eine dedizierte Datenbank versprechen, solange tatsächlich RLS verwendet wird.

Zugang setzt Identität UND berechtigte Mitgliedschaft voraus. Zahlung allein gewährt keine Mitgliedschaft in irgendeinem vorhandenen Betrieb. E-Mail-Domain, Kundennummer und Apple-Account sind keine Mandantenzuordnung. Falls mehrere Betriebsmitgliedschaften später erlaubt werden: bewusster Bereichswechsel, getrennte lokale Bestände, niemals Zusammenführen durch identische E-Mail/Kundennummer.

## 2. Durchzusetzende Schutzregeln

Unsere Implementierungsanforderungen:

1. Jeder Datensatz, Importauftrag, Audit-Eintrag und jede Datei gehört zu einer unveränderlichen `org_id`. Server bestimmt den zulässigen Betrieb aus authentifizierter Mitgliedschaft; eine übermittelte Firmen-ID wird nicht ungeprüft vertraut. Kein Standardbetrieb bei fehlendem Kontext.
2. RLS in PostgreSQL schützt alle Geschäftstabellen zusätzlich zur API. Zusammengesetzte Schlüssel `(org_id, id)` und Fremdschlüssel verhindern Verknüpfungen fremder Kunden, Projekte und Berichte. Daten dürfen nicht durch UPDATE in einen anderen Betriebsbereich verschoben werden, auch wenn ein Nutzer in beiden Mitglied ist.
3. Keine Supabase-Secret-/Service-Zugangsdaten in IPA, GitHub Pages oder Importdateien. Diese Schlüssel können RLS umgehen. Importer arbeitet bevorzugt mit beschränkter Rolle und authentifiziertem Betriebskontext. Jeder privilegierte Serverweg benötigt eigene Autorisierung und Negativtests.
4. Fotos, Audio, PDF, Vorschaubilder und Importdateien privat. Nicht bloß unerratbare URLs. Downloads mit aktueller Berechtigungsprüfung; keine frei weitergebbaren dauerhaften Downloadlinks. Zeitlich signierte Links sind bis zum Ablauf übertragbare Berechtigungen: für sofort widerrufbare Zugriffe authentifizierten Downloadweg bevorzugen. Bereits heruntergeladene oder absichtlich exportierte Kopien lassen sich nicht zuverlässig zurückholen.
5. Suche, Chat/Realtime, Push, Cache, Offline-Warteschlange, Hintergrundaufträge und Exporte verwenden denselben geprüften Betriebsbereich. Schlüssel enthalten Betrieb und gegebenenfalls Benutzer/Rolle. Nach Abmeldung oder Wechsel keine Vorschau, Suchhistorie oder Antwort des vorherigen Bereichs anzeigen. Alte Antworten nach einem Wechsel verwerfen.
6. Rollen: Inhaber verwaltet Abo und Betrieb; Admin verwaltet berechtigte Mitarbeiter und Importe; Bearbeiter arbeitet an freigegebenen Daten; Leser schreibt/importiert nicht. Vollständige Kundenexporte und Massenänderungen nur Inhaber/Admin. Projektbezogene Einschränkungen für Monteure sind eine weitere Produktstufe, derzeit nicht implementiert.
7. WhatsApp transportiert lediglich die Einladung. Authentifizierter Empfänger, zeitliche Begrenzung, einmalige Verwendung und Platzreservierung bleiben nötig. Aktueller Entwurf bindet den Code noch nicht an eine Zielidentität: vor Produktivstart verifizierte Empfängerbindung oder explizite Admin-Freigabe ergänzen, damit Weiterleiten allein keinen Zugang gibt.
8. Mitgliedschaftsentzug verhindert neue Serverzugriffe auch mit noch gültigem Login-Token. Keine ausschließlich im Token eingebrannte, bis Ablauf weitergültige Firmenrolle. MFA für Inhaber/Admin, Sitzungsverwaltung und Wiederherstellungsprozess vorsehen. Lokale bereits autorisiert bezogene Offline-Daten separat behandeln; keine sofortige Fernlöschung versprechen.
9. Abo serverseitig an genau einen Betrieb binden. Apple-signierte Kaufdaten verifizieren; Original-Transaktionskennung eindeutig zuordnen, keine doppelte Freischaltung durch Wiederherstellen in einem zweiten Betrieb. Webhooks auf Echtheit, Reihenfolge und Wiederholung prüfen. Paket, Plätze und Zahlungsstatus nie aus einem Client-Preisschild übernehmen. Testbetrieb und zahlender Betrieb müssen unterscheidbar sein.
10. Abo-Ende ändert keinen Datenbesitzer und verschiebt keine Daten. Lese-/Exportfrist, Sperre und Löschfristen vor Verkauf definieren. Herabstufung unter belegte Plätze niemals durch zufälliges Entfernen von Mitarbeitern lösen.
11. Backups und Restore bleiben mandantengebunden. Supportzugriffe zeitlich begrenzt, nachvollziehbar und minimal; normale Mitarbeiterzugänge des Betreibers sehen keine Kundendaten. Geheimnisse und Kundennamen nicht in CI-/Fehlerlogs schreiben. Datenbank- und Dateisicherung separat testen. EU-Vorgabe gilt auch für temporäre Importdaten und deren Verarbeitung; Supabase-Region allein genügt nicht als EU-only-Nachweis.

Orientierung: OWASP-Mandantentrennung [S1], Supabase-RLS und Schlüsselrollen [S2–S3]. Das ist ein Anforderungskatalog für unser Produkt, keine Zertifizierung oder Zusicherung von Fehlerfreiheit.

## 3. Recherchierte Quellenprogramme

Herstellerdokumentation belegt den Exportweg, nicht schon die Kompatibilität eines Werkbeleg-Importers. Exportschemata und Optionen können versions-/paketabhängig sein. Für jeden benannten Adapter braucht es ein anonymisiertes Referenzexportfile und einen Regressionstest. Keine echten Kundendaten in das öffentliche Repository übernehmen.

| Quelle | Nachgewiesener Weg | Umsetzungsvorgabe |
| --- | --- | --- |
| Lexware Office | Kontakte als CSV [S4] | CSV-Profil; Kunden und Lieferanten unterscheiden; externe Kundennummer erhalten |
| sevdesk | Kontaktlisten-CSV in offizieller API [S5] | Dateiimport zuerst; API/OAuth-/Tokenanbindung separat prüfen, nicht als aktiv bewerben |
| ToolTime | Kundendaten als CSV oder Excel [S6] | CSV-/Tabellenzuordnung, Feldschema anhand Referenzdatei bestätigen |
| HERO | Hersteller nennt CSV-/Excel-Datenexport [S7] | Allgemeiner Importweg; genaue Kundenexportspalten noch nicht verifiziert |
| bexio (Schweiz) | Adressen als CSV/Excel [S8] | Firmen/Personen, mehrere Adressen, Schweizer Länder-/PLZ-/UID-Daten berücksichtigen |
| ProSaldo.net (Österreich) | Kundenexport CSV [S9] | CSV-Profil, österreichische Anschriften und UID erhalten |
| Fakturownia (Polen) | Kundenliste über Export do XLS [S10] | Legacy-XLS ausdrücklich berücksichtigen; nicht fälschlich XLSX nennen |
| Outlook | Kontakte CSV [S11] | Sprachabhängige Spaltennamen zuordnen |
| Google Kontakte | CSV oder vCard [S12] | Mehrere Telefonnummern/Mails erhalten |
| Apple/iCloud Kontakte | vCard/VCF [S13] | Selektive Dateiübernahme; kein automatisches Hochladen des privaten Adressbuchs |
| Excel, Numbers, LibreOffice | Ausgangsbasis der allgemeinen Tabellenimporte | CSV und XLSX als Zielformate; konkrete Exportvariante prüfen |
| TAIFUN, pds, weitere ältere Handwerkssysteme | In dieser Recherche kein hinreichend konkretes Kundenexportschema verifiziert | Nicht als unterstützten Adapter bewerben; allgemeine Zuordnung erst an Exportdatei prüfen |

Nicht behaupten, alle Programme direkt anzubinden. Ehrliche Produktformulierung nach bestandenen Dateitests: „Kundenübernahme aus CSV, Excel und Kontaktdateien mit Importassistent“. DATEV-Buchungsexporte, GAEB-Leistungsverzeichnisse und DATANORM-Artikeldateien sind keine generischen Kundenlisten.

## 4. Kundenmodell für DACH/Polen/Englisch

Der heutige Pilot speichert lediglich Name, freie Adresse und Kontakttext. Vor strukturiertem Import erweitern, alte Backups lesbar halten:

- Person/Firma, Anzeigename; Vorname, Nachname, Firmenname und Ansprechpartner getrennt.
- Interne UUID unabhängig von externer Kundennummer; Quellsystem und Quellkonto/-datenbestand separat. Externe Identität eindeutig innerhalb `(org_id, source, source_account, external_id)`, nicht plattformweit.
- Rechnungs- und Einsatzadressen, Straße/Hausnummer/Adresszusatz/PLZ/Ort/Land als Text. Führende Nullen erhalten; keine deutsche PLZ-Länge weltweit erzwingen.
- Mehrere E-Mails/Telefonnummern mit Typ; Telefon als Text, Normalisierung nur mit Länderbezug. Originalwert bei Bedarf erhalten.
- Sprache DE/EN/PL, Notizen, optionale USt-ID/UID/NIP mit Kennzeichnung des Typs; keine allgemeine Pflicht für Privatkunden. Keine Bankdaten importieren, solange hierfür kein konkreter Produktzweck besteht.
- Archivstatus, Erstell-/Änderungszeit, Herkunft und Importlauf. Keine fremde Firmen-ID aus Quelldateien übernehmen.

## 5. Importassistent und Datenqualität

Ablauf: Datei lokal auswählen → Betrieb klar anzeigen → Format/Arbeitsblatt erkennen → Spalten vorschlagen → Zuordnung korrigieren → Vorschau und Dubletten prüfen → Zusammenfassung bestätigen → mandantengebunden schreiben → Ergebnisbericht und gezieltes Rückgängigmachen anbieten.

Muss-Funktionen:

- CSV mit Komma, Semikolon und Tabulator; echte Anführungszeichen, eingebettete Zeilenumbrüche und UTF-8/BOM. Ältere Windows-1252/1250-Dateien nur mit kontrollierter Auswahl/Vorschau, keine stille Zeichenzerstörung. DE-/PL-Sonderzeichen testen.
- XLSX als Daten lesen: keine Makros, Formeln, externen Verknüpfungen oder eingebetteten Programme ausführen. Legacy-XLS benötigt eigenen geprüften Parser oder eine ausdrücklich erklärte Umwandlung in CSV/XLSX. XLSM und passwortgeschützte Dateien zunächst verständlich ablehnen. Schutz vor extrem entpackten XLSX-Dateien, überlangen Feldern und Ressourcenerschöpfung.
- VCF-Multikontaktdateien, mehrfache Adressen/Telefon-/Mailfelder, Zeichensatzvarianten und gefaltete Zeilen kontrolliert verarbeiten. Dateigröße, Datensätze und Feldlängen begrenzen. Erste vorgeschlagene Produktgrenze: 10 MiB Quelldatei, 10.000 Kunden pro Lauf; Messungen vor Freigabe erforderlich.
- Zuordnungsprofile für Deutsch/Englisch/Polnisch, unbekannte Spalten sichtbar lassen. Keine Adressen/Personennamen durch ungeprüfte KI erfinden. Für diese Kernfunktion ist keine externe KI-Übertragung nötig.
- Dubletten: zuerst externe ID plus Quellbestand im selben Betrieb. Gleiche Mail/Telefon ist nur ein Hinweis, da Haushalte und Firmen Nummern teilen. Gleicher Name niemals automatisch zusammenführen. Bestehende Kunden standardmäßig nicht überschreiben, leere Werte löschen nichts ohne explizite Wahl.
- Vorschau, Zeilenfehler, neu/aktualisiert/übersprungen-Zählung; keine stille Teilmigration. Wiederholungen idempotent. Staging und Commit-Lauf ausschließlich im berechtigten Betrieb, Autorisierung beim Start und beim Commit erneut prüfen. Ein reiner Dateihash genügt nicht, wenn Zuordnung/Importoptionen geändert wurden.
- Rückgängig nur mit Vorherständen und Änderungsversionen; zwischenzeitliche Mitarbeiteränderungen nicht überschreiben. Wiederherstellungsdateien genauso privat wie Kundendaten. Fehlerberichte enthalten keine fremden Daten; temporäre Dateien nach festgelegter Frist beseitigen.
- CSV-Formeln als Text behandeln; beim späteren Tabellenexport Formula Injection berücksichtigen [S14]. Inhalte nicht pauschal abschneiden: Telefonnummern mit + und legitime Notizen erhalten.

## 6. Abnahme vor echten Kundendaten

Bestehender Nachweis: 31 PostgreSQL-16-Prüfungen erfolgreich, https://github.com/p1337/meshtastic-backend/actions/runs/39054073801 . Getestet wurden RLS/Privilegien mit synthetischen Identitäten und simuliertem Auth-/Storage-Schema. Kein vollständiger HTTP-/JWT-/Cloud-/Import-/Abo-Nachweis.

Zusätzliche verpflichtende Abnahme:

| Bereich | Angriffs-/Fehlerfall | Erwartung |
| --- | --- | --- |
| Zwei Betriebe A/B | Nutzer A verwendet echte Kunden-/Projekt-/Datei-IDs von B in Lesen/Ändern/Löschen/Suche/Export/Import/RPC | Keine Daten und keine Änderung bei B; keine Vorschau/Anzahl/Fehlermeldung mit B-Inhalt |
| Mandantenwechsel | Gleichzeitig Mitglied in A/B; Update org_id, offene Anfrage, Offline-Queue und Cache von A nach Wechsel zu B | Keine Datenverschiebung, kein falscher Zielbetrieb, keine Anzeige alter Antworten |
| Zugriffsverlust | Leser, abgemeldeter, abgelaufener oder widerrufener Nutzer; noch gültiger Token nach Mitgliedschaftsentzug | Kein neuer unberechtigter Serverzugriff; lokale Offline-Grenzen separat dokumentiert |
| Einladungen | Weiterleitung, Wiederverwendung, Ablauf, parallele Annahme und letzter verfügbarer Platz | Nur bestätigte Zielperson, einmalig, Platzlimit bleibt erhalten |
| Dateien | Vorschaubild/PDF/Original/temporärer Import; manipulierte Pfade und bereits erstellte Downloadberechtigung | Kein fremder Zugriff; Widerrufs- und Ablaufverhalten messen |
| Importe | Gleiche externe Kundennummer und dieselbe Quelldatei in A und B; eingeschleuste org_id; Wiederholung und Abbruch | Bestände unabhängig; kein Überschreiben zwischen Betrieben; reproduzierbares Ergebnis |
| Importqualität | Umlaute/Ł/ß, führende Null, Anführungszeichen, Mehrzeiler, unklare Dublette, Formeln, kaputte/überdimensionierte Datei | Keine stille Änderung, sichere Ablehnung oder sichtbarer Korrekturschritt |
| Abo | Client behauptet 20 Plätze, Kauf von A wird in B wiederhergestellt, doppelte/verspätete Benachrichtigung | Verifizierte einmalige Zuordnung, kein Wechsel des Datenbesitzers |
| Hintergrund/Restore | Gleichzeitige Importe/Chat/Backup; Restore von A, während B aktiv ist | Nur berechtigter Bereich, keine verlorenen Fremdänderungen |

Tests gegen echte Provider-Anmeldung, Daten- und Storage-API sowie reale App-Pfade laufen in einer getrennten EU-Testumgebung mit zwei Betrieben. Produktivzugang bleibt bis dahin gesperrt. Unabhängige Sicherheitsprüfung vor öffentlichem Kundendatenbetrieb; Regressionen bei relevanten Änderungen. „100 % wasserdicht“ darf nicht als technisch bewiesene Garantie verkauft werden.

## 7. Umsetzung in prüfbaren Schritten

1. Diese Regeln als Abnahmekriterien festlegen. SQL-Lücken schließen: unveränderliche Mandantenzuordnung, sichere Mitgliedschaftsverwaltung/Einladungsempfänger, verifiziertes Abo. Der aktuelle SQL-Entwurf erlaubt noch kostenlose Testbetriebserstellung ohne Kaufprüfung und hat keinen fertigen Widerrufs-/Aboablauf.
2. Kundenmodell abwärtskompatibel erweitern, allgemeiner CSV-Import zunächst lokal mit Vorschau/Zuordnung, Dubletten und Undo. Noch keine Provider- oder Servergeheimnisse nötig.
3. XLSX/VCF und geprüfte Quellprofile ergänzen; für XLS Parser prüfen oder dokumentierte Konvertierung anbieten. Synthetische Herstellerlayout-Fixtures eindeutig als solche kennzeichnen; echte Kompatibilität erst mit Referenzexport beweisen.
4. Native Anmeldung, getrennte lokale Betriebsbestände und datensatzweiser Cloudimport/-sync. Den alten JSON-Pilotserver nicht lediglich mit einem Supabase-URL-Feld zum SaaS erklären.
5. Vollständige A/B-Abnahme und Recovery, unabhängige Prüfung, dann echter Pilot mit Kundendaten. EU-Verarbeitungspfade vorab bestätigen. Erst danach Vermarktung und aktive Abos.

Es wurde durch diese Recherche keine neue Appfunktion, Kundenmigration oder produktive Cloud aktiviert.

## Primärquellen

Alle am 17.10.2026 geprüft; Quellen belegen Herstellerfunktionen bzw. technische Grundlagen, nicht die Fertigstellung unseres Produkts.

- [S1] OWASP Multi Tenant Security: https://cheatsheetseries.owasp.org/cheatsheets/Multi_Tenant_Security_Cheat_Sheet.html
- [S2] Supabase RLS: https://supabase.com/docs/guides/database/postgres/row-level-security
- [S3] Supabase Schlüsselrollen: https://supabase.com/docs/guides/getting-started/api-keys
- [S4] Lexware Kontakte exportieren: https://help.lexware.de/de-form/articles/548273-wie-exportiere-ich-kontakte
- [S5] sevdesk offizielle API, Kontaktlistenexport: https://api.sevdesk.de/
- [S6] ToolTime Datenexporte: https://support.tooltime.app/de/articles/4538822-datenexporte-aus-tooltime
- [S7] HERO Datenexport: https://hero-software.de/features/stammdaten/daten-export
- [S8] bexio Adressverwaltung: https://www.bexio.com/de-CH/adressverwaltung
- [S9] ProSaldo.net Datenexport: https://support.prosaldo.net/support/solutions/articles/101000415262-datenexport
- [S10] Fakturownia Kundenbestand übertragen: https://pomoc.fakturownia.pl/605582-Jak-wyglada-przeniesienie-bazy-klientow-miedzy-kontami-na-Fakturowni
- [S11] Microsoft Outlook Import/Export: https://support.microsoft.com/en-au/outlook/import-and-export-outlook-email-contacts-and-calendar
- [S12] Google Kontakte exportieren: https://support.google.com/contacts/answer/7199294?hl=de
- [S13] Apple iCloud vCard: https://support.apple.com/de-de/guide/icloud/mmfba748b2/1.0
- [S14] OWASP CSV Injection: https://community.owasp.org/attacks/CSV_Injection
- [S15] Apple Kaufdaten-Verifikation: https://developer.apple.com/videos/play/wwdc2024/10062/
- [S16] Supabase regionale Verarbeitungsausnahmen: https://supabase.com/legal/privacy-resources/data-residency-and-transfers-faq

## Implementierungsstand Version 1.2 (17.10.2026)

Der native Importassistent und die strukturierte Kundenkartei sind implementiert: CSV/TSV/Text mit auswählbarem Zeichensatz, XLSX-Tabellenauswahl, vCard, manuelle Spaltenzuordnung, Vorschau und standardmäßig abgewählte Dubletten. Übernahme fügt hinzu, überschreibt keine Kunden. Die letzte Übernahme kann selektiv rückgängig gemacht werden; geänderte oder in Projekten referenzierte Kunden bleiben erhalten. Suchbare Kundenliste und Detailseite mit Projekten vorhanden. Alte Backups bleiben lesbar. XLS-Altformate, Makros, verschlüsselte und Formel-Tabellen benötigen weiterhin Konvertierung in CSV oder reine Werte; keine vollständige Hersteller-API-Synchronisation. Synthetische Vorlage: WERKBELEG_KUNDEN_VORLAGE.csv.

Cloud-Migration 002 und 50 PostgreSQL-Prüfungen ergänzen unveränderliche Betriebszuordnung, adminbeschränkten Insert-Import mit atomarem Rollback, Quellen-ID-Trennung, personengebundene Einladungen, Mitgliedschaftsentzug und eine eindeutige Transaktionszuordnung für künftige Aboverifikation. Letzter bestandener SQL-Lauf: https://github.com/p1337/meshtastic-backend/actions/runs/39060337905 .

Die native Pilot-App trennt lokale Daten nach Server/Zugang in eigene Bereiche. Der alte anonyme Einladungsbeitritt ist gesperrt, bis die personengebundene Hosted-Auth-Anbindung fertig ist. Die früheren Pilotlinks sind kein Ersatz dafür. Echte Apple-Kaufverifikation, native Supabase-Auth, Dateien-/Import-RPC-Anbindung, Echtbetrieb mit mehreren Geräten, unabhängige Prüfung und verifizierter EU-Betrieb bleiben offen. Keine Produktionsfreigabe und keine 100-%-Garantie.

CI-Hinweis: 41 native Foundation-/Importprüfungen bestanden bereits. Ein erster Simulatorlauf bestand Import/Rücknahme, scheiterte dann am echten Schlüsselbund des unsignierten Simulators. Der Simulator verwendet deshalb nun ausdrücklich einen isolierten Zugangsspeicher-Testdouble; dessen Erfolg beweist keine iPhone-Keychain-ACL. Der signierte Gerätebuild enthält diesen Testdouble nicht. Finale Veröffentlichung separat verifizieren.
