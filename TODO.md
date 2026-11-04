## MQTT TODO

This is poorly structured and currently mostly private to @geeksville

## Misc geeksville todo

https://github.com/protocolbuffers/protobuf/releases/download/v3.15.8/protoc-3.15.8-linux-x86_64.zip
	"initializeCommand": "sudo apt-get update; sudo apt-get install -y openjdk-11-jdk python3-distutils; wget https://github.com/protocolbuffers/protobuf/releases/download/v3.15.8/protoc-3.15.8-linux-x86_64.zip -O /tmp/protoc.zip; cd /tmp; unzip protoc.zip; chmod a+x bin/protoc; sudo cp bin/protoc /usr/local/bin",

	"postCreateCommand": "git submodule update --init"

## RAK board

* rak wireless board, add support
* release bin
* add readme link

## device TODO

* DONE: fix "No suitable channel found for decoding, hash was 0xb1!" (not a bug, was configured as ham)
* suppress sleep (so is_router can work correctly) when we have an active mqtt connection.

## Service TODO

* expose recent messages
* find internal eventbus idea (coroutine based?)
* DONE geoJSON
* don't let untrusted users see $SYS
* don't decrypt duplicate messages
* add crashlytics
* add common exception catching wrappers
* setup cloud logging https://docs.spring.io/spring-cloud-gcp/docs/1.2.7.RELEASE/reference/html/#stackdriver-logging
* Use an internal eventbus to launch coroutines anytime we see a new cleartext message (Use this to refactor
  ToJSONDaemon and DBMaintenanceDaemon)
