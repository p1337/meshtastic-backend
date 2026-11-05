# Streckenschmiede – Entwicklungsstand

Verbindlicher Gesamtumfang und Status: [../TODO.md](../TODO.md) · Zielarchitektur und dauerhafte technische Entscheidungen: [ARCHITECTURE.md](ARCHITECTURE.md) · [Routen/Karten/Integrationen](ROUTES_MAPS_INTEGRATIONS.md) · [RLV-Kompatibilität](RLV_COMPATIBILITY.md) · [eigene Grafiken](ARTWORK.md) · DJI Action 5 Pro Video-/GPS-Sync: [CAMERA_SYNC.md](CAMERA_SYNC.md)

## Ziel
Native iPhone- und später Apple-TV-App für Fahrradaufzeichnung und Indoor-Training, ohne laufendes Abonnement.

## Aktueller iOS-Grundprototyp
- Zwei Hauptmodi in einem kompakten Umschalter rechts oben: Outdoor und Indoor
  mit eigenen, originalen Symbolen für Strecke/Baum beziehungsweise Fahrrad am
  Hometrainer; die frühere platzraubende untere Tab-Leiste entfällt
- Automatische GPS-Tagesaufzeichnung ohne Startknopf: Bei Standortfreigabe
  beginnt beziehungsweise rekonstruiert die App die Route des lokalen
  Kalendertags. Auto-Pause trennt Stillstand, Wiederanfahren setzt fort und ein
  Tageswechsel schließt die alte GPX-Datei vor dem neuen Tag ab
- GPX-Tagesexport, getrennte Gesamt-/Fahrt-/Pausenzeit und atomarer
  Wiederherstellungsstand; Planung, Import, Teilen und DJI-Sync wurden aus der
  Fahrtkarte in die Einstellungen verschoben
- Erste lokale Tagesfahrten-Historie unter Einstellungen: Datum, Distanz,
  Fahrtzeit, Durchschnitt, Maximum, Auf-/Abstieg und GPS-Punktzahl werden
  versioniert und atomar gesichert; jede Tages-GPX ist einzeln teilbar
- Einstellbare GPS-Auto-Pause: Geschwindigkeit und Verzögerung sind wählbar,
  Wiederanfahren setzt automatisch fort, und eine manuelle Pause kann durch
  Bewegung niemals aufgehoben werden; reale Stop-and-go-Testfahrt steht aus
- Hintergrund-Ortung ist für eine laufende Fahrt konfiguriert; die echte
  Sperrbildschirm- und Langzeittestfahrt steht noch aus
- Bildschirmfüllendes, oben beginnendes Karten-Cockpit mit kompakten
  transparenten Messwert-Overlays, gefahrenem Track, Geschwindigkeit, Zeit,
  Höhe, Auf-/Abstieg und gespeichertem Karten-Zoom; die laufende Position liegt
  beim Folgen horizontal mittig ungefähr ein Drittel über dem unteren Rand
- Die Karte reicht unverändert hinter Uhr, Dynamic Island und Statussymbolen
  bis an die Oberkante. Dort liegt ausschließlich ein durchscheinender
  Material-Blur; er reserviert keinen Platz und verschiebt die Karte nicht.
  Kompass links sowie Outdoor/Indoor/Einstellungen rechts sitzen höher in der
  freien Zeile direkt unter dem Statusbereich
- Erster DJI-Action-5-Pro-Sync-Bildschirm mit Start-/Checkpoint-/End-QR, Fahrt-ID, UTC, Fahrtzeit, Prüfsumme und optionaler GPS-Position
- GPX-Import aus Dateien sowie Empfang über „Öffnen mit“/Teilen aus WhatsApp, Komoot und anderen Apps
- Live-Karte mit geplanter GPX-Linie, Fahrtrichtung/Vorausblick, eindeutigem
  Fadenkreuz-Zentrieren-Knopf und 84-Punkte-Handschuhsteuerung unten: Minus
  ganz links, Zentrieren mittig, Plus ganz rechts; separate Aktions- und
  Tab-Leisten, „Bereit“- und GPS-Punkt-Zeilen sowie die untere Sensorleiste
  wurden zugunsten der Karte entfernt
