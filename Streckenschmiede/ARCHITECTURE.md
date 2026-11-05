# Streckenschmiede – Zielarchitektur

Stand: 4. November 2026. Dieses Dokument beschreibt die geplante Architektur. Der tatsächlich nachgewiesene Produktstand steht in [README.md](README.md), der verbindliche Arbeits- und Abnahmeplan in [../TODO.md](../TODO.md).

## Produktgrenzen

- Genau zwei Hauptreiter bleiben erhalten: **Outdoor** und **Indoor**.
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

Der Core-Location-Pfad verarbeitet immer beide Delegate-Ausgänge:
`didUpdateLocations` und `didFailWithError`. Autorisierungswechsel starten oder
beenden den passenden Modus ausdrücklich; verweigerte oder ausgeschaltete
Ortung darf weder abstürzen noch eine Fahrt vortäuschen.

Die Kartenposition ist kein Nebenprodukt einer laufenden Fahrt. Mit erteilter
Freigabe verwendet die aktive App kontinuierliche Vordergrund-Updates, damit
Position, Kurs und Vorausblick schon vor „Start“ und während manueller Pause
aktuell bleiben. Nur `RideSessionPhase.recording` schreibt Trackpunkte. Während
einer automatischen Pause bleibt die Ortung auch im Hintergrund aktiv, damit
echte Bewegung die Fahrt wieder starten kann; eine manuelle Pause tut dies nie.
Eine inaktive App ohne laufende oder automatisch pausierte Aufzeichnung beendet
Updates, damit „Live-GPS“ nicht unbemerkt dauerhaft Akku verbraucht.
Diese drei Modi (`foregroundLive`, `recordingBackground`, `off`) werden als
reine Policy mit Referenztests abgesichert.

## Sitzungs- und Datenmodell

Eine Fahrt hat eine stabile UUID und mindestens die Zustände `idle`, `preparing`, `recording`, `paused`, `finishing`, `finished` und `recoveryRequired`. Zustandswechsel werden vor Nebenwirkungen atomar gespeichert.

Der erste `RideSessionEngine`-Stand besitzt allein die Zustandsübergänge und
berechnet Gesamt-, Fahrt- und Pausenzeit. Er schreibt `active-ride-v1.json`
atomar in den Application-Support-Bereich: sofort bei jedem Zustandswechsel,
beim Wechsel der App in den Hintergrund und während der Fahrt spätestens alle
fünf Sekunden. Eine beim Start gefundene offene oder noch nicht exportierte
Sitzung wird `recoveryRequired`; die Oberfläche bietet Fortsetzen oder einen
sauberen GPX-Abschluss an. Die aktuelle JSON-Gesamtsicherung ist ein
migrationsfähiger MVP. Vor sehr langen produktiven Aufzeichnungen wird die
Punktreihe in das vorgesehene append-orientierte kompakte Format getrennt.

`AutoPauseController` ist eine getrennt getestete Zustandsmaschine vor dem
Session-Engine: anhaltende GPS-Geschwindigkeit unter der einstellbaren Schwelle
pausiert erst nach der gewählten Verzögerung. Fortgesetzt wird oberhalb einer
höheren Schwelle, damit GPS-Rauschen nicht flattert. Die Zustandsmaschine kennt
einen manuellen Besitzer; Bewegung und Einstellungsänderungen dürfen eine
manuelle Pause niemals aufheben. BLE-/Watch-Geschwindigkeit folgt erst mit der
dokumentierten Quellenpriorität und ersetzt bis dahin nicht stillschweigend GPS.

Persistente Hauptobjekte:

- `Ride`: Start/Ende, Typ indoor/outdoor, Gesamt-/Fahrt-/Pausenzeit, Summen, HealthKit-ID und Abschlussstatus.
- `TrackPoint`: Zeit, Position, Genauigkeit, Höhe, Geschwindigkeit und Quelle.
- `MetricSample`: Zeit, Messart, Wert, Einheit, Quelle, Qualität und Geräte-ID.
- `RoutePlan`: Start, Ziel, Zwischenziele, Provider, Profil, Geometrie, Manöver und Höhenprofil.
- `SavedRoute`: benannte Route, Vorschau, Statistik, Importursprung und optionale Fotos.
- `SensorBond`: stabile CoreBluetooth-ID, Geräteinformationen, Fahrrad, Rollen und Nutzervorrang.
- `BikeProfile`: Typ, Radumfang, Gewicht, E-Bike-Konfiguration, Sensoren und Routingpräferenzen.

