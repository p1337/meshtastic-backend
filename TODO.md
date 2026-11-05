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

- [x] Native iOS-Grund-App mit genau zwei Hauptreitern: **Outdoor** und **Indoor**.
- [x] Einfacher GPS-Track, Distanzberechnung und GPX-Export im Vordergrund.
- [x] GPX-Import und Darstellung einer importierten Strecke mit Start/Ziel in Apple MapKit.
- [x] Allgemeine BLE-Gerätesuche ohne Sensor-Dekodierung oder Trainersteuerung.
- [x] Vorhandene Werkbeleg-/LoRaLab-Signier- und OTA-Pipeline rekonstruiert; sie verwendet die drei bestehenden Secret-Namen und übernimmt Team und Bundle-ID aus dem vorhandenen Profil.
- [x] Fitmeter Bike anhand Herstellerseite, aktueller App-Store-Beschreibung und der bereitgestellten Referenzbilder als Mindestumfang ausgewertet.
- [x] Vorhandene ClickBridge-Arbeit in `origin/codex/clickbridge-ios` geprüft. Decoder, BLE-Lebenszyklus, Tests und Lizenzhinweise sollen wiederverwendet werden; die dort dokumentierte Hardwareabnahme ist weiterhin offen.

## P0 – verlässliche Fahrtaufzeichnung

- [~] `RideSessionEngine` ist als einzige Quelle für Start, Pause, Fortsetzen, Stop, Zeiten, Metriken und Wiederherstellung eingeführt; Compiler- und echter Relaunch-Test stehen noch aus.
- [~] Background-Location-Modus und fortlaufende GPS-Updates während einer gestarteten Fahrt sind konfiguriert; Freigabestufe „Immer“, energieangepasste Genauigkeit und echte Sperrbildschirm-Abnahme bleiben offen.
- [~] Core Location hält bei geöffneter App Live-Position, Tempo und Kurs dauerhaft aktuell, verarbeitet Autorisierungswechsel und Fehler-Callback und trennt die Live-Position von aufgezeichneten Trackpunkten; echter Relaunch-Test mit erteilter, verweigerter und ausgeschalteter Standortfreigabe bleibt offen.
- [ ] Aufzeichnung bei gesperrtem Display und App im Hintergrund testen.
- [~] Laufende Fahrt wird spätestens alle fünf Sekunden sowie bei Zustands-/App-Wechsel atomar zwischengespeichert; Wiederaufnahme oder GPX-Abschluss werden nach Relaunch angeboten. Echter Abbruch-/Telefonneustart-Test bleibt offen.
- [~] Alte, ungenaue, nicht monotone und über 126 km/h implizierende GPS-Punkte sowie Sprünge ab 300 m werden verworfen; Tunnel-/Empfangslücken und reale Grenzfälle bleiben zu testen.
- [~] GPS-Auto-Pause mit einstellbarer Geschwindigkeit und Verzögerung, Wiederanfahr-Hysterese sowie verbindlichem Vorrang der manuellen Pause ist implementiert und durch Zustandsmaschinentests belegt; echte Stop-and-go-, Hintergrund- und Tunnelabnahme fehlt.
- [~] Gesamtzeit, Fahrzeit sowie manuelle und automatische Pausenzeit werden getrennt geführt und im Cockpit angezeigt; echte Fahrtabnahme fehlt.
- [~] Erste GPS-Live-Werte: aktuelle, durchschnittliche und maximale Geschwindigkeit, Distanz, Zeit, Höhe sowie Auf-/Abstieg. Steigung, Kalorien, Herzfrequenz, Trittfrequenz, Leistung, Balance und Sensor-/Akkudaten bleiben offen.
- [ ] Datenherkunft je Wert sichtbar und testbar machen: Sensor, Apple Watch, GPS oder Schätzung.
- [ ] Einheiten km/mi, kg/lb, °C/°F und konfigurierbarer Radumfang.

## P0 – modernes Fahrt-Cockpit und Karten

