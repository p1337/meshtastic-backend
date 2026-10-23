# Veröffentlichung und Lizenzentscheidung

Status: **kein Verkaufsrelease**. Die App hat derzeit keinen nachgewiesenen Ausgang zur unveränderten Incyclist-App; beide Pucks und die Fahrwirkung sind nicht abgenommen. Preisbewertung, Bezahlfunktion und Store-Metadaten folgen erst nach einem funktionsfähigen Prototyp.

## Geschäftsmodell

Bezahlter App-Store-Download oder einmaliger, nicht verbrauchbarer StoreKit-Kauf. Keine wiederkehrenden Gebühren, Werbung, Konten oder Cloudpflicht. Der Prototyp enthält keine Kasse, keine Probeabo-Falle und keine Kauf-Freischaltung ohne realen Nutzen. StoreKit-Kauf/Restore erfordert Apples Store-Infrastruktur; der spätere Fahrbetrieb soll nach Freischaltung offline funktionieren. Eine Firmware-Freischaltung durch eine fremde Cloud wäre mit der strikten Anforderung gesondert zu bewerten.

## Aktuelle Apple-Prüfung

Primärquelle: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), abgerufen am 23.10.2026. Für die Einreichung relevant: vollständige Funktion und ehrliche Beschreibung (2.1), öffentliche APIs (2.5.1), zweckgerechter Hintergrundmodus (2.5.4), digitale Freischaltung über In-App Purchase (3.1.1), ausreichender eigenständiger Nutzen (4.2) und Datenschutz (5.1). Keine Zulassungsgarantie. Die unfertige Schaltintegration darf nicht als verkaufte Funktion beworben werden.

Bluetooth-Zweckbeschreibung und `bluetooth-central` sind vorhanden. Kein Standort-/HealthKit-/Mikrofonzugriff. Lokale Einstellungen nutzen UserDefaults; das Manifest nennt den [Apple-Grund CA92.1](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype). Vor Einreichung aktuelle API-/SDK-/Datenschutzauswertung des fertigen Builds durchführen.

## Lizenzen

| Bestandteil | Lizenz / Entscheidung |
|---|---|
| Eigener ClickBridge-Code | MIT, kommerzielle Nutzung und Einbettung erlaubt; Lizenzhinweise bleiben erhalten. |
| TrainerHUD am festgelegten Commit | MIT; Protokollreferenzen und zwei Capture-Vektoren mit vollständigem Hinweis in `THIRD_PARTY_NOTICES.md`. |
| Incyclist mobile/devices/services | MIT; eine tatsächliche Quellübernahme im Fork muss die vorhandenen Hinweise behalten. Der Installer verändert den Originalbaum und bewahrt dessen LICENSE. |
| Aktuelles BikeControl | Non-Commercial-Lizenz; keine kommerzielle Codeübernahme. Privates `prop`-Modul nicht zugänglich. Nur als technische Recherche verwendet. |
| zubinkavarana/swiftcontrol | GPL-3.0; kein Code übernommen. Eine kommerzielle Nutzung ist nicht generell verboten, aber Copyleft-/Distributionsbedingungen müssten gesondert erfüllt werden. |
| Bestehendes meshtastic-backend | Enthält ältere GPL-Bestandteile. Die neue App ist ein eigenständiges Paket und verwendet keinen alten Backend-/LoRa-/Werkbeleg-Code. Getrennte Artefakte und Lizenztexte beibehalten; endgültige Vertriebsprüfung vor Veröffentlichung. |

Eine Code-Lizenz ist keine Garantie für Patentfreiheit oder Herstellerfreigabe. Insbesondere Code aus einem privaten oder nicht kommerziell lizenzierten Modul wird nicht durch Übersetzen in Swift frei.

## Marken und Produktbeschreibung

Eigener Name und eigenes Icon, keine Zwift-/Incyclist-Logos. Nur sachliche Kompatibilitätsangaben, nachdem sie getestet wurden; unabhängiges Projekt klar kennzeichnen. [Zwifts Bedingungen, Abschnitt Marken](https://eu.zwift.com/policies/terms-of-service) beanspruchen Namen/Logos und untersagen eine vorgetäuschte Verbindung. Die rechtliche Zulässigkeit des endgültigen Namens, Store-Auftritts und konkreter Kompatibilitätswerbung bleibt vor Veröffentlichung zu prüfen. Keine Behauptung einer offiziellen Partnerschaft.

## Datenschutz und Wartbarkeit

Keine automatische Datenerhebung oder Übertragung. Diagnoseexport ist nutzergesteuert und kann lokale Gerätekennungsfragmente sowie Firmware-/Tastenzeitpunkte enthalten. Store-Datenschutzerklärung und Supportadresse müssen das tatsächliche spätere Produkt beschreiben. Kaufbelege dürfen nicht als Accountzwang dienen.

Firmwarematrix je Version führen, unveränderte Referenzpakete aufbewahren, unbekannte Frames fehlergeschlossen behandeln, keine stillen Firmwareupdates. Nach Änderungen Decoder-/State-/Routingtests und betroffene Hardwarepunkte erneut ausführen. Vor Vertrieb: 60-Minuten-Abnahme beider Seiten, Offlinebetrieb ohne Zwift-Freischaltung, integrierter Incyclist-Build, Wiederverbindung und öffentliche Signierung/Distribution lösen.
