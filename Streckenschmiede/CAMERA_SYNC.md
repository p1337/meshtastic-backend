# DJI Osmo Action 5 Pro – Video-/GPS-Synchronisierung

Stand: 4. November 2026. Verbindliche Kamera für die erste Integration ist die **DJI Osmo Action 5 Pro**.

## Entscheidung

Streckenschmiede zeichnet GPS, Sensoren und Fahrtzeit unabhängig von der Kamera auf. Die Action 5 Pro darf parallel eigenständig filmen. Nach der Fahrt werden Videodateien eingelesen und mit der Fahrt verbunden.

Die Synchronisierung verwendet mehrere Ebenen, damit sie ohne proprietäre DJI-Schnittstelle zuverlässig bleibt:

1. **Optischer Streckenschmiede-Sync:** Die Kamera filmt zu Beginn und am Ende einen QR-Code auf dem iPhone. Ein Anker bestimmt den Zeitversatz; zwei oder mehr Anker erlauben zusätzlich eine lineare Driftkorrektur.
2. **DJI-Timecode/Dateimetadaten:** Beim Import werden Timecode-Track, Aufnahmezeit, Dauer und Bildrate gelesen, soweit die Datei diese Daten enthält.
3. **FIT für DJI Mimo:** Streckenschmiede exportiert die Fahrt als FIT-Datei, die DJI Mimo als Sportdatenquelle verwenden kann.
4. **DJI GPS Bluetooth Remote Controller:** Optionaler offizieller Weg für Kamera-Start/Stop und eigene GNSS-Daten. Die Streckenschmiede-Spur bleibt trotzdem die primäre Fahrtquelle.

Eine direkte BLE-/WLAN-Steuerung der Kamera aus Streckenschmiede ist kein P0-Versprechen. In den geprüften offiziellen DJI-Entwicklerunterlagen wurde kein öffentlich dokumentierter Action-5-Pro-SDK-Pfad gefunden. Vor proprietären Kommandos sind eine belastbare Protokollquelle, Lizenzprüfung und echte Hardwaretests erforderlich.

## Offizielle Fähigkeiten und Grenzen

- Die Action 5 Pro besitzt Timecode. Er kann zurückgesetzt, mit der Systemzeit oder über USB-C mit einem externen Timecode-Generator synchronisiert werden.
- DJI nennt unter anderem Tentacle Sync und DJI Mic 3 als Timecode-Quellen.
- Timecode steht bei Video über 60 fps nicht zur Verfügung.
- Im Pre-Rec-Modus unterstützt die Action 5 Pro keinen Timecode.
- Wird die Kamera mit DJI Mimo verbunden, synchronisiert Mimo Datum und Uhrzeit des Telefons; die Aufnahmezeit ist anschließend als Videometadatum verfügbar.
- Der DJI Osmo Action GPS Bluetooth Remote Controller steuert Aufnahme Start/Stop sowie Wake/Sleep und erfasst Multi-GNSS-Daten für DJI Mimo.
- DJI Mimo kann laut DJI Sportdaten aus Apple Health, Garmin Connect und FIT-Dateien importieren.

Diese Angaben müssen mit der tatsächlich verwendeten Firmware und Beispielclips erneut geprüft werden. Vor allem wird nicht angenommen, dass jede MP4-Datei der Kamera einen für AVFoundation lesbaren Timecode-Track enthält, bevor eine reale Datei dies bestätigt.

## Optisches Sync-Protokoll v1

Der Code wird mindestens vier Sekunden groß und kontrastreich im Vollbild gezeigt. Zusätzlich erscheinen UTC-Zeit, Fahrtzeit und eine kurze Fahrtkennung als lesbarer Text. Ein kurzer visueller Countdown hilft beim Ausrichten der Kamera.

