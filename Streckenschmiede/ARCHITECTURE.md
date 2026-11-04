# Streckenschmiede – Zielarchitektur

Stand: 4. November 2026. Dieses Dokument beschreibt die geplante Architektur. Der tatsächlich nachgewiesene Produktstand steht in [README.md](README.md), der verbindliche Arbeits- und Abnahmeplan in [../TODO.md](../TODO.md).

## Produktgrenzen

- Genau zwei Hauptreiter bleiben erhalten: **Aufzeichnung** und **Indoor-Training**.
- Routen, Historie, Statistiken, Sensoren und Einstellungen sind innerhalb dieser beiden Bereiche erreichbar und keine zusätzlichen Hauptreiter.
- Fitmeter Bike ist eine Funktions-Mindestlinie, keine Design- oder Codevorlage. Es werden weder fremder Code noch Texte, Grafiken oder Markenauftritt kopiert.
- Offline nutzbare Kernfunktionen, lokale Datenhaltung, kein Abo, kein Zwangskonto.
- „Fertig“ bedeutet nicht „kompiliert“, sondern angemessen auf echten Geräten, mit den betroffenen Sensoren und als signiertes OTA-Paket geprüft.

## Module und Eigentümer

| Modul | Verantwortung | Wichtige Grenze |
|---|---|---|
| `RideCore` | Sitzungszustand, Zeit, Auto-Pause, Metriken, Runden, Wiederherstellung | Keine UI- oder Bluetooth-Abhängigkeit |
| `LocationCore` | Core Location, Filterung, Spur, Höhe, Hintergrundbetrieb | Liefert Messpunkte; entscheidet nicht über Sensorpriorität |
| `SensorHub` | Scan, Pairing, mehrere Verbindungen, Parser, Reconnect, Quellenqualität | Gerätespezifische Adapter senden keine UI- oder HealthKit-Befehle |
| `TrainerCore` | FTMS-Eigentum, D100-Steuerung, ERG, Widerstand, Steigung, Sicherheitsgrenzen | Genau ein Besitzer des Trainer-Control-Points |
| `ClickBridgeCore` | Click-Protokoll, Links/Rechts, Tasten, virtuelle Gangwünsche | Sendet nie direkt Trainerkommandos |
| `RouteCore` | Zielsuche, Provider, Profile, Route, Manöver, Abweichung, Neuberechnung | Keine Bindung an einen einzelnen Karten- oder Routinganbieter |
| `MapUI` | Apple-/OSM-Darstellung, Overlays, Follow, Orientierung, Zoom | Zeichnet Routingresultate; berechnet keine Route selbst |
| `WorkoutCore` | HealthKit-Rechte, Workout-Eigentum, Watch-Spiegelung, Workout-Route | Verhindert doppelte HealthKit-Workouts |
| `Persistence` | Fahrten, Routen, Einstellungen, Sensorzuordnung, atomare Zwischenstände | Rohdaten bleiben erhalten; abgeleitete Werte sind neu berechenbar |
| `ImportExport` | GPX, FIT, TCX, CSV und Teilen | Parser isoliert und mit Referenzdateien testbar |
| `CameraAdapter` | Herstellerspezifische Kameraverbindung und Kommandos | Optional; Fehler beeinflussen Fahrt/Navigation nicht |
| `LiveGroupCore` | Freiwillige, zeitlich begrenzte Gruppenpositionen | Keine Google-/Find-My-Auslese; explizite Zustimmung, Widerruf und Ablauf sind Pflicht |

Die Oberfläche liest einen zusammengeführten, unveränderlichen `RideSnapshot`. GPS, Watch und Sensoren schreiben zeitgestempelte Rohmessungen in den jeweiligen Dienst. `RideCore` bestimmt anhand der konfigurierten Quellenpriorität und Qualität den angezeigten Wert. So werden weder Distanz noch Kalorien doppelt gezählt.