* DONE fix kermit docker containers
* DONE use my custom mqtt server (and passwords) as mqtt.meshtastic.org
* DONE hub.meshtastic.org for the web service
* DONE stop running ezdevice process on kermit (document process first)
* DONE run meshtastic backend on kermit
* DONE test on esp32
* DONE announce ready for brave users
* figure out how to do riot bridge
* figure out how to do global channel ids
* take break for RAK board tasks
* increase DNS interval for lug.geeksville and mqtt.meshtastic.org (to decrease # of DNS queries clients need to make)
* DONE change to java 11
* DONE setup mqtt.meshtastic.org and
* DONE use https://kotlinlang.org/docs/jvm-spring-boot-restful.html#explore-the-project-build-file
* DONE make kubernetes container - https://cloud.google.com/community/tutorials/kotlin-springboot-container-engine
* have server deduplicate redundant messages before publishing as cleartext
* REJECTED use a free GKE autopilot cluster
* make MQTT to pushover daemon - or just use https://github.com/jpmens/mqttwarn
  and https://dan.langille.org/2018/04/15/using-mtqq-to-create-a-notification-network-mosquitto-mqttwarn-hare-and-hared/
* APRS to MQTT daemon
* change meshub password and remove from build (to prevent impersonation)
* add crashlytics (or similar) with remote log viewing
* thank ttgo, discourse and intellij
* Unify model.Channel with android code!
* Split APRS and pushover MQTT daemons into their own projects
* Change to use "bootBuildImage" to create docker images
  per https://www.baeldung.com/dockerizing-spring-boot-application

## APRS TODO

* add a real ham radio flag
* http://www.aprs-is.net/javAPRSSrvr/
* http://www.aprs-is.net/Connecting.aspx

## Python TODO

* add test case of preencrypting in the python tool (and sending through a node that lacks keys)

## Android TODO

* Have android app serve as a MQTT forwarder if needed (by sending ToRadio.wants_mqtt)
* Give place in android app for users to select which channel they are sending on (and which channels they are watching)

## Device TODO

* In MQTT:onPublish use the global channel ID to find the PSK/channel - not the (much weaker) channel hash
* DONE leave encrypted messages as forwarded (need fixes on both tx and rx sides)
* DONE have sim provide a fake wifi connection status saying connected
* DONE don't start MQTT if we don't have wifi connected
* DONE have plugin send uplinks to mesh
* have plugin send downlinks from mesh
* DONE don't decrypt messages before uplinking them to MQTT (move out of plugin)
* make a named "GlobalPub" secondary channel, enable uplink (only) for that channel. Short name on purpose.
* add python option for --mqtt-enable, create publicuplink channel
* optionally send positions on the PublicUplink channel
* DONE attempt reconnect to server if internet connectivity changes
* DONE don't bother contacting server if we don't have any uplink/downlink channels
* DONE test on ESP32
* DONE no need for python gateway to web initially: because both the simulator and ESP32 can talk wifi directly
* if simmesh_name is set in preferences, create the MQTTSimInterface using that as the global channel_id
* figure out how to use MQTT for simulator mesh network, use a special simmesh_name global channel_id? (because this
  would allow all nodes in simnet_xxx to subscribe only to those packets)
* figure out legality of hosting public mqtt servers with chat msgs
* mqtt.meshtastic.org should have VERY basic auth at launch (to prevent abuse)
* DONE do initial development inside of portduino
* DONE do as much possible on the device side (so we can eventually just have ESP32 talk directly to server)
* DONE add mqtt_server to radio prefs
* eventually add a MQTTPacket on the ToRadio & FromRadio links
* LATER: an android gateway would be useful
# Streckenschmiede – verbindlicher Arbeitsplan

Stand: 4. November 2026. Dieses Dokument ist die verbindliche Produkt- und Abnahmeliste. Ein Haken bedeutet nur dann „fertig“, wenn die zugehörigen Nachweise im Repository oder in einem verlinkten CI-Lauf vorhanden sind. Ein Build allein ersetzt keinen Test auf einem echten iPhone und mit echter Hardware.

## Status

- `[ ]` offen
- `[~]` begonnen, aber noch nicht vollständig abgenommen
- `[x]` umgesetzt und für den angegebenen Umfang nachgewiesen
- `[?]` benötigt eine Geräte-, Konto- oder Produktentscheidung

## Bereits nachgewiesen

- [x] Native iOS-Grund-App mit genau zwei Hauptreitern: **Aufzeichnung** und **Indoor-Training**.
- [x] Einfacher GPS-Track, Distanzberechnung und GPX-Export im Vordergrund.
- [x] GPX-Import und Darstellung einer importierten Strecke mit Start/Ziel in Apple MapKit.
- [x] Allgemeine BLE-Gerätesuche ohne Sensor-Dekodierung oder Trainersteuerung.
- [x] Vorhandene Werkbeleg-/LoRaLab-Signier- und OTA-Pipeline rekonstruiert; sie verwendet die drei bestehenden Secret-Namen und übernimmt Team und Bundle-ID aus dem vorhandenen Profil.
- [x] Fitmeter Bike anhand Herstellerseite, aktueller App-Store-Beschreibung und der bereitgestellten Referenzbilder als Mindestumfang ausgewertet.
- [x] Vorhandene ClickBridge-Arbeit in `origin/codex/clickbridge-ios` geprüft. Decoder, BLE-Lebenszyklus, Tests und Lizenzhinweise sollen wiederverwendet werden; die dort dokumentierte Hardwareabnahme ist weiterhin offen.

## P0 – verlässliche Fahrtaufzeichnung

- [ ] `RideSessionEngine` als einzige Quelle für Start, Pause, Fortsetzen, Stop und Wiederherstellung einführen.
- [ ] Standortfreigabe „Immer“, Background-Location und energieangepasste GPS-Genauigkeit korrekt konfigurieren.
- [ ] Aufzeichnung bei gesperrtem Display und App im Hintergrund testen.
- [ ] Laufende Fahrt absturzsicher und atomar zwischenspeichern; nach App-/Telefonneustart Wiederaufnahme oder sauberen Abschluss anbieten.
- [ ] GPS-Ausreißer, alte Punkte, Tunnel-/Empfangslücken und unrealistische Sprünge filtern, ohne echte schnelle Abschnitte zu verlieren.
- [ ] Auto-Pause mit einstellbarer Geschwindigkeit und Zeit; manuelle Pause hat Vorrang.
- [ ] Gesamtzeit, Fahrzeit und Pausenzeit getrennt führen.
- [~] Erste GPS-Live-Werte: aktuelle, durchschnittliche und maximale Geschwindigkeit, Distanz, Zeit, Höhe sowie Auf-/Abstieg. Steigung, Kalorien, Herzfrequenz, Trittfrequenz, Leistung, Balance und Sensor-/Akkudaten bleiben offen.
- [ ] Datenherkunft je Wert sichtbar und testbar machen: Sensor, Apple Watch, GPS oder Schätzung.
- [ ] Einheiten km/mi, kg/lb, °C/°F und konfigurierbarer Radumfang.

## P0 – modernes Fahrt-Cockpit und Karten

- [~] Erste moderne schwarze/orange Cockpitansicht mit großen Live-Werten; Anpassbarkeit, vollständige Dynamic-Type- und Geräteabnahme bleiben offen.
- [ ] Anpassbare Datenfelder und mindestens drei speicherbare Cockpit-Layouts.
- [~] Live-Karte mit aktueller Position und gefahrenem Track im Fahrtbild; geplante Route und Abweichung fehlen noch.
- [ ] Kartenmodi: Standard, Satellit, Hybrid und OSM-basierte Darstellung mit sichtbarer Quellenangabe.
- [ ] Kartenorientierung: Norden oben, Fahrtrichtung oben und 3D-Perspektive.
- [~] Follow-Modus mit Zentrieren-Taste; Verschieben/Pinch schaltet auf freie Karte. Reale Gestenabnahme steht aus.
- [~] Live-Karten-Zoom per Gesten und Tasten sowie dauerhaft einstellbarer Standardbereich von 250 m bis 10 km; getrennte Presets fehlen.
- [~] Dauerhaft gespeicherter Live-Karten-Zoom und optionaler geschwindigkeitsabhängiger Auto-Zoom; manöverabhängiger Zoom fehlt.
- [ ] Bildschirm-Wachhalten optional, Helligkeits-/OLED-schonender Nachtmodus und Live Activity/Lock-Screen-Status.

## P0 – Routenplaner und Zielnavigation

- [ ] Zielwahl über Adresse/POI-Suche, Favoriten, Kartenpunkt, aktuelle Position und Kontakte nur nach ausdrücklicher Freigabe.
- [ ] Zwischenziele hinzufügen, sortieren und entfernen.
- [ ] Profile: **Radwege bevorzugt**, **Ausgewogen**, **Straße/schnell**.
- [ ] Fahrradtypen: Rennrad, Gravel/Cross, City/Trekking, Mountainbike und E-Bike.
- [ ] Regler für Straßenanteil, Hügel, schlechte Oberflächen, Hauptstraßen, Fähren, Treppen und unbefestigte Wege.
- [ ] Apple-MapKit-Fahrradrouting ab der unterstützten Betriebssystemversion hinter einer Verfügbarkeitsprüfung nutzen.
- [ ] OSM-basiertes Valhalla-Routing als austauschbaren Provider anbinden, damit Radweg-/Straßenanteil, Fahrradtyp, Untergrund und Hügel tatsächlich steuerbar sind.
- [ ] Keine Produktionsabhängigkeit von einem ungarantierten öffentlichen Test-Endpunkt; Server/Provider austauschbar konfigurieren.
- [ ] Mindestens zwei Alternativrouten mit Distanz, Fahrzeit, Auf-/Abstieg und Untergrundhinweisen vergleichen.
- [ ] Turn-by-turn-Manöver, Restdistanz, Restzeit, nächste Abbiegung und Höhenprofil anzeigen.
- [ ] Abweichung erkennen, akustisch/haptisch warnen und kontrolliert neu berechnen; ursprüngliche Route auf Wunsch behalten.
- [ ] Sprachansagen und Apple-Watch-Haptik mit getrennten Lautstärke-/Hinweisoptionen.
- [ ] GPX-Route kann als Navigationsroute ohne Neuberechnung verfolgt oder auf das Wegenetz angepasst werden.
- [ ] Routen und erforderliche Manöverdaten für eine begonnene Fahrt lokal speichern.
- [ ] Für Offline-Karten nur einen Provider oder eigene Vektorkacheln verwenden, der Offline-/Prefetch ausdrücklich erlaubt; `tile.openstreetmap.org` nicht vorladen.

## P0 – Apple Watch, HealthKit und Apple Fitness

- [ ] HealthKit-Capability, verständliche Zwecktexte und granulare Freigabeoberfläche ergänzen.
- [ ] watchOS-Begleit-App mit großen Live-Werten, Herzfrequenz, Start, Pause, Fortsetzen, Runde und Stop.
- [ ] Bei vorhandener Watch eine primäre `HKWorkoutSession` auf der Watch starten und zum iPhone spiegeln; ohne Watch eine iPhone-Workout-Session verwenden.
- [ ] Nie zwei Workouts für dieselbe Fahrt speichern; Session-Eigentümer und Wiederverbindung eindeutig behandeln.
- [ ] Outdoor- und Indoor-Radfahren korrekt unterscheiden.
- [ ] Workout und `HKWorkoutRoute` speichern, damit Strecke und Training in Apple Health/Fitness ankommen.
- [ ] Von HealthKit unterstützte Messreihen mit Zeitbezug speichern: aktive Energie, Fahrraddistanz, Herzfrequenz, Fahrradgeschwindigkeit, Trittfrequenz und Leistung.
- [ ] FTP lesen/anzeigen und nur dann schreiben, wenn Quelle und HealthKit-Regeln dies erlauben; keine erfundenen Werte.
- [ ] Gewicht, Alter und weitere notwendige Profildaten nur nach Freigabe lesen und ausschließlich für nachvollziehbare Berechnungen verwenden.
- [ ] Apple-Fitness-Integration über das gespeicherte HealthKit-Workout und die zulässigen Energie-/Trainingsdaten; keine direkte, nicht existierende „Fitness-API“ vortäuschen.
- [ ] HealthKit-Autorisierung, abgelehnte Einzelrechte, gesperrtes Gerät, Watch-Trennung und späteren Sync testen.

## P0 – Bluetooth- und Fahrradsensoren

- [ ] `SensorHub` mit mehreren gleichzeitigen Geräten, dauerhafter Zuordnung pro Fahrrad, Wiederverbindung und Zustandswiederherstellung.
- [ ] Heart Rate Service (`0x180D`): Puls, RR-Intervalle und Sensor-Kontaktstatus, soweit geliefert.
- [ ] Cycling Speed and Cadence Service (`0x1816`): Rad-/Kurbelumdrehungen, Geschwindigkeit, Distanz und Trittfrequenz mit Überlaufbehandlung.
- [ ] Cycling Power Service (`0x1818`): Leistung, Kadenz, Balance, Drehmoment- und Rad-/Kurbelwerte, soweit vom Sensor geliefert.
- [ ] Fitness Machine Service (`0x1826`): Indoor-Bike-Daten, Status, unterstützte Bereiche und Control Point.
- [ ] Battery Service (`0x180F`) und Device Information Service (`0x180A`).
- [ ] Environmental Sensing (`0x181A`) für Temperatur und weitere für die Fahrt sinnvolle standardisierte Werte, falls vorhanden.
- [ ] Location and Navigation Service (`0x1819`) nur nach Capability-Prüfung; keine Doppelzählung gegenüber GPS/Route.
- [ ] Mehrere Sensoren desselben Typs unterstützen und pro Messgröße eine Priorität/Quelle auswählen lassen.
- [ ] Sensorverlust sichtbar melden und ohne Sprung auf die nächste erlaubte Quelle wechseln.
- [ ] Apple-Watch-Sensoren und direkt mit der Watch gekoppelte Fahrrad-Leistungs-/Kadenz-/Geschwindigkeitssensoren über die Workout-Session übernehmen.
- [ ] Reine ANT+-Geräte ehrlich als nicht nativ iPhone-kompatibel kennzeichnen; Unterstützung nur über BLE-Dualmodus oder einen konkret getesteten externen ANT+-BLE-Bridge-Adapter.
- [ ] Proprietäre Radar-, Licht-, Reifendruck-, E-Bike- und elektronische-Schaltsysteme über getrennte Adapter ergänzen, sobald öffentlich dokumentierte oder rechtlich nutzbare Protokolle und Testhardware vorliegen.
- [ ] Sensor-Simulatoren und Referenzvektoren für Parser; physische Testmatrix für mindestens Puls, CSC, Leistung und FTMS.

## P0 – D100, Click V2 und Indoor-Training

- [ ] Van Rysel D100 als FTMS-Trainer verbinden, Features und Werte auslesen.
- [ ] Exklusive FTMS-Steuerberechtigung sauber anfordern, verlieren und wiedererlangen.
- [ ] Widerstand, Ziel-Leistung/ERG und simulierte Steigung innerhalb der vom Trainer gemeldeten Grenzen steuern.
- [ ] Sicherheitsgrenzen, Timeout, Neutralstellung und sichtbaren Not-Stopp implementieren.
- [ ] ClickBridge-Core und -BLE aus `origin/codex/clickbridge-ios` mit Lizenzhinweisen in Streckenschmiede übernehmen, statt das Protokoll neu zu erfinden.
- [ ] Zwei Click V2 gleichzeitig, feste Links-/Rechts-Zuordnung, Batteriestand, Entprellen, lange Tastendrücke und Reconnect.
- [ ] Virtuelle Gänge mit konfigurierbarer Gangzahl/Übersetzung; Click verändert nur das Gangmodell, der Trainer-Controller bleibt alleiniger Eigentümer der D100-Kommandos.
- [ ] Linken Click über mindestens 60 Minuten auf den historisch dokumentierten firmwareabhängigen Ausfall testen.
- [ ] Indoor-Cockpit mit Leistung, Kadenz, Herzfrequenz, Gang, Widerstand, Zeit, Energie und Intervallen.
- [ ] Strukturierte Workouts mit Warm-up, Intervallen, ERG, frei fahren und Cool-down.

## P1 – Strecken, Historie, Statistik und Rekorde

- [ ] Persistente Streckenbibliothek mit Karten-Vorschau, Name, Distanz, erwarteter Zeit, Auf-/Abstieg und Auswahlstatus.
- [ ] Persistente Fahrtenhistorie mit Karten-Vorschau oder eigenem Foto, Datum, Distanz, Zeit, Durchschnitt, Höhe und Sensorzusammenfassung.
- [ ] Detailansicht mit Karte, Höhenprofil und Diagrammen über Zeit/Distanz für Geschwindigkeit, Herzfrequenz, Trittfrequenz und Leistung.
- [ ] Statistik nach Woche, Monat, Jahr und frei gewähltem Zeitraum.
- [ ] Rekorde und Gesamtsummen; Indoor/Outdoor, Fahrrad und Sensorquelle filterbar.
- [ ] Manuelle Fahrten ergänzen und bestehende Fahrten korrigieren, ohne rohe Originaldaten zu verlieren.
- [ ] iCloud-/Datei-Backup mit Konfliktstrategie und lokalem Betrieb ohne Konto.

## P1 – Import, Export und Teilen

- [ ] GPX 1.0/1.1 robust importieren/exportieren, inklusive Route, Track, Zeit und Höhe.
- [ ] FIT, TCX und CSV importieren/exportieren; unbekannte Felder erhalten, soweit praktikabel.
- [ ] Teilen als Datei und als datenschutzbewusste Karte/Bildzusammenfassung ohne Zwangskonto.
- [ ] Export-Validierung mit Roundtrip-Tests und unabhängigen Beispielwerkzeugen.

## P2 – Kamera und Medien

- [?] Exaktes Kameramodell und gewünschte Aktionen festlegen. Ohne Modell/Protokoll ist eine echte Steuerung nicht seriös implementierbar.
- [ ] Geräte-API und Lizenz-/Netzwerkanforderungen prüfen; keine geratenen Bluetooth-/WLAN-Kommandos senden.
- [ ] Verbinden, Aufnahme starten/stoppen, Status, Akku und Speicher anzeigen, soweit das Gerät dies offiziell erlaubt.
- [ ] Kamerazeit und Fahrtzeit synchronisieren; Clips anhand der Fahrtposition referenzieren.
- [ ] Kameraausfall darf Fahrt, Navigation und Sensoraufzeichnung niemals beenden.

## Qualität, Datenschutz und Veröffentlichung

- [ ] Swift-Unit-Tests für Metriken, Auto-Pause, GPX/FIT/TCX, Sensorparser, Routingprofile und Persistenz.
- [ ] UI-/Simulator-Smoke-Test für beide Hauptreiter, Einstellungen, Historie, Routenplaner und Wiederherstellung.
- [ ] Reale iPhone-Testfahrten: mindestens 30 und 120 Minuten, Display an/aus, Hintergrund, Telefonat, Bluetooth-Abbruch, GPS-Lücke und Akkumessung.
- [ ] Reale Watch-Testfahrt mit gespiegelter Session und anschließendem Health-/Fitness-Nachweis.
- [ ] Barrierefreiheit, VoiceOver, Kontrast, Dynamic Type und Bedienung mit Handschuhen prüfen.
- [ ] Standort- und Gesundheitsdaten standardmäßig lokal; kein Tracker, keine Werbung, kein Zwangskonto.
- [ ] OSM-Attribution und Providerbedingungen in Karte, App und Dokumentation einhalten.
- [ ] Signierter Geräte-Build mit Apple-Code-Signatur, eingebettetem gültigem Profil und arm64 unabhängig prüfen.
- [ ] OTA-Manifest, IPA-URL, HTTPS-Abruf, Hash und Installationslink auf GitHub Pages nach Deployment erneut abrufen und prüfen.
- [ ] Keine Erfolgsmeldung für Gesamtumfang vor echter Geräte-, Sensor-, HealthKit-, Signatur- und OTA-Abnahme.

## Technische Primärquellen

- Fitmeter-Mindestumfang: <https://fitmeter.net/bike/> und <https://apps.apple.com/de/app/fitmeter-bike-fahrrad-tacho/id1088672024>
- Apple Workout/Watch-Spiegelung: <https://developer.apple.com/documentation/healthkit/building-a-multidevice-workout-app>
- HealthKit-Workout-Route: <https://developer.apple.com/documentation/healthkit/creating-a-workout-route>
- HealthKit-Fahrradwerte: <https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier>
- Apple MapKit Fahrradrouting: <https://developer.apple.com/documentation/mapkit/mkdirectionstransporttype/cycling>
- Valhalla-Routingprofile: <https://valhalla.github.io/valhalla/api/route/api-reference/>
- Bluetooth-SIG Assigned Numbers: <https://www.bluetooth.com/specifications/assigned-numbers/>
- OSM-Kachelrichtlinie: <https://operations.osmfoundation.org/policies/tiles/>