SwiftData ist für Indizes und Metadaten vorgesehen. Große zeitliche Reihen werden kompakt und atomar dateibasiert gespeichert, damit eine lange Fahrt nicht durch tausende UI-Datenbankänderungen belastet wird. Ein migrationsfähiges Format und Roundtrip-Tests sind Pflicht, bevor produktive Daten entstehen.

Die erste aktive Navigation verwendet `RoutePlanStore`: Apple- und GPX-Pläne
werden als versionierter, größen- und punktbegrenzter JSON-Umschlag atomar in
`Application Support/Streckenschmiede/active-route-v1.json` geschrieben. Beim
App-Start wird ausschließlich ein validierter Plan wiederhergestellt. Das
sichtbare X beendet die Navigation und entfernt diese Sicherung; sie ist noch
keine benannte Routenbibliothek und ersetzt nicht die spätere SwiftData-Struktur.

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

Der erste `SensorHub`-Stand scannt bewusst allgemein, aktiviert Adapter aber
erst nach GATT-Dienst-/Merkmalserkennung. Er hält mehrere `CBPeripheral`-Sitzungen
parallel, verwendet einen Restore-Identifier und versucht nur ausdrücklich
gewünschte Verbindungen nach einem unerwarteten Abbruch erneut. Live unterstützt
er Heart Rate Measurement, CSC Measurement, Cycling Power Measurement, FTMS
Indoor Bike Data, Battery Level sowie Hersteller/Modell aus Device Information.
Rad-/Kurbelzähler und deren 1/1024-Sekunden-Zeitbasis werden je Gerät getrennt
geführt. Noch nicht festgelegte Quellenpriorität darf diese ersten Livewerte
nicht später ungeprüft in Fahrtstrecke oder HealthKit doppelt einrechnen.

„Alle Fahrradsensoren“ bedeutet in der Basisschicht alle relevanten öffentlichen BLE-Standarddienste und eine erweiterbare Adapterarchitektur. Proprietäre Gerätefamilien wie manche Radar-, Licht-, Reifendruck-, E-Bike-, elektronische Schalt- und Kamera-Systeme benötigen jeweils dokumentierte Protokolle, Lizenzprüfung und echte Hardware. Reines ANT+ ist auf dem iPhone nicht nativ erreichbar; es braucht Dual-BLE oder einen getesteten Bridge-Adapter. Diese Grenzen werden in der UI sichtbar, nicht verschwiegen.

## D100 und Click V2

Der D100 wird über FTMS durch `TrainerCore` gesteuert. Vor jedem Control-Point-Kommando werden Support, Bereich, Schreibart und aktuelle Steuerberechtigung geprüft. Timeout, Verlust der Kontrolle und Not-Stopp gehen in einen sicheren Zustand.

Der erste vertikale Steuerpfad trennt das reine, referenzvektorgeprüfte
`FTMSControl`-Codec vom Core-Bluetooth-Transport in `SensorHub`. Ein Nutzer
wählt genau einen verbundenen FTMS-Trainer als Kommandobesitzer. Der Control
Point `0x2AD9` wird erst nach aktivierten Indikationen freigegeben. Jeder Befehl
wartet exklusiv auf die zugehörige `0x80`-Antwort; nach fünf Sekunden, einem
Schreibfehler, Trennung oder Fitness-Machine-Status `0xFF` werden laufender
Befehl und Steuerberechtigung verworfen. Widerstand (`0x04`), Ziel-Leistung
(`0x05`) und Ziel-Inklination (`0x03`) benutzen die gelesenen Bereichsmerkmale.
Indoor-Bike-Simulation (`0x11`) ist zusätzlich auf −10 bis +15 Prozent
begrenzt. Start, Pause und Stopp werden niemals als erfolgreich angezeigt,
bevor der Trainer sie bestätigt. Diese Stufe ist noch kein D100-Hardwarebeweis;
automatische Neutralstellung und physische Fehlerfälle bleiben Teil der
Geräteabnahme. Bei weiterem Ausbau wandert die Zustandsmaschine hinter die
bereits definierte `TrainerCore`-Grenze; `SensorHub` bleibt BLE-Transport.

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