Ein einmaliger Core-Location-Abruf über `requestLocation()` wird nur mit beiden
Delegate-Pfaden betrieben: `didUpdateLocations` und `didFailWithError`. Das ist
ein Startpfad und deshalb Teil jedes Smoke-Tests mit bereits erteilter sowie
noch nicht erteilter Standortfreigabe.

## Sitzungs- und Datenmodell

Eine Fahrt hat eine stabile UUID und mindestens die Zustände `idle`, `preparing`, `recording`, `paused`, `finishing`, `finished` und `recoveryRequired`. Zustandswechsel werden vor Nebenwirkungen atomar gespeichert.

Persistente Hauptobjekte:

- `Ride`: Start/Ende, Typ indoor/outdoor, Gesamt-/Fahrt-/Pausenzeit, Summen, HealthKit-ID und Abschlussstatus.
- `TrackPoint`: Zeit, Position, Genauigkeit, Höhe, Geschwindigkeit und Quelle.
- `MetricSample`: Zeit, Messart, Wert, Einheit, Quelle, Qualität und Geräte-ID.
- `RoutePlan`: Start, Ziel, Zwischenziele, Provider, Profil, Geometrie, Manöver und Höhenprofil.
- `SavedRoute`: benannte Route, Vorschau, Statistik, Importursprung und optionale Fotos.
- `SensorBond`: stabile CoreBluetooth-ID, Geräteinformationen, Fahrrad, Rollen und Nutzervorrang.
- `BikeProfile`: Typ, Radumfang, Gewicht, E-Bike-Konfiguration, Sensoren und Routingpräferenzen.

SwiftData ist für Indizes und Metadaten vorgesehen. Große zeitliche Reihen werden kompakt und atomar dateibasiert gespeichert, damit eine lange Fahrt nicht durch tausende UI-Datenbankänderungen belastet wird. Ein migrationsfähiges Format und Roundtrip-Tests sind Pflicht, bevor produktive Daten entstehen.

## Metrik- und Quellenpriorität

Jede Messgröße besitzt eine eigene Priorität, keine pauschale „bestes Gerät“-Regel. Voreinstellung:

1. ausdrücklich vom Nutzer gewählter externer Sensor,
2. direkt an der Apple Watch erfasster standardisierter Fahrradsensor,
3. Apple-Watch-/HealthKit-Messung,
4. iPhone-GPS oder Barometer,
5. nachvollziehbar gekennzeichnete Schätzung.

Ein Wechsel erfolgt nur bei veralteter oder ungültiger Quelle und wird im Fahrtprotokoll markiert. Maximalwerte und Distanzen werden nicht aus zwei Quellen addiert. Berechnungen benutzen monotone Zeit, während Exporte die originale UTC-Zeit behalten.

## SensorHub und unterstützte Protokollklassen

`SensorHub` nutzt einen CoreBluetooth-Central mit State Preservation/Restoration. Ein Adapter wird erst nach Service-/Characteristic-Erkennung aktiviert. Geräte werden nicht nur anhand ihres Namens erraten.

| Klasse | BLE-Service | Zielumfang |
|---|---:|---|
| Herzfrequenz | `0x180D` | BPM, RR, Kontaktstatus |
| Geschwindigkeit/Kadenz | `0x1816` | Rad-/Kurbelereignisse, Geschwindigkeit, Distanz, Kadenz |
| Leistung | `0x1818` | Watt, Balance, Drehmoment, Rad-/Kurbelereignisse und Features |
| Fitness Machine | `0x1826` | Indoor-Bike-Daten, Status, Featurebereiche, Control Point |
| Batterie | `0x180F` | Ladezustand und Warnschwellen |
| Geräteinfo | `0x180A` | Hersteller, Modell, Firmware/Hardware, soweit vorhanden |
| Umgebung | `0x181A` | Temperatur und ausdrücklich unterstützte Umgebungswerte |
| Navigation | `0x1819` | standardisierte Navigationsdaten nur nach Capability-Prüfung |