Die implementierte Aufnahmeansicht verwendet drei Sekunden Vorlauf und danach
fünf vollständige Sekunden garantierte QR-Belichtung. Sie bleibt anschließend
offen, damit ein verspäteter Kamerastart den Anker nicht verliert. Systemleisten
werden ausgeblendet und das automatische Sperren wird nur für diese Ansicht
verhindert. Die optionale Maximalhelligkeit speichert den vorherigen Wert;
Helligkeit und Idle-Timer werden beim Schließen oder bei inaktiver App sofort
wiederhergestellt. „Noch einmal filmen“ wiederholt Vorlauf und Belichtung mit
demselben Nutzdatenanker.

Logischer Inhalt:

```text
version: 1
rideID: UUID der Fahrt
event: start | checkpoint | end
sequence: fortlaufende Nummer
utc: ISO-8601 mit Millisekunden
rideElapsedMs: monotone Fahrtzeit seit Sitzungsstart
latitudeE7/longitudeE7: optional
horizontalAccuracyCm: optional
payloadChecksum: gekürztes SHA-256 der kanonischen Nutzdaten
```

Der QR-Code verwendet hohe Fehlerkorrektur. Die präzise Position ist standardmäßig nicht erforderlich: `rideID`, UTC und Fahrtzeit verknüpfen das Video mit der lokal gespeicherten GPS-Spur. Eine Einstellung kann die aktuelle Position zusätzlich einbetten, wenn der Nutzer einen auch außerhalb der App interpretierbaren Anker möchte. In exportierten oder veröffentlichten Videos kann ein lesbarer QR-Code Standort und Zeit verraten; darauf weist die Oberfläche hin.

Die kanonische Prüfsummenfolge ist UTF-8 über die obigen neun Felder ohne
`payloadChecksum`, in genau dieser Reihenfolge und mit `|` getrennt. Fehlende
optionale Standortfelder sind leere Felder. Die Prüfsumme besteht aus den
ersten acht Byte des SHA-256-Digests als 16 kleingeschriebene Hex-Zeichen.
Version 1 verlangt eine kanonische kleingeschriebene UUID, UTC mit
Millisekunden, nichtnegative Sequenz/Fahrtzeit und entweder beide E7-
Koordinaten oder keine. Genauigkeit darf nur zusammen mit Koordinaten stehen.
Der feste CI-Testvektor und Manipulationstests verhindern unbemerkte
Formatänderungen; die spätere Vision-Pipeline muss denselben Decoder verwenden.

## Zuordnungsalgorithmus

1. Video aus Fotos, Dateien oder per OTG auswählen, ohne das Original ungefragt zu duplizieren.
2. Mit AVFoundation Dauer, Bildrate, Erstellungs-/Aufnahmedatum, Metadaten und vorhandene Timecode-Tracks lesen.
3. Mit Apple Vision QR-Codes in den ersten und letzten Abschnitten sowie optional in regelmäßigen Stichproben suchen.
4. Für jeden gültigen Code die Videopräsentationszeit `videoPTS` und die Fahrtzeit/UTC aus dem Payload erfassen.
5. Bei einem Anker nur den Offset bestimmen. Bei mindestens zwei Ankern eine robuste lineare Abbildung `rideTime = a × videoPTS + b` berechnen. `a` korrigiert die Kameradrift, `b` den Startversatz.
6. Ausreißer, falsche Fahrt-IDs und nicht monotone Anker ablehnen. Drift in ppm anzeigen und bei unplausiblen Werten eine manuelle Prüfung verlangen.
7. Position und Fahrwerte für einen Videoframe zeitlich aus der Fahrt interpolieren. Große GPS-Lücken werden nicht überspielt, sondern sichtbar markiert.
8. Die Verbindung als `RideVideoLink` speichern: Fahrt-ID, Medienreferenz, Offset, Drift, Anker, Qualitätsstufe und verwendete Metadaten. Das Video bleibt unverändert.

Qualitätsstufen:

- **Exakt:** mindestens zwei gültige optische/Timecode-Anker und plausible Drift.
- **Gut:** ein optischer Anker plus verlässliche Timecode-/Aufnahmezeit.
- **Einfach:** ein optischer Anker; Offset ohne Driftkorrektur.
- **Geschätzt:** nur Dateidatum/Dateiname; muss der Nutzer bestätigen.