- [~] Die beiden Hauptreiter heißen **Outdoor** und **Indoor** und verwenden eigene Template-Vektoren: Baum mit perspektivischer Strecke sowie Fahrrad-Vorderteil am dreieckigen Hometrainer-Ständer. Asset-Compiler- und echte Tabbar-Abnahme fehlen.
- [~] Bildschirmfüllende schwarze/orange Karten-Cockpitansicht beginnt oben und legt Live-Werte kompakt über die Karte; Anpassbarkeit, vollständige Dynamic-Type- und Geräteabnahme bleiben offen.
- [~] Das Kartenbild läuft hinter Status-/Top-Bereich weiter; Cockpit, Ebenenknopf und Pflichtaktionen müssen auf allen unterstützten Displaygrößen innerhalb sicherer, überlappungsfreier Bedienbereiche bleiben. Kleine-iPhone-Abnahme fehlt.
- [~] Eine breite, mindestens 64 Punkte hohe orange Haupttaste startet die Aufzeichnung ausdrücklich; GPS-Liveposition und Hilfswerkzeuge bleiben davon getrennt. Reale Handschuh- und Geräteabnahme steht aus.
- [ ] Anpassbare Datenfelder und mindestens drei speicherbare Cockpit-Layouts.
- [~] Live-Karte mit aktueller Position, gefahrenem Track und geplanter GPX-Linie im Fahrtbild; Abweichung und echte Navigation fehlen noch.
- [~] Gespeicherte Kartenwahl liegt ausschließlich in **Einstellungen > Fahrtkarte**, damit kein Ebenenknopf die Fahrkarte verdeckt: Apple Standard, Satellit und Hybrid sowie interaktives Online-OpenStreetMap und CyclOSM mit sichtbarer Attribution sind implementiert. OpenCycleMap ist als getrennte Thunderforest-Option vorhanden, bleibt ohne gültigen Provider-Key ausgeblendet; reale Geräte-, Last- und Sperrtestfahrt fehlen.
- [~] Kartenorientierung mit Norden oben, Fahrtrichtung oben und separat abschaltbarer geneigter 3D-Perspektive ist vorhanden; Stillstand, Kompassglättung und reale Geräteabnahme fehlen.
- [~] Follow-Modus mit eindeutigem Fadenkreuz-Zentrieren-Knopf unten mittig; Verschieben/Pinch schaltet auf freie Karte, Zentrieren stellt den Vorausblick mit Position im unteren Drittel wieder her. Reale Gestenabnahme steht aus.
- [~] Live-Karten-Zoom per Gesten und auf 84 Punkte beziehungsweise Faktor 1,5 vergrößerten Tasten: Minus unten links, Zentrieren unten mittig, Plus unten rechts; Standardbereich 250 m bis 10 km und Presets Nah/Fahrt/Voraus/Übersicht sind implementiert, reale Handschuhabnahme fehlt.
- [~] Puls, Kadenz, Leistung und Sensorakku stehen im oberen Daten-Cockpit; die untere Sensorleiste entfällt für mehr freie Kartenfläche. Reale Geräte- und Dynamic-Type-Abnahme fehlt.
- [~] Dauerhaft gespeicherter Live-Karten-Zoom und optionaler geschwindigkeitsabhängiger Auto-Zoom; manöverabhängiger Zoom fehlt.
- [~] Fahrtrichtung/Vorausblick setzt den orangefarbenen Positionspfeil durch einen weiter vorausliegenden Kartenmittelpunkt horizontal mittig in den unteren Kartenbereich; Kurs fällt auf Track- oder GPX-Richtung zurück. Der Vorausblick ist in 2D und besonders in 3D auf eine kleine, getestete Kameradistanz begrenzt, damit der Fahrer nicht hinter der Bedienleiste oder außerhalb des Bildschirms landet. Die 3D-Neigung wirkt auch im Stand ohne gültigen Fahrkurs. Glättung, Stillstandstest und echte Fahrabnahme fehlen.
- [~] Kartensteuerung und Navigationsbanner erhalten getrennte vertikale Bereiche. Minus, Zentrieren und Plus besitzen weiterhin 84-Punkte-Trefferflächen, erscheinen aber als ruhigere 58-Punkte-Kreise weiter unten. Die kontextabhängige untere Leiste zeigt während einer Fahrt keinen Teilen- oder Importknopf und integriert Start/Pause/Stop kompakt. Kleine iPhones, Dynamic Type und Handschuhe müssen real geprüft werden.
- [~] „An geplante Straße kleben“ ist standardmäßig aus und verändert eingeschaltet nur den sichtbaren Kartenpfeil innerhalb 50 m der aktiven Routengeometrie; Roh-GPS, Aufzeichnung und Abweichungsprüfung bleiben unverändert. Allgemeines Street-Matching ohne aktive Route benötigt einen regelkonformen Routing-/Map-Matching-Provider und bleibt offen.
- [ ] Bildschirm-Wachhalten optional, Helligkeits-/OLED-schonender Nachtmodus und Live Activity/Lock-Screen-Status.
- [ ] Dunkle **Live Activity** mit eigener Streckenschmiede-Gestaltung für eine laufende Fahrt: Lock Screen, Dynamic Island kompakt/minimal/erweitert, Distanz, Fahrzeit, Tempo, Pause/Aufzeichnung und genau eine sichere Schnellaktion. Sie startet nur mit einer Fahrt, endet zuverlässig bei Stop/Relaunch und zeigt keine private Route auf dem frei einsehbaren Sperrbildschirm.