- Zentrieren stellt den sicheren Vorausblick statt einer Bildschirmmitte wieder
  her; ein gemeinsamer MapKit-Kamerapfad verankert den Fahrer auf Apple- und
  OSM-Karten ein Drittel über dem unteren Rand. Auf kompakten Displays wandert
  der Pfeil automatisch nach oben und hält mindestens 24 Punkte Abstand vor
  den tiefen 84-Punkte-Kartenknöpfen. Die Position wird auch ohne verfügbaren
  Fahrkurs aus der Bildschirmmitte in den unteren Kartenbereich gesetzt. Die
  geneigte 3D-Ansicht wirkt auch im Stand, ist separat abschaltbar und lässt
  sich über einen Regler von 0 bis 30 Grad anpassen. Der native Nordpfeil steht
  links und kollidiert nicht mit dem rechten Outdoor-/Indoor-Umschalter
- Garmin-artig konfigurierbares oberes Daten-Cockpit: 1, 2, 4, 6 oder 8
  Felder sind in Einstellungen wählbar; jedes Feld lässt sich im Hauptbild per
  Antippen dauerhaft auf einen Fahrt-, Höhen-, Zeit- oder Sensorwert umstellen.
  Klein, Mittel und Groß sind frei wählbare Schriftstufen; 1 Feld schlägt Groß,
  2/4 Felder Mittel und 6/8 Felder Klein vor
- Dauerhaft gespeicherte Kartenwahl ausschließlich unter Einstellungen:
  Apple Karte, Apple Satellit, Apple Hybrid, interaktives OpenStreetMap und
  CyclOSM sind aktiv. OpenCycleMap erscheint nur mit gültigem
  Thunderforest-Key; auf der Fahrtkarte verdeckt kein Ebenenknopf die Route.
  Apple-Verkehr ist für die nativen Apple-Kartenstile separat zuschaltbar
- Optionale, standardmäßig ausgeschaltete Musiksteuerung. Sie kann nur in den
  Einstellungen aktiviert werden; im Outdoor-Cockpit bleibt danach nur ein
  kleiner Doppelnotenknopf, dessen Position aus der tatsächlichen Feldanzahl
  und Schriftgröße berechnet wird und deshalb niemals ein Datenfeld überdeckt.
  Er öffnet direkt am rechten Bildschirmrand einen vertikal zentrierten,
  nur etwa 15 Prozent breiten Symbol-Mini-Player; Quelle und
  Playlists erscheinen als wegwischbares Blatt von unten. Apple-Music-Playlists werden nach
  ausdrücklicher Freigabe direkt gelesen und gestartet;
  Spotify, Amazon Music und eigener iCloud-/Dateien-Player sind als getrennte
  Adapter dokumentiert
- Erster Zielplaner innerhalb des Aufzeichnungsbereichs: Adresse oder POI
  suchen, Apple-Fahrradrouten ab aktueller GPS-Position einschließlich
  verfügbarer Alternativen gemeinsam auf der Karte vergleichen, über große
  nummerierte Kartenpunkte auswählen und die ausgewählte Linie übernehmen
- Erste Live-Routenführung für Apple- und GPX-Linien: Fortschritt auf der
  Geometrie, nächstes Apple-Manöver samt Entfernung, Restdistanz, anteilige
  Restzeit und sichtbare Abweichung ab 60 Metern; die aktive Route und ihre
  Manöver werden begrenzt, versioniert und atomar gesichert, nach App-Neustart
  wiederhergestellt und über das X ausdrücklich beendet; beschädigte
  Routensicherungen werden sicher verworfen; echte Fahrt, Haptik, Sprache und
  kontrollierte Neuberechnung stehen noch aus
- Einstellung „An geplante Straße kleben“ ist standardmäßig aus. Eingeschaltet
  wird nur der sichtbare Kartenpfeil in höchstens 50 m Entfernung an die aktive
  Route gelegt; Roh-GPS, Aufzeichnung und Abweichungswarnung bleiben unverändert
- Eigenes orange/schwarzes Corporate-Zeichen mit mittigem Rennrad-Vorderrad,
  steiler Gabel und angeschnittenem Rennlenker; separates Routenmotiv als Hero-Asset