Der erste vertikale RouteCore-Pfad bleibt innerhalb des Aufzeichnungsbereichs:
Eine MapKit-Suche löst Adresse oder POI auf, die aktuelle GPS-Position ist der
Start und `MKDirections` fordert `.cycling` mit Alternativrouten an. Angezeigt
werden tatsächliche Distanz, erwartete Zeit, Providerhinweise und die von Apple
gelieferten Alternativen gemeinsam auf derselben Karte. Große nummerierte
Routenpunkte und die zugehörigen Detailzeilen ändern dieselbe Auswahl; erst die
ausdrückliche Bestätigung übernimmt die
Polyline in das gemeinsame Kartenmodell; dadurch erscheint sie identisch auf
Apple-, OSM- und CyclOSM-Ebenen. Apple bietet keine Streckenschmiede-Regler für
Gravel, Untergrund oder Straßenanteil; diese bleiben der getrennten Valhalla-
Stufe vorbehalten und werden nicht simuliert.

Die ausgewählte Route wird als providerneutrales `RideRoutePlan` aus Punkten,
Distanz, Zeit und geordneten `RouteManeuver`-Anweisungen gehalten. Der reine,
getestete `NavigationProgressEngine` projiziert die Live-Position auf das
nächste Routensegment und liefert Fortschritt, Restdistanz, anteilige Restzeit,
nächstes Manöver und Querabstand. Die erste Oberfläche warnt ab 60 Metern
sichtbar. Dieser Einzelpositions-MVP ersetzt noch keine zeitlich entprellte
Abweichungslogik: Haptik, Sprache und Neuberechnung dürfen erst auf einem
zustandsbehafteten Fortschrittszeiger aufbauen, der Kreuzungen und Rücksprünge
bei GPS-Rauschen sicher behandelt.

Die Provider-URL ist konfigurierbar und nicht fest an einen öffentlichen Demo-Dienst gekoppelt. Produktionsbetrieb benötigt einen verlässlich betriebenen oder beauftragten Valhalla-Dienst.

GPX ist zugleich die erste Interoperabilitätsschicht zu WhatsApp, Dateien und Komoot. Die App registriert einen GPX-Dokumenttyp und verarbeitet externe Dokument-URLs über denselben Parser wie den Dateiauswahldialog. Eine Kontosynchronisation mit Komoot wird nicht aus undokumentierten Web-Endpunkten gebaut; bis zu einer offiziellen Partnervereinbarung bleibt es beim lokalen Dateiaustausch.

Kartenanzeige und Routing sind getrennt. Apple MapKit bleibt die sichere Standarddarstellung. Eine OSM-Darstellung benötigt sichtbare Attribution und einen geeigneten Vector-Tile-Anbieter oder eigene Kacheln. Die öffentlichen `tile.openstreetmap.org`-Server erlauben kein Offline-Prefetch und bieten keine Verfügbarkeitsgarantie; deshalb werden sie nicht als Offline-Backend verwendet.

