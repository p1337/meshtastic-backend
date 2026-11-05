# Streckenschmiede

Native Fahrrad-App für iPhone, später optional tvOS. Kostenlos nutzbare Lösungen, keine Abos.

Verbindlicher Gesamtumfang und Abnahmestatus: [TODO.md](TODO.md) · Technische Zielarchitektur: [Streckenschmiede/ARCHITECTURE.md](Streckenschmiede/ARCHITECTURE.md)

## App (iOS 17+)
**Exakt zwei Hauptmodi in einem kompakten Umschalter rechts oben:**
- **Outdoor:** bildschirmfüllendes Karten-Cockpit mit Positionspfeil im
  unteren Drittel und großem Vorausblick; bei Standortfreigabe läuft eine
  automatische Tagesaufzeichnung ohne Startknopf. Bewegte Abschnitte werden
  durch Auto-Pause getrennt und pro Kalendertag in einer Route gesammelt;
  ein in Einstellungen auf 1, 2, 4, 6 oder 8 Felder schaltbares Cockpit;
  jedes Feld kann im Hauptbild per Antippen auf einen Fahrt- oder Sensorwert
  gelegt werden; die Beschriftung ist zusätzlich in Klein, Mittel oder Groß
  wählbar und erhält abhängig von der Feldanzahl einen sinnvollen Vorschlag;
  handschuhtaugliche 84-Punkte-Trefferflächen mit visuell kompaktem Minus
  links, Zentrieren mittig und Plus rechts; der Pfeil bleibt im Follow-Modus
  mit reserviertem Abstand oberhalb dieser Bedienzone;
  Kartenwahl in den Einstellungen für Apple Karte, Satellit, Hybrid,
  Online-OSM und die offene Fahrradkarte CyclOSM, ohne zusätzlichen
  Ebenenknopf über der Fahrkarte; Apple-Verkehr und eine 0–30-Grad-
  3D-Neigung sind separat einstellbar;
  erster Zielplaner mit Adress-/POI-Suche, Apple-Fahrradrouten und Alternativen;
  kompakte Live-Führung mit nächstem Apple-Manöver, Entfernung, Reststrecke,
  Restzeit und sichtbarer Routenabweichung; die aktive Apple- oder GPX-Route
  bleibt über einen App-Neustart erhalten und kann ausdrücklich beendet werden;
  einstellbare GPS-Auto-Pause mit Verzögerung, Hysterese und sicherem Vorrang
  der manuellen Pause;
  optional ausschließlich in den Einstellungen aktivierbare Apple-Music-
  Steuerung: Auf der Karte bleibt nur ein kleiner Doppelnotenknopf am rechten
  Bildschirmrand. Er öffnet dort eine nur ungefähr 15 Prozent breite,
  vertikal ausgerichtete und bündig sitzende Symbolleiste mit
  Zurück, Play/Pause, Weiter und Mediathek; das Blatt von unten bietet
  Apple-Music-Playlists; direkt darunter pausiert beziehungsweise setzt ein
  gleich großer kompakter Fahrtknopf die automatische Tagesaufzeichnung fort;
  mehrere lokal gespeicherte Fahrradprofile mit aktivem Rad, eigenem Namen,
  Fahrradtyp, Schattenbild und Abroll-Durchmesser; der daraus berechnete
  Radumfang wird direkt für BLE-Geschwindigkeitssensoren verwendet;
  Pedalbalance und BLE-Umgebungstemperatur sind zusätzlich als frei wählbare
  Datenfelder verfügbar;
  atomare Notfall-Wiederherstellung, Distanz und Tages-GPX-Export; Planung,
  Import, Teilen und Kamera-Sync liegen außerhalb der störungsfreien Fahrkarte
- **Indoor:** gleichzeitige BLE-Sensorverbindungen mit Puls, Tempo,
  Kadenz, Leistung, Pedalbalance, Umgebungstemperatur, FTMS-Livewerten und Akku
  sowie erste begrenzte
  FTMS-Steuerung für D100-kompatible Trainer mit ERG, Widerstand, Steigung,
  Pause und Not-Stopp