## P0 – Routenplaner und Zielnavigation

- [~] Zielwahl über Apple-Adress-/POI-Suche ab aktueller GPS-Position ist implementiert; Favoriten, Kartenpunkt, Zwischenziele und Kontakte nach ausdrücklicher Freigabe fehlen.
- [ ] Zwischenziele hinzufügen, sortieren und entfernen.
- [ ] Profile: **Radwege bevorzugt**, **Ausgewogen**, **Straße/schnell**.
- [ ] Fahrradtypen: Rennrad, Gravel/Cross, City/Trekking, Mountainbike und E-Bike.
- [ ] Regler für Straßenanteil, Hügel, schlechte Oberflächen, Hauptstraßen, Fähren, Treppen und unbefestigte Wege.
- [~] Apple-MapKit-Fahrradrouting nutzt `.cycling`, Distanz, erwartete Zeit, Hinweise und verfügbare Alternativen; Regionsverfügbarkeit, echte Route und Fehlerfälle auf dem iPhone bleiben zu testen.
- [ ] OSM-basiertes Valhalla-Routing als austauschbaren Provider anbinden, damit Radweg-/Straßenanteil, Fahrradtyp, Untergrund und Hügel tatsächlich steuerbar sind.
- [ ] Keine Produktionsabhängigkeit von einem ungarantierten öffentlichen Test-Endpunkt; Server/Provider austauschbar konfigurieren.
- [~] Von Apple gelieferte Alternativrouten werden gemeinsam auf der Karte dargestellt, über große nummerierte Routenpunkte oder die Detailzeile ausgewählt und mit Distanz, Fahrzeit sowie Hinweisen verglichen; die Anzahl bleibt providerabhängig, Auf-/Abstieg und Untergrundhinweise fehlen.
- [~] Apple-Manöver, Entfernung zur nächsten Anweisung, Restdistanz und anteilige Restzeit werden kompakt über der Fahrtkarte angezeigt und durch Geometrietests belegt; Symbolklassifizierung, Höhenprofil, Sprache/Haptik und echte Fahrabnahme fehlen.
- [~] Querabstand zur Route wird laufend berechnet und ab 60 Metern sichtbar gewarnt; zeitliche Entprellung, akustische/haptische Warnung und kontrollierte Neuberechnung mit Erhalt der ursprünglichen Route fehlen.
- [ ] Sprachansagen und Apple-Watch-Haptik mit getrennten Lautstärke-/Hinweisoptionen.
- [ ] GPX-Route kann als Navigationsroute ohne Neuberechnung verfolgt oder auf das Wegenetz angepasst werden.
- [~] Die aktive Apple- oder GPX-Route samt Manövern wird versioniert, begrenzt und atomar lokal gespeichert, nach App-Neustart wiederhergestellt und kann ausdrücklich beendet werden; eine benannte Routenbibliothek und der echte Relaunch-/Navigationstest auf dem iPhone fehlen.
- [ ] Für Offline-Karten nur einen Provider oder eigene Vektorkacheln verwenden, der Offline-/Prefetch ausdrücklich erlaubt; `tile.openstreetmap.org` nicht vorladen.
- [ ] MapLibre-Native-Prototyp mit explizit offline erlaubten PMTiles/MBTiles; Gebiet, Zoomspanne, Größe, Fortschritt, Stand, Attribution und Löschen anzeigen.
- [ ] Umschaltbaren OSM-Fahrradstil erst nach eindeutiger Provider-, Lizenz-, Offline- und Kostenentscheidung integrieren; „OpenBikeMap“ ist als Anbieterbezeichnung zu präzisieren.

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