## Bedienablauf

1. Fahrt in Streckenschmiede starten.
2. Aufnahme auf der Action 5 Pro oder dem offiziellen GPS-Remote starten.
3. In Streckenschmiede „Kamera synchronisieren“ öffnen und den Startcode 4–5 Sekunden filmen.
4. Optional während einer langen Fahrt einen Checkpoint filmen.
5. Vor oder nach dem Stoppen der Kamera den Endcode filmen.
6. Nach der Fahrt Video importieren. Streckenschmiede erkennt Codes, zeigt die Sync-Qualität und verbindet den Clip mit Karte und Messwerten.
7. Optional FIT exportieren und in DJI Mimo für das offizielle Sports Dashboard verwenden.

## Umzusetzende Einheiten

1. ✅ `CameraSyncPayload` mit kanonischer Kodierung, Prüfsumme, strikter
   Validierung, Datenschutzfällen und festem Referenzvektor.
2. 🟡 Vollbild-QR-Generator mit Start/Checkpoint/Ende, getestetem Countdown,
   fünf Sekunden Mindestbelichtung, Helligkeitsoption und Datenschutzschalter;
   Simulator-/Vision-Test sowie reale Action-5-Pro-Aufnahme stehen aus.
3. FIT-Export mit Fahrtzeit, Position, Höhe, Geschwindigkeit, Puls, Kadenz und Leistung, soweit vorhanden.
4. Videoimport und AVFoundation-Metadaten-/Timecode-Inspektion.
5. Vision-QR-Erkennung auf zeitlich begrenzten Videoframes.
6. Anker-Fit, Driftkorrektur, Qualitätsbewertung und manuelle Feinjustierung.
7. Verknüpfte Wiedergabe: Kartenposition und Fahrwerte folgen dem Video.
8. Optionaler gerenderter Daten-Overlay-Export; Originalvideo bleibt unverändert.
9. Direkte Kamerasteuerung nur nach dokumentierter, rechtlich nutzbarer Schnittstelle und Hardwareabnahme.

## Abnahmefälle

- 25, 30, 50 und 60 fps; 29,97 fps mit längerer Aufnahme.
- Über 60 fps und Pre-Rec ohne Timecode: QR-Fallback muss funktionieren.
- Starkes Sonnenlicht, Nacht, Bewegungsunschärfe, schräger Blickwinkel und verschmutztes Kameraglas.
- Ein fehlender Endcode, mehrere Checkpoints, mehrere Clips und automatische Dateisegmentierung.
- Wechsel von Zeitzone/Systemzeit während einer Fahrt darf monotone Fahrtzeit nicht beschädigen.
- GPS-Lücke, ungenaue Position und Video ohne Metadaten.
- Datenschutzmodus ohne Koordinaten im QR-Code.
- Reale Action-5-Pro-Dateien mit der beim Nutzer installierten Firmware.

## Primärquellen

- DJI Action 5 Pro Handbuch: <https://dl.djicdn.com/downloads/DJI_Osmo_Action_5_Pro/UM/20250523/DJI_Osmo_Action_5_Pro_User_Manual_v1.0_en.pdf>
- DJI Timecode-Hilfe: <https://repair.dji.com/help/content?customId=en-us03400007306&documentType=artical&lang=en&paperDocType=paper&re=US&spaceId=34>
- DJI Action 5 Pro Support/GPS Remote: <https://www.dji.com/support/product/osmo-action-5-pro>
- DJI Action 5 Pro Guide einschließlich Mimo-Sportdatenimport: <https://repair.dji.com/help/content?customId=en-us03400011286&documentType=artical&lang=en&paperDocType=paper&re=US&spaceId=34>
- Apple AVFoundation-Metadaten: <https://developer.apple.com/documentation/avfoundation/retrieving-media-metadata>
- Apple AVFoundation-Timecode: <https://developer.apple.com/library/archive/technotes/tn2310/_index.html>
- Apple Vision Barcode-Erkennung: <https://developer.apple.com/documentation/vision/vndetectbarcodesrequest>