Die erste Online-Ebenenstufe verwendet einen ausschließlich in den Einstellungen
liegenden, gespeicherten Kartenwähler. Dadurch verdeckt auf der Fahrtkarte kein
Ebenenknopf die Route oder Fahrposition. Apple Standard, Satellit und Hybrid bleiben native MapKit-Stile.
OpenStreetMap Carto wird ausschließlich für die gerade sichtbare interaktive
Ansicht über einen identifizierten, HTTP-Cache-Regeln respektierenden Client
geladen, zeigt die Attribution dauerhaft und bietet keinerlei Prefetch oder
Offline-Download. CyclOSM nutzt denselben begrenzten Client als offene,
fahrradorientierte Online-Ebene und bleibt technisch sowie namentlich von
OpenCycleMap getrennt. OpenCycleMap ist als Thunderforest-Ebene
vorbereitet, aber ohne einen 32-stelligen gültigen Provider-Key deaktiviert.
Ein Schlüssel wird nie in Git eingecheckt; Kosten- und Kontowahl bleiben eine
explizite Produktentscheidung.

### Zoom- und Follow-Modell

Zoom wird als sichtbare Breite/Höhe in Metern statt als anbieterspezifische Kachelstufe gespeichert. Voreinstellungen: **Nah**, **Fahrt**, **Vorausblick**, **Übersicht** und **Benutzerdefiniert**. Jede Ansicht kann ein eigenes Preset haben.

- Pinch/Scroll setzt `manualOverride` und pausiert automatisches Follow.
- Zentrieren aktiviert Follow erneut.
- Auto-Zoom darf Geschwindigkeit, Distanz zum nächsten Manöver und Routenkrümmung verwenden, bleibt abschaltbar.
- Fahrtrichtung oben nutzt geglätteten Kurs; bei Stillstand wird nicht unruhig gedreht.
- Die Fahrtkarte füllt die verfügbare Aufzeichnungsfläche bis an den oberen Bildschirmrand. Messwerte und Fahrtaktionen liegen als kompakte kontrastreiche Overlays darauf; es gibt keine separate dauerhaft sichtbare „Bereit“- oder GPS-Punkt-Zeile.
- Live-GPS und Aufzeichnung sind auch in der Bedienung getrennt: Eine breite orange Haupttaste „Aufzeichnung starten“ beginnt erst die Speicherung. Import, Kamera und Teilen stehen in einer eigenen Werkzeugzeile und dürfen die Starttaste nicht zusammendrücken.
- Im Vorausblick wird der Kartenmittelpunkt so weit in Fahrtrichtung vor das Fahrrad verschoben, dass der Positionspfeil horizontal mittig bei ungefähr zwei Dritteln der Bildschirmhöhe, also ein Drittel über dem unteren Rand, erscheint, ohne die tatsächliche GPS-Position zu verändern. Weil `MKMapCamera.distance` nicht der sichtbaren Kartenhöhe entspricht, begrenzt `MapCameraPolicy` den Versatz auf 16 % in 2D und 12 % in der geneigten 3D-Ansicht; größere frühere Werte konnten den Fahrer aus dem Bildschirm schieben. Fehlt ein aktueller Kurs, dienen zuletzt gefahrene Spur oder nächste GPX-Richtung als Fallback. Eine separat gespeicherte 3D-Option steuert die Neigung.
- Die untere Kartensteuerung ist symmetrisch und handschuhtauglich: Minus unten links, das optisch vom Positionspfeil getrennte Fadenkreuz-Zentrieren mittig und Plus unten rechts. Alle drei Kartenknöpfe sind mit 84 × 84 Punkten exakt Faktor 1,5 gegenüber der ersten 56-Punkte-Zoomstufe vergrößert.
- Bei aktiver Navigation rückt die Kartensteuerung um die Höhe des Manöverbanners nach oben. Route, GPX-Import, Kamera-Sync und Teilen liegen darunter als vier gleich große kompakte Werkzeugflächen; Start/Pause/Stop bleiben eigene große Fahrtaktionen.
- „An geplante Straße kleben“ ist eine reine Darstellungshilfe und standardmäßig aus. In der ersten Stufe darf sie nur den sichtbaren Positionspfeil innerhalb einer engen Schwelle auf die aktive Routengeometrie projizieren. Roh-GPS, gespeicherte Spur und Abweichungslogik verwenden immer die unveränderte Messung. Allgemeines Street-Matching gehört in einen austauschbaren Provider und darf niemals still aktiviert werden.
- Puls, Kadenz, Leistung und Sensorakku werden kompakt in das obere Daten-Cockpit integriert. Eine zusätzliche untere Sensorleiste darf die freie Kartenfläche und die Fahrtaktionen nicht verkleinern.