- [~] `SensorHub` unterstützt mehrere gleichzeitige Verbindungen, Wiederverbindung und Core-Bluetooth-State-Restoration; dauerhafte Zuordnung pro Fahrrad und echte Hardwareabnahme fehlen.
- [~] Heart Rate Service (`0x180D`): Puls, RR-Intervalle und Sensor-Kontaktstatus werden defensiv dekodiert; reale Brustgurt-/Watch-Abnahme fehlt.
- [~] Cycling Speed and Cadence Service (`0x1816`): Rad-/Kurbelumdrehungen, Geschwindigkeit und Trittfrequenz einschließlich Zeitüberlauf sind implementiert; Radumfang-Einstellung, Distanzquelle und Hardwaretest fehlen.
- [~] Cycling Power Service (`0x1818`): Leistung, Balance und optionale Rad-/Kurbelwerte werden dekodiert; Drehmoment-/Extremkraftfelder, Quellenwahl und Hardwaretest fehlen.
- [~] Fitness Machine Service (`0x1826`): Indoor-Bike-Livewerte, Target-Features, unterstützte Widerstands-/Steigungs-/Leistungsbereiche, Status und Control Point sind implementiert; zusätzliche FTMS-Messfelder und echte Hardwareabnahme fehlen.
- [~] Battery Service (`0x180F`) und Device Information Service (`0x180A`) werden gelesen und pro Gerät angezeigt; echte Geräteabnahme fehlt.
- [ ] Environmental Sensing (`0x181A`) für Temperatur und weitere für die Fahrt sinnvolle standardisierte Werte, falls vorhanden.
- [ ] Location and Navigation Service (`0x1819`) nur nach Capability-Prüfung; keine Doppelzählung gegenüber GPS/Route.
- [ ] Mehrere Sensoren desselben Typs unterstützen und pro Messgröße eine Priorität/Quelle auswählen lassen.
- [ ] Sensorverlust sichtbar melden und ohne Sprung auf die nächste erlaubte Quelle wechseln.
- [ ] Apple-Watch-Sensoren und direkt mit der Watch gekoppelte Fahrrad-Leistungs-/Kadenz-/Geschwindigkeitssensoren über die Workout-Session übernehmen.
- [ ] Reine ANT+-Geräte ehrlich als nicht nativ iPhone-kompatibel kennzeichnen; Unterstützung nur über BLE-Dualmodus oder einen konkret getesteten externen ANT+-BLE-Bridge-Adapter.
- [ ] Proprietäre Radar-, Licht-, Reifendruck-, E-Bike- und elektronische-Schaltsysteme über getrennte Adapter ergänzen, sobald öffentlich dokumentierte oder rechtlich nutzbare Protokolle und Testhardware vorliegen.
- [~] CI-Referenzvektoren prüfen Puls, RR, CSC, Leistung, Balance, FTMS-Livewerte, FTMS-Control-Point-Kommandos/-Antworten, Sicherheitsgrenzen und Batterie einschließlich gekürzter Pakete; physische Testmatrix fehlt.

## P0 – D100, Click V2 und Indoor-Training