Die Profiltypen decken Rennrad, Gravel, Cyclocross, Triathlon, Bahn/Fixie,
MTB-Varianten, Trekking, City, Reise, Hybrid, Lastenrad, Falt-/Kinder-/BMX-,
Liege-, Tandem-, Hand-, Cruiser- und die entsprechenden E-Bike-Klassen ab;
„Andere“ bleibt für Sonderräder verfügbar.

Einstellungen sind über das Zahnradsymbol erreichbar. Design: dunkel, orangefarbene Akzente. Der derzeitige Build ist nur ein Grundprototyp. Das verbindliche Ziel umfasst ein modernes Fahrt-Cockpit, Live-Navigation mit Radweg-/Straßenprofilen und einstellbaren Zoomstufen, OSM-Option, Apple Watch/HealthKit/Apple Fitness, mehrere gleichzeitige Fahrradsensoren, D100/FTMS, Click V2 und die dokumentierten Historien-/Analysefunktionen. Diese Punkte sind in [TODO.md](TODO.md) einzeln aufgeführt und überwiegend **noch nicht implementiert**.

## Build und OTA-Installation

Quellcode: [Streckenschmiede/](Streckenschmiede/) · CI: [.github/workflows/streckenschmiede-ios.yml](.github/workflows/streckenschmiede-ios.yml)

Jeder Push auf `streckenschmiede-ios` mit App-/Workflow-Änderungen startet den macOS-Build. Der Workflow:

1. Prüft Swift-Syntax, generiert das Xcode-Projekt und kompiliert die unsignierte iPhone-App.
2. Verwendet die bereits bewährte Signierumgebung `apple-signing` und deren drei bestehenden Environment-Secrets. Team-ID und Bundle-ID werden aus dem vorhandenen Profil gelesen; Streckenschmiede ersetzt dadurch die frühere Test-App auf den registrierten Geräten.
3. Importiert dieselbe Apple-Distribution-Identität in einen temporären Keychain, archiviert und exportiert eine signierte IPA.
4. Validiert Bundle-ID, Profil, Ablaufdatum und die tatsächliche Apple-Code-Signatur mit [package_release.py](Streckenschmiede/scripts/package_release.py).
5. Generiert `index.html`, `Streckenschmiede.ipa`, `manifest.plist`, `release.json`; veröffentlicht das Paket mit GitHub Pages **nur nach erfolgreicher Signaturprüfung**.

Der macOS-Build darf bis zu 45 Minuten laufen. Simulator, Geräte-Compile und
signiertes Archiv schwanken auf den bereitgestellten Intel-Runnern; das frühere
30-Minuten-Limit konnte einen ansonsten fehlerfreien Build erst während des
Archivs abbrechen.

Der Store soll unter [p1337.github.io/meshtastic-backend](https://p1337.github.io/meshtastic-backend/) erreichbar sein. Die Datei `index.html` im Branch allein veröffentlicht **keine** App.

### Bestehende Environment-Secrets

- `IOS_DISTRIBUTION_P12_BASE64`: Base64-kodiertes Apple-Distribution-P12
- `IOS_P12_PASSWORD`: Passwort des P12
- `IOS_ADHOC_PROFILE_BASE64`: Base64-kodiertes bestehendes Ad-hoc-Profil

Secretwerte werden nie ausgegeben. Team, Profil-UUID, Zertifikatsbindung und die konkrete Bundle-ID werden im Runner aus dem Profil validiert. Die IPA wird nur auf den dort registrierten iPhone-UDIDs installiert. GitHub Pages bleibt auf **GitHub Actions als Build-/Deploymentquelle** eingestellt.

Historische Referenz: Die identische Signierumgebung und dieselben drei Secret-Namen haben Werkbeleg und LoRaLab mehrfach erfolgreich signiert und per Pages veröffentlicht. Ein Streckenschmiede-Release gilt trotzdem erst nach erfolgreichem aktuellem Workflow, Signaturprüfung und Abruf der veröffentlichten OTA-Dateien als fertig.

## Schutz bestehender Dateien

Keine fremden oder historischen Dateien löschen. Keine Secrets im Repository ablegen. Die Release-Pipeline überschreibt die öffentliche Webseite nur, wenn eine gültige signierte Streckenschmiede-IPA vorliegt.