Parser behandeln optionale Flags, Little Endian, Zählerüberläufe, Zeitüberläufe, fehlende Werte und ungültige Pakete explizit. Batterie- oder Geräteinformationsdienste können parallel zu jedem Messdienst vorliegen.

„Alle Fahrradsensoren“ bedeutet in der Basisschicht alle relevanten öffentlichen BLE-Standarddienste und eine erweiterbare Adapterarchitektur. Proprietäre Gerätefamilien wie manche Radar-, Licht-, Reifendruck-, E-Bike-, elektronische Schalt- und Kamera-Systeme benötigen jeweils dokumentierte Protokolle, Lizenzprüfung und echte Hardware. Reines ANT+ ist auf dem iPhone nicht nativ erreichbar; es braucht Dual-BLE oder einen getesteten Bridge-Adapter. Diese Grenzen werden in der UI sichtbar, nicht verschwiegen.

## D100 und Click V2

Der D100 wird über FTMS durch `TrainerCore` gesteuert. Vor jedem Control-Point-Kommando werden Support, Bereich, Schreibart und aktuelle Steuerberechtigung geprüft. Timeout, Verlust der Kontrolle und Not-Stopp gehen in einen sicheren Zustand.

Die vorhandene Arbeit aus `origin/codex/clickbridge-ios` ist die Ausgangsbasis für Click V2. Wiederzuverwenden sind insbesondere der strikte Wire-Decoder, zwei unabhängige Peripheral-Sitzungen, Zuordnung, Wiederherstellung, Diagnose und Tests. Fremdlizenzen und Quellenhinweise bleiben erhalten.

Click-Tasten erzeugen ausschließlich `GearIntent`-Ereignisse. Das virtuelle Gangmodell berechnet daraus ein Verhältnis; nur `TrainerCore` übersetzt dieses Verhältnis in ein erlaubtes FTMS-Ziel. Dadurch konkurrieren Click und Trainingsprogramm nicht um die Trainerverbindung.

## Apple Watch, HealthKit und Apple Fitness

`WorkoutCore` entscheidet vor Fahrtbeginn über genau einen Eigentümer:

- Mit geeigneter Apple Watch: primäre `HKWorkoutSession` auf watchOS, gespiegelte Session auf iOS. Start/Pause/Stop und Live-Werte bleiben synchron.
- Ohne Watch: primäre Workout-Session auf dem iPhone.

Gespeichert werden nach Freigabe ein Rad-Workout und eine zugeordnete `HKWorkoutRoute`. Zeitbezogene, tatsächlich verfügbare HealthKit-Typen umfassen aktive Energie, Fahrraddistanz, Herzfrequenz, Geschwindigkeit, Kadenz und Leistung. FTP wird von HealthKit/Watch gelesen oder nur nach Apples Regeln und belegbarer Quelle geschrieben. Auf-/Abstieg und weitere Zusammenfassungen werden als unterstützte Workout-Metadaten oder app-lokal gehalten, nicht in unpassende Datentypen gezwungen.

Apple Fitness erhält Drittanbieterfahrten über HealthKit-Workout- und Aktivitätsdaten. Es gibt keine erfundene direkte Fitness-Schreibschnittstelle. Abgelehnte HealthKit-Rechte sind normale Zustände; die Fahrt bleibt lokal funktionsfähig.

## Routing und Karten

`RouteProvider` liefert ein gemeinsames Modell aus Geometrie, Manövern, Distanz, Zeit, Höhenprofil, Warnungen und Providerhinweis.

- `AppleCyclingRouteProvider`: verwendet MapKit `.cycling`, wenn Betriebssystem und Region es unterstützen. Apple bietet dabei ein hochwertiges Fahrradprofil, aber keine Streckenschmiede-Regler für Straßenanteil oder Untergrund.
- `ValhallaRouteProvider`: OSM-basiert und für die verlangten Profile. `bicycle_type`, `use_roads`, `use_hills`, `avoid_bad_surfaces`, Fähren und weitere Optionen werden aus dem Bike-Profil abgeleitet.
- GPX-Provider: folgt der importierten Linie entweder unverändert oder lässt sie nach ausdrücklicher Wahl auf das Wegenetz anpassen.