- [~] Van Rysel D100 als FTMS-Trainer verbinden, Features und Werte auslesen; generischer FTMS-Pfad und explizite Trainerwahl sind implementiert, reale D100-Abnahme fehlt.
- [~] Exklusive FTMS-Steuerberechtigung wird angefordert, pro App nur einem gewählten Trainer zugeordnet und bei Status `0xFF`, fehlender Bestätigung oder Trennung verworfen; Wiedererlangen mit echter Hardware bleibt zu testen.
- [~] Widerstand, Ziel-Leistung/ERG und Steigung über Ziel-Inklination oder Indoor-Bike-Simulation werden nur bei gemeldeter Fähigkeit und innerhalb des Gerätebereichs gesendet; reale D100-Wirkung und Grenzwerte sind nicht abgenommen.
- [~] Ein Befehl gleichzeitig, fünf Sekunden Timeout, sichere Simulationsgrenze von −10 bis +15 Prozent und sichtbarer Not-Stopp sind implementiert; automatische Neutralstellung und reale Fehler-/Verbindungstests fehlen.
- [ ] ClickBridge-Core und -BLE aus `origin/codex/clickbridge-ios` mit Lizenzhinweisen in Streckenschmiede übernehmen, statt das Protokoll neu zu erfinden.
- [ ] Zwei Click V2 gleichzeitig, feste Links-/Rechts-Zuordnung, Batteriestand, Entprellen, lange Tastendrücke und Reconnect.
- [ ] Virtuelle Gänge mit konfigurierbarer Gangzahl/Übersetzung; Click verändert nur das Gangmodell, der Trainer-Controller bleibt alleiniger Eigentümer der D100-Kommandos.
- [ ] Linken Click über mindestens 60 Minuten auf den historisch dokumentierten firmwareabhängigen Ausfall testen.
- [~] Indoor-Cockpit zeigt Leistung, Kadenz, Herzfrequenz und FTMS-Steuerung für Widerstand/ERG/Steigung; Gang, Indoor-Zeit/Energie, Intervalle und anpassbare Felder fehlen.
- [ ] Strukturierte Workouts mit Warm-up, Intervallen, ERG, frei fahren und Cool-down.
- [ ] Trainingsplan-Bibliothek mit Vorlagen, selbst erstellbaren Einheiten, Kalender/Planfortschritt, Zielbereichen für Leistung, Puls und Kadenz sowie sicherer Pause/Fortsetzung.
- [ ] Indoor-„Geistfahrt“ gegen eine eigene gespeicherte Referenzfahrt: Fortschritt entlang derselben Distanz/Route, Zeitabstand, bisherige und aktuelle Leistung/Kadenz/Puls, persönliche Bestzeit und Datenschutz vollständig lokal; Trainerziele laufen weiterhin ausschließlich über `TrainerCore` und seine Sicherheitsgrenzen.

## P1 – Strecken, Historie, Statistik und Rekorde

- [ ] Persistente Streckenbibliothek mit Karten-Vorschau, Name, Distanz, erwarteter Zeit, Auf-/Abstieg und Auswahlstatus.
- [ ] Persistente Fahrtenhistorie mit Karten-Vorschau oder eigenem Foto, Datum, Distanz, Zeit, Durchschnitt, Höhe und Sensorzusammenfassung.
- [ ] Detailansicht mit Karte, Höhenprofil und Diagrammen über Zeit/Distanz für Geschwindigkeit, Herzfrequenz, Trittfrequenz und Leistung.
- [ ] Statistik nach Woche, Monat, Jahr und frei gewähltem Zeitraum.
- [ ] Rekorde und Gesamtsummen; Indoor/Outdoor, Fahrrad und Sensorquelle filterbar.
- [ ] Manuelle Fahrten ergänzen und bestehende Fahrten korrigieren, ohne rohe Originaldaten zu verlieren.
- [ ] iCloud-/Datei-Backup mit Konfliktstrategie und lokalem Betrieb ohne Konto.

## P1 – Import, Export und Teilen

- [~] Streckenschmiede als `com.topografix.gpx`-Dokument-App registrieren und GPX per „Öffnen mit“/Share Sheet aus WhatsApp, Dateien, Komoot und anderen Apps empfangen; Compiler- und echter App-zu-App-Test stehen aus.
- [ ] GPX 1.0/1.1 robust importieren/exportieren, inklusive Route, Track, Zeit und Höhe.
- [ ] FIT, TCX und CSV importieren/exportieren; unbekannte Felder erhalten, soweit praktikabel.
- [ ] Teilen als Datei und als datenschutzbewusste Karte/Bildzusammenfassung ohne Zwangskonto.
- [ ] Export-Validierung mit Roundtrip-Tests und unabhängigen Beispielwerkzeugen.
- [x] Komoot-, Offlinekarten-, GPX-Dateihandler- und Standortfreigabegrenzen in `Streckenschmiede/ROUTES_MAPS_INTEGRATIONS.md` dokumentiert.
- [ ] Komoot-Austausch zunächst ausschließlich über offiziellen GPX-Import/-Export und iOS Share Sheet; Kontosync nur mit offiziell vereinbarter Partner-API.