Offline- und Integrationsentscheidungen stehen ausführlich in [ROUTES_MAPS_INTEGRATIONS.md](ROUTES_MAPS_INTEGRATIONS.md). MapLibre/PMTiles ist die Zielrichtung für lokale Vektorkarten; öffentliche OSM-Standardkacheln werden nicht vorgeladen.

## Navigation

Die Navigation führt einen Fortschrittszeiger entlang der Route und berechnet Querabstand sowie plausiblen Vorwärtsfortschritt. GPS-Rauschen allein löst keine Neuberechnung aus. Eine anhaltende Abweichung erzeugt zuerst eine Warnung, dann – abhängig von der Einstellung – eine neue Route vom aktuellen Punkt zum nächsten sinnvollen Routenabschnitt oder Ziel.

Manöver werden auf iPhone, Apple Watch, optional per Sprache und Haptik ausgegeben. Sicherheitsrelevante Hinweise bleiben kurz; die Karte darf während der Fahrt keine kleinen Pflichtbedienelemente verlangen.

## Indoor-Trainingspläne und Geistfahrt

Ein `TrainingPlan` besteht aus geordneten Abschnitten mit Dauer oder Distanz,
Zielbereichen und Übergangsregeln. Die Ausführung erzeugt nur deklarative
Trainerziele; ausschließlich `TrainerCore` prüft FTMS-Fähigkeiten, Grenzen,
Control-Point-Eigentum und Not-Stopp.

Eine Geistfahrt referenziert eine eigene gespeicherte Fahrt und vergleicht
Fortschritt auf derselben Distanzbasis. Angezeigt werden Zeitabstand und
tatsächlich vorhandene Leistung, Kadenz und Puls beider Fahrten. Die
Referenzdaten bleiben lokal, sind keine simulierte Person und senden keine
Trainerkommandos außerhalb derselben `TrainerCore`-Sicherheitsgrenzen.

## Historie und Auswertung

Rohmessungen bleiben unverändert. Zusammenfassungen, Rekorde und Diagrammreihen werden versioniert abgeleitet und können nach Algorithmusänderungen neu berechnet werden. Karten-Vorschaubilder sind Cache, nicht Primärdaten. Löschen einer Fahrt ist ausdrücklich, rückgängig machbar soweit praktisch und entfernt zugehörige HealthKit-Daten nur nach separater Bestätigung und Berechtigung.

## Musik und Audio

Musik ist ein optionales, standardmäßig ausgeschaltetes Cockpit-Modul. Nur die
Einstellungen dürfen es aktivieren oder die Quelle ändern. Aktiviert erscheint
auf der Fahrtkarte ausschließlich ein kleiner Doppelnotenknopf. Er öffnet einen
dunklen Player als Sheet; geschlossen belegt der Player keinen Kartenplatz.
Kontozugangsdaten oder versteckte Kopplungsschritte erscheinen nie im Cockpit.

Die erste Implementierung verwendet auf dem Main Thread
`MPMusicPlayerController.systemMusicPlayer`. Sie übernimmt den Zustand der
Apple-Music-App und bietet Titel/Künstler, Zurück, Play/Pause und Weiter erst
nach `MPMediaLibrary`-Freigabe. Streckenschmiede ersetzt keine Apple-Music-
Bibliothek und beginnt ohne Nutzeraktion keine Wiedergabe.

Weitere Dienste bleiben getrennte Adapter mit ehrlichen Fähigkeiten:

- Spotify App Remote benötigt eine registrierte Spotify-Developer-App,
  Client-ID, Redirect-URI, installierte Spotify-App und ausdrückliche
  Autorisierung. Die Spotify-Bibliothek und Zugangsdaten werden nicht
  nachgebaut oder eingecheckt.
- Amazon Music besitzt derzeit kein öffentliches iOS-SDK; die Web-API ist eine
  geschlossene Beta und verlangt Prüfung/Zertifizierung. Deshalb gibt es keine
  undokumentierte Fernsteuerung.