- Mehrere gleichzeitige BLE-Verbindungen mit State Restoration sowie Live-Parsern
  für Heart Rate, Cycling Speed/Cadence, Cycling Power, FTMS Indoor Bike,
  Environmental-Sensing-Temperatur, Battery und Device Information;
  Pedalbalance sowie Temperatur stehen im Outdoor-Datenfeldmenü und im
  Indoor-Livebereich; echte Sensorabnahme steht noch aus
- Erste FTMS-Trainersteuerung mit expliziter Gerätewahl, Control-Point-
  Berechtigung, bestätigten Einzelbefehlen, Wertebereichsprüfung, fünf Sekunden
  Timeout, ERG, Widerstand, Steigung/Simulation, Pause und sichtbarem Not-Stopp;
  die reale Abnahme mit dem Van Rysel D100 steht noch aus
- Dunkles Design mit orangefarbenem Akzent

## Noch nicht implementiert
- Mehrere benannte Cockpit-Layouts, alle Ziel-/Sensorwerte und getrennte Zoom-Presets; die erste frei konfigurierbare 1/2/4/6/8-Felder-Stufe ist vorhanden
- Zielnavigation mit Radweg-/Straßenprofilen, Apple-Fahrradrouting und OSM/Valhalla
- Reale Abnahme der GPS-Aufzeichnung bei gesperrtem Display und nach einem
  erzwungenen App-/Telefonneustart
- Persistente Fahrtenbibliothek
- Apple-Watch-Begleit-App, HealthKit-Workout/-Route und Übergabe an Apple Fitness
- Vollständige Hardwareabnahme, dauerhafte Fahrradzuordnung und Quellenpriorität
  für standardisierte BLE-Sensoren
- Reale D100-Abnahme, Neutralstellung nach Fehlerfällen und Langzeittest der
  FTMS-Steuerung; der standardkonforme erste Steuerpfad ist vorhanden
- Zwift Click V2 Tastenprotokoll und virtuelle Schaltung
- DJI Osmo Action 5 Pro Videoimport, QR-/Timecode-/FIT-Synchronisierung und optionale Kamerasteuerung; das technische Konzept ist dokumentiert
- Offline-Vektorkarten/OSM-Fahrradstil, Komoot-Kontosync und freiwillige Gruppenpositionen; Grenzen und Providerentscheidung sind dokumentiert
- Trainingsplan-Bibliothek, Geistfahrt gegen eine eigene gespeicherte Fahrt,
  Apple-TV-App und Apple Look Around
- Dunkle Live Activity für Lock Screen und Dynamic Island während einer Fahrt;
  die ActivityKit-/WidgetKit-Erweiterung ist geplant, aber noch nicht gebaut
- Freiwillige Gruppenfahrt mit eigener zeitlich begrenzter Standortfreigabe;
  private Google-Maps- oder Apple-„Wo ist?“-Personenpositionen können nicht über
  eine öffentliche Drittanbieter-API ausgelesen werden

## Build und Veröffentlichung
Workflow: `.github/workflows/streckenschmiede-ios.yml`

Die Pipeline nutzt die vorhandene GitHub-Environment `apple-signing` mit `IOS_DISTRIBUTION_P12_BASE64`, `IOS_P12_PASSWORD` und `IOS_ADHOC_PROFILE_BASE64`. Bundle-ID und Team-ID werden aus dem bestehenden Profil übernommen; dadurch ersetzt die App die frühere Werkbeleg-/LoRaLab-Test-App. Nach Compiler-, Profil- und Signaturprüfung werden IPA, Manifest und Store gemeinsam über GitHub Pages veröffentlicht. Ein fehlgeschlagener Build überschreibt den letzten funktionierenden Store nicht.

Vor dem Gerätebuild startet die Pipeline zusätzlich die App auf einem iPhone-
Simulator mit synthetischer Testposition und erzeugt `ui-outdoor.png`. Dadurch
wird der reale Outdoor-Bildschirm pro Release visuell prüfbar; echte Geräte-
und Handschuhtests bleiben trotzdem erforderlich.