## P1 – optionale Musiksteuerung

- [~] Musiksteuerung ist standardmäßig aus und ausschließlich in **Einstellungen > Musik** aktivierbar. Im Outdoor-Cockpit erscheint danach nur ein kleiner Doppelnotenknopf; der dunkle Player mit Titel/Künstler sowie Zurück, Play/Pause und Weiter klappt als Sheet auf und belegt geschlossen keinen Kartenplatz. Der signierte Release-Build 75 kompiliert und paketiert diesen Stand erfolgreich; der echte Apple-Music-Gerätetest steht noch aus.
- [ ] Spotify App Remote als getrennten Adapter ergänzen. Voraussetzung sind eine registrierte Spotify-Developer-App, Client-ID, Redirect-URI, Spotify-App auf dem Gerät und ausdrückliche Autorisierung; keine Zugangsdaten im Repository.
- [ ] Amazon Music erst integrieren, wenn Amazon den Zugriff auf die derzeit geschlossene Beta freigibt, die App zertifiziert ist und eine belastbare iOS-Schnittstelle bereitsteht; keine undokumentierte Fernsteuerung.
- [ ] Eigenen lokalen Player für MP3/AAC/ALAC aus einem vom Nutzer gewählten Dateien-/iCloud-Drive-Ordner bauen: Security-Scoped Bookmark, Bibliotheksindex, Wiedergabeliste, Unterbrechungsbehandlung, Background Audio, Sperrbildschirm-/Headset-Steuerung und nachvollziehbarer Rechteentzug.
- [ ] Musiklautstärke und Navigationsansagen gegeneinander testen; Anweisungen dürfen Musik nur nach einer ausdrücklichen Einstellung absenken oder unterbrechen.

## P1 – Gruppenfahrt und freiwillige Live-Position

- [ ] Zeitlich begrenzte Fahrtgruppe per Einladungslink/QR, ausdrücklicher Beitritt und jederzeitiger Widerruf.
- [ ] Verschlüsselte Live-Positionen mit Zeit, Genauigkeit und optional Akku/ETA; veraltete oder ungenaue Werte sichtbar kennzeichnen.
- [ ] Automatische Löschung nach der Tour, Teilnehmer blockieren/entfernen und keine stille Standortfreigabe.
- [ ] Keine Auslese privater Google-Maps- oder Apple-„Wo ist?“-Positionen; nur eigene, dokumentierte Freigabe verwenden.
- [ ] Eigene Streckenschmiede-Gruppenfahrt als belastbaren Weg umsetzen: zeitlich begrenzte Einladung/QR oder Link, ausdrückliche Freigabe jedes Teilnehmers, verschlüsselte Übertragung, Ablaufzeit, Blockieren und sofortiges Beenden.
- [ ] Google-Maps-Orte und Routen nur über offizielle Maps-URLs öffnen/übergeben. Die Google-Maps-Standortfreigabe bietet derzeit keinen dokumentierten Drittanbieter-Livestream für Freunde; Freigabelinks dürfen höchstens ausdrücklich im Browser/Google Maps geöffnet, nicht automatisiert ausgelesen oder gescrapt werden.
- [ ] Apple „Wo ist?“ nicht als Personenquelle versprechen: Das öffentliche Find-My-Entwicklerprogramm dient MFi-Zubehör, nicht dem Auslesen der Standorte von Freunden/Familie. Eine spätere Apple-Integration nur nach einer ausdrücklich dokumentierten Personenfreigabe-API.

## P2 – Kamera und Medien