Die Provider-URL ist konfigurierbar und nicht fest an einen öffentlichen Demo-Dienst gekoppelt. Produktionsbetrieb benötigt einen verlässlich betriebenen oder beauftragten Valhalla-Dienst.

GPX ist zugleich die erste Interoperabilitätsschicht zu WhatsApp, Dateien und Komoot. Die App registriert einen GPX-Dokumenttyp und verarbeitet externe Dokument-URLs über denselben Parser wie den Dateiauswahldialog. Eine Kontosynchronisation mit Komoot wird nicht aus undokumentierten Web-Endpunkten gebaut; bis zu einer offiziellen Partnervereinbarung bleibt es beim lokalen Dateiaustausch.

Kartenanzeige und Routing sind getrennt. Apple MapKit bleibt die sichere Standarddarstellung. Eine OSM-Darstellung benötigt sichtbare Attribution und einen geeigneten Vector-Tile-Anbieter oder eigene Kacheln. Die öffentlichen `tile.openstreetmap.org`-Server erlauben kein Offline-Prefetch und bieten keine Verfügbarkeitsgarantie; deshalb werden sie nicht als Offline-Backend verwendet.

### Zoom- und Follow-Modell

Zoom wird als sichtbare Breite/Höhe in Metern statt als anbieterspezifische Kachelstufe gespeichert. Voreinstellungen: **Nah**, **Fahrt**, **Vorausblick**, **Übersicht** und **Benutzerdefiniert**. Jede Ansicht kann ein eigenes Preset haben.

- Pinch/Scroll setzt `manualOverride` und pausiert automatisches Follow.
- Zentrieren aktiviert Follow erneut.
- Auto-Zoom darf Geschwindigkeit, Distanz zum nächsten Manöver und Routenkrümmung verwenden, bleibt abschaltbar.
- Fahrtrichtung oben nutzt geglätteten Kurs; bei Stillstand wird nicht unruhig gedreht.
- Im Vorausblick wird der Kartenmittelpunkt in Fahrtrichtung vor das Fahrrad verschoben. Bei gleichzeitig gedrehter Karte erscheint das Fahrrad dadurch unten mittig, ohne die tatsächliche GPS-Position zu verändern.
- Pflichtbedienelemente auf der Fahrkarte erhalten mindestens 52 × 52 Punkte; Zentrieren liegt unten mittig und aktiviert Follow erneut.

Offline- und Integrationsentscheidungen stehen ausführlich in [ROUTES_MAPS_INTEGRATIONS.md](ROUTES_MAPS_INTEGRATIONS.md). MapLibre/PMTiles ist die Zielrichtung für lokale Vektorkarten; öffentliche OSM-Standardkacheln werden nicht vorgeladen.

## Navigation

Die Navigation führt einen Fortschrittszeiger entlang der Route und berechnet Querabstand sowie plausiblen Vorwärtsfortschritt. GPS-Rauschen allein löst keine Neuberechnung aus. Eine anhaltende Abweichung erzeugt zuerst eine Warnung, dann – abhängig von der Einstellung – eine neue Route vom aktuellen Punkt zum nächsten sinnvollen Routenabschnitt oder Ziel.

Manöver werden auf iPhone, Apple Watch, optional per Sprache und Haptik ausgegeben. Sicherheitsrelevante Hinweise bleiben kurz; die Karte darf während der Fahrt keine kleinen Pflichtbedienelemente verlangen.

## Historie und Auswertung