- Lokale Musik aus Dateien/iCloud Drive wird später von einem eigenen
  `LocalAudioProvider` abgespielt. Ein Nutzer wählt den Ordner mit dem
  Dokumentenpicker; die App speichert nur ein Security-Scoped Bookmark und
  behandelt widerrufenen Zugriff. AVFoundation, Background Audio sowie System-
  Now-Playing/Headsetbefehle gehören zu diesem Provider und beeinflussen
  Navigation oder Fahrtaufzeichnung nicht.

Primärquellen: Apple `MPMusicPlayerController`, Apple Document Picker und
AVFoundation, Spotify iOS App Remote sowie Amazon Music Developer Program:

- <https://developer.apple.com/documentation/mediaplayer/mpmusicplayercontroller>
- <https://developer.apple.com/documentation/uikit/providing-access-to-directories>
- <https://developer.apple.com/documentation/avfoundation/configuring-your-app-for-media-playback>
- <https://developer.spotify.com/documentation/ios>
- <https://developer.amazon.com/docs/music/get_started_program-overview.html>

## Live Activity und Sperrbildschirm

Eine gestartete Outdoor- oder Indoor-Fahrt erhält genau eine ActivityKit-Live-
Activity. Die WidgetKit-Erweiterung unterstützt Lock Screen sowie Dynamic
Island kompakt, minimal und erweitert. Der dunkle Stil zeigt nur auf einen
Blick notwendige, nicht sensible Werte: Fahrtzustand, Zeit, Distanz und
optional Tempo. Route, Zieladresse, Gesundheitswerte und Teilnehmerpositionen
bleiben standardmäßig verborgen. Die Aktivität wird von derselben
`RideSessionEngine` gestartet, aktualisiert und beendet; nach Relaunch werden
verwaiste Activities abgeglichen. Eine Schnellaktion benötigt App Intent und
darf höchstens Pause/Fortsetzen auslösen, niemals Fahrt löschen oder Not-Stopp
umgehen.

Primärquellen:

- <https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities>
- <https://developer.apple.com/design/human-interface-guidelines/live-activities>

## Freiwillige Gruppenposition

Streckenschmiede liest keine privaten Freunde-/Familienpositionen aus Google
Maps oder Apple „Wo ist?“ aus. Googles dokumentierte Maps-URLs können Maps für
Orte, Karten und Navigation öffnen; die Nutzerfunktion zur Echtzeitfreigabe
liefert jedoch keinen dokumentierten Drittanbieter-Datenstrom. Apples
öffentliches Find-My-Programm adressiert MFi-Zubehör im Find-My-Netzwerk und
ist keine API für die Personenpositionen aus „Wo ist?“.

Die produktive Lösung ist deshalb eine eigene, freiwillige Gruppenfahrt:
zeitlich begrenzte Einladung per Link/QR, ausdrücklicher Beitritt jedes
Teilnehmers, verschlüsselte aktuelle Position mit Zeit/Genauigkeit, sichtbarer
Ablauf, Widerruf und automatische Löschung. Google-/Apple-Links dürfen nur als
ausdrückliche Übergabe zum jeweiligen Dienst dienen und werden nicht gescrapt.

Primärquellen:

- <https://developers.google.com/maps/documentation/urls/get-started>
- <https://support.google.com/maps/answer/15437054>
- <https://developer.apple.com/find-my/>

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
- Bluetooth Fitness Machine Service 1.0.1: <https://www.bluetooth.com/specifications/specs/fitness-machine-service-1-0-1/>
- Bluetooth Heart Rate Service: <https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/HRS_v1.0/out/en/index-en.html>
- Bluetooth Cycling Speed and Cadence Service: <https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/CSCS_v1.0/out/en/index-en.html>
- Apple Core Bluetooth State Restoration: <https://developer.apple.com/documentation/corebluetooth/central-manager-state-restoration-options>
- OpenStreetMap Tile Usage Policy: <https://operations.osmfoundation.org/policies/tiles/>