- [x] Erstes Kameramodell festgelegt: DJI Osmo Action 5 Pro. Offizielle Fähigkeiten für Timecode, GPS Bluetooth Remote Controller, Mimo und FIT-Import dokumentiert.
- [x] Unabhängiges Synchronisierungskonzept mit Start-/End-QR, optionalen Checkpoints, Timecode-/Metadaten-Fallback und Driftkorrektur in `Streckenschmiede/CAMERA_SYNC.md` festgelegt.
- [~] Vollbild-QR-Generator mit Fahrt-ID, UTC, monotoner Fahrtzeit, SHA-256-Prüfsumme und optionaler GPS-Position implementiert; Compiler-, Simulator-, Kamera- und Wiedererkennungstest stehen aus.
- [ ] QR zu Beginn und Ende filmen; ab zwei Ankern Offset und Kameradrift robust berechnen.
- [ ] Action-5-Pro-Video aus Fotos/Dateien/OTG importieren und Metadaten, Aufnahmedatum, Bildrate sowie Timecode-Track mit AVFoundation prüfen.
- [ ] QR-Codes mit Apple Vision aus Videoframes erkennen; fehlende/mehrdeutige Codes nachvollziehbar behandeln.
- [ ] `RideVideoLink` speichern und Video-Wiedergabe zeitlich mit Karte, GPS und Sensorwerten koppeln.
- [ ] FIT-Export für DJI Mimo mit Position, Höhe, Geschwindigkeit, Puls, Kadenz und Leistung, soweit vorhanden.
- [ ] DJI GPS Bluetooth Remote Controller als offiziell unterstützten externen Start-/Stop-/GNSS-Weg dokumentieren und mit echter Hardware testen.
- [ ] Geräte-API und Lizenz-/Netzwerkanforderungen weiter prüfen; keine geratenen Bluetooth-/WLAN-Kommandos senden. Direkte Streckenschmiede-Steuerung bleibt optional.
- [ ] Aufnahme starten/stoppen, Status, Akku und Speicher aus Streckenschmiede nur anzeigen/steuern, wenn das Gerät dies über eine belastbar nutzbare Schnittstelle erlaubt.
- [ ] Timecode-Grenzen testen: über 60 fps und Pre-Rec benötigen den optischen QR-Fallback.
- [ ] Kamerazeit und Fahrtzeit synchronisieren; Clips anhand der Fahrtposition referenzieren.
- [ ] Kameraausfall darf Fahrt, Navigation und Sensoraufzeichnung niemals beenden.

## P2 – RLV / Real-Life-Video

- [x] RLV-Formatlandschaft, portablen MP4+GPX-Korridor sowie Tacx-RLV/PGMF-Blöcke und Lizenzgrenzen in `Streckenschmiede/RLV_COMPATIBILITY.md` dokumentiert.
- [ ] Portable RLV-Paare importieren: gleichnamiges MP4/AVI plus GPX mit Zeit und Höhe; H.264/H.265 zuerst.
- [ ] Video-/GPX-Offset sowie Drift mit denselben QR-/Timecode-Ankern wie Action 5 Pro bestimmen.
- [ ] Tacx `.rlv`/`.pgmf` defensiv lesen, MIT-Hinweise erhalten und mit eigenen/lizenzierten Referenzdateien gegen Incyclist sowie GoldenCheetah prüfen.
- [ ] Steigungen ausschließlich über `TrainerCore`, FTMS-Fähigkeiten, Wertebereiche und Not-Stopp anwenden.
- [ ] Tacx-Export erst nach Roundtrip-Nachweis; fremde RLV-Videos nie ungefragt kopieren oder verteilen.

## Qualität, Datenschutz und Veröffentlichung

- [~] CI-Selbsttests decken Sitzungszustände, getrennte Zeiten, GPS-Sprungfilter, atomare Relaunch-Wiederherstellung, dauerhafte Vordergrund-Liveposition versus Hintergrund-Aufzeichnung, Auto-Pause einschließlich manuellem Vorrang, Routenfortschritt/Restwerte/Manöver/Querabstand, atomaren Roundtrip und Validierung der aktiven Route, ausschließlich sichere vollständig aufgelöste HTTPS-Kachel-URLs sowie BLE-/FTMS-Paketparser ab; Dateiformate und Routingprofile fehlen.
- [~] Der Apple-Build startet den Outdoor-Hauptreiter auf einem iPhone-Simulator mit gesetzter Testposition, erzeugt einen echten Screenshot und veröffentlicht ihn als Build-Artefakt sowie `ui-outdoor.png` zur visuellen Prüfung. Automatisierte Screenshots für Indoor, Einstellungen, Routenplaner, Navigation und Wiederherstellung fehlen.
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
- Bluetooth Fitness Machine Service 1.0.1: <https://www.bluetooth.com/specifications/specs/fitness-machine-service-1-0-1/>
- OSM-Kachelrichtlinie: <https://operations.osmfoundation.org/policies/tiles/>