Rohmessungen bleiben unverändert. Zusammenfassungen, Rekorde und Diagrammreihen werden versioniert abgeleitet und können nach Algorithmusänderungen neu berechnet werden. Karten-Vorschaubilder sind Cache, nicht Primärdaten. Löschen einer Fahrt ist ausdrücklich, rückgängig machbar soweit praktisch und entfernt zugehörige HealthKit-Daten nur nach separater Bestätigung und Berechtigung.

## Kamera

Verbindliches erstes Modell ist die **DJI Osmo Action 5 Pro**. Die detaillierte Entscheidung und das optische Protokoll stehen in [CAMERA_SYNC.md](CAMERA_SYNC.md).

Primär wird das Video nach der Fahrt mit der unabhängig aufgezeichneten Streckenschmiede-Spur verbunden. Ein gefilmter Start-QR liefert den Zeitversatz; ein Endcode oder weitere Checkpoints ermöglichen eine lineare Driftkorrektur. AVFoundation-Timecode und Aufnahmemetadaten sind zusätzliche Anker. FIT-Export ermöglicht den von DJI dokumentierten Import in Mimo.

Der optionale `CameraAdapter` darf weder Fahrt- noch Trainer-Session besitzen. Eine direkte Kamerasteuerung wird erst aktiviert, wenn eine offiziell dokumentierte oder anderweitig rechtlich nutzbare Schnittstelle und echte Hardwaretests vorliegen. Bis dahin ist der DJI GPS Bluetooth Remote Controller der offizielle Start-/Stop-/GNSS-Weg. Kameraereignisse verwenden immer monotone Fahrtzeit; Systemzeitänderungen dürfen die Zuordnung nicht zerstören.

Für Indoor-Real-Life-Video ist zunächst MP4 plus zeitgestempeltes, gleichnamiges GPX der portable Austauschweg. Tacx-RLV/PGMF ist eine zusätzliche Binärformatstufe und wird gemäß [RLV_COMPATIBILITY.md](RLV_COMPATIBILITY.md) nur mit defensivem Parser, Referenzdateien und Lizenzhinweisen ergänzt.

## Abnahme und Beweisführung

Jedes Modul erhält Unit- oder Referenzvektortests. Zusätzlich gelten:

1. reproduzierbarer Xcode-Projekt-/Paket-Build,
2. Simulator-Smoke-Test ohne erfundene Hardwareergebnisse,
3. echter iPhone-Test für Hintergrund/GPS/Bluetooth,
4. echte Watch-/HealthKit-Abnahme,
5. reale Sensor-/D100-/Click-Matrix,
6. signierte IPA mit gültigem eingebettetem Profil und Code-Signatur,
7. nach Deployment erneut abgerufene IPA, Manifest, Hash und funktionierender `itms-services`-Link.

### Release-Versionierung

Die von XcodeGen erzeugte `Info.plist` referenziert
`$(MARKETING_VERSION)` und `$(CURRENT_PROJECT_VERSION)` ausdrücklich. Der
signierte CI-Archivlauf setzt die Buildnummer auf die GitHub-Run-Nummer. Damit
ein OTA-Update nicht versehentlich wieder als Build `1` ausgeliefert wird,
müssen `release.json`, die öffentliche IPA und deren `Info.plist` nach jedem
Deployment dieselbe neue Versions-/Buildkombination ausweisen.

## Primärquellen für Entscheidungen

- Apple Multidevice Workouts: <https://developer.apple.com/documentation/healthkit/building-a-multidevice-workout-app>
- Apple Workout Route: <https://developer.apple.com/documentation/healthkit/creating-a-workout-route>
- Apple MapKit Cycling: <https://developer.apple.com/documentation/mapkit/mkdirectionstransporttype/cycling>
- Valhalla Route API: <https://valhalla.github.io/valhalla/api/route/api-reference/>
- Bluetooth Assigned Numbers: <https://www.bluetooth.com/specifications/assigned-numbers/>
- OpenStreetMap Tile Usage Policy: <https://operations.osmfoundation.org/policies/tiles/>

