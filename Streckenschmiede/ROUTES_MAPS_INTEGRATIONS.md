# Routen-, Karten- und Standortintegrationen

Stand: 4. November 2026. Dieses Dokument hält Anbietergrenzen fest, damit keine kostenpflichtige oder private Schnittstelle versehentlich als fertige Funktion dargestellt wird.

## GPX aus WhatsApp, Dateien und anderen Apps

Streckenschmiede registriert `com.topografix.gpx` als importierten Dokumenttyp und sich als GPX-Viewer/Ersteller. Eingehende Dokument-URLs werden sofort über denselben begrenzten Parser verarbeitet wie der interne Dateiauswahldialog.

- iOS zeigt Streckenschmiede dadurch in „Öffnen mit“ beziehungsweise im Teilen-Menü für GPX an.
- iOS besitzt für GPX keine vom Nutzer festlegbare systemweite Standard-App-Kategorie wie Browser oder E-Mail. `LSHandlerRank` verbessert die Zuordnung, erzwingt aber keine Auswahl gegen den Willen des Nutzers.
- Sicherheitsbereich der ersten Stufe: reguläre Datei, maximal 50 MB, valide Track-/Routenpunkte und gültige Koordinaten.
- Der nächste Parserausbau muss GPX 1.0/1.1, Tracksegmente, Route, Wegpunkte, Zeit, Höhe und bekannte Extensions erhalten, statt nur eine Koordinatenliste zu erzeugen.

Apple beschreibt die Zuordnung über `CFBundleDocumentTypes`/UTI und den SwiftUI-Empfang über `onOpenURL`.

## Komoot

Die sinnvolle erste Integration ist **GPX-Dateiaustausch ohne Komoot-Kontozugriff**:

1. Route in Komoot als GPX exportieren beziehungsweise teilen.
2. Im iOS-Teilen-Menü Streckenschmiede wählen.
3. Streckenschmiede zeigt und navigiert die Geometrie lokal.
4. Umgekehrt kann eine Streckenschmiede-GPX über das iOS-Teilen-Menü an Komoot übergeben werden.

Komoot dokumentiert GPX-Export sowie GPX/FIT/TCX-Import. Der GPX-Export enthält nur die Geometrie, nicht Komoot-Karten, Sprachanweisungen oder geplante Zwischenpunkte. Für den Export muss die Region am Routenstart im Komoot-Konto freigeschaltet sein.

Kostenentscheidung:

- Für Streckenschmiede fallen beim lokalen GPX-Austausch keine Komoot-API-Kosten an.
- Beim Nutzer kann Komoot eine freigeschaltete Region verlangen. Komoot nennt derzeit eine kostenlose erste Region, danach je nach Markt Einzelregion/Regionspaket oder ein einmalig gekauftes Weltpaket; Premium ist ein separates Abo.
- In den geprüften offiziellen Unterlagen wurde keine öffentliche Self-Service-API gefunden, über die eine beliebige Drittanbieter-App das Komoot-Konto und dessen Routen vollständig synchronisieren darf. Eine echte Kontoverknüpfung wird deshalb erst nach einer schriftlich geklärten Partner-API, Bedingungen und Preisen geplant.

## Apple-, OSM- und Offline-Karten

- Apple MapKit bleibt Standard und liefert Standard, Satellit und Hybrid ohne eigenen Kachelvertrag.
- Eine Fahrradkarte auf OSM-Basis wird über einen austauschbaren Kartenprovider eingebunden. Kartenrenderer und Routingprovider bleiben getrennt.
- Zielrenderer für Offline-Vektorkarten ist MapLibre Native (BSD-2-Clause) mit PMTiles/MBTiles oder einem Provider, der Offline-/Prefetch ausdrücklich erlaubt.
- `tile.openstreetmap.org` wird nie für Gebietsdownloads verwendet. Die offizielle Richtlinie verbietet Offline-Prefetch/Bulkdownload.
- „OpenBikeMap“ ist kein ausreichend eindeutiger technischer Providername. Vor der Einbindung werden Style-URL, Tile-Lizenz, Attribution, Offline-Recht, Kostenlimit und Verfügbarkeit festgehalten. OpenCycleMap/Thunderforest, OpenFreeMap, eigene OSM-Vektorkacheln und andere Anbieter sind unterschiedliche Produkte.
- Erste Online-Stufe: Ein Ebenenknopf rechts oben schaltet Apple Standard,
  Satellit und Hybrid sowie OpenStreetMap Carto. OSM lädt nur die aktuelle
  interaktive Ansicht, sendet `Streckenschmiede/<Version>` mit Projekt-URL als
  User-Agent, respektiert HTTP-Caching und zeigt dauerhaft
  „© OpenStreetMap contributors“. Es gibt keinen OSM-Prefetch und keinen
  OSM-Offlineknopf.
- OpenCycleMap ist ein Thunderforest-Produkt, kein kostenloser OSM-Systemstil.
  Die Ebene ist im Wähler sichtbar, aber nur mit gültigem 32-stelligem
  Thunderforest-Key aktiv. Thunderforest nennt aktuell einen kostenlosen
  Hobby-Tarif mit begrenztem Monatskontingent und kostenpflichtige Folgetarife;
  Konto, Schlüssel und Kostenlimit sind vor Aktivierung zu entscheiden.
- Als sofort nutzbare offene Fahrradkarte wird CyclOSM separat angeboten. Die
  Projektbetreiber veröffentlichen Stil und Kacheladresse und erlauben die
  Wiederverwendung unter der allgemeinen OSM-Tile-Policy. Streckenschmiede
  behandelt diese Ebene daher wie OSM Carto: nur sichtbare interaktive
  Kacheln, identifizierter Client, HTTP-Cache, Attribution und kein Prefetch.
- Jeder Download zeigt Gebiet, Zoomspanne, geschätzte Größe, Stand, Attribution und Löschen-Schaltfläche. Die ausgewählte Apple- oder importierte GPX-Route wird einschließlich Manövern unabhängig von der Kartenoptik atomar lokal gespeichert, nach einem App-Neustart wiederhergestellt und erst über „Navigation beenden“ entfernt. Das ist noch keine benannte Routenbibliothek.

## Erste Apple-Fahrradplanung

- Zielsuche verwendet `MKLocalSearch` mit aktueller GPS-Region als Hinweis und
  zeigt Adressen sowie POIs zur ausdrücklichen Auswahl.
- `MKDirections` berechnet mit Transporttyp `.cycling` und angeforderten
  Alternativen. Distanz und Zeit stammen aus dem jeweiligen `MKRoute`-Objekt;
  die App erfindet keine Höhen- oder Untergrunddaten.
- Apples Swift-Schreibweise `.cycling` steht erst im Xcode-26-SDK, obwohl der
  zugehörige `MKDirectionsTransportType` laut Apple ab iOS 14 verfügbar ist.
  Solange die bewährte Signierpipeline Xcode 16 nutzt, setzt die App deshalb
  denselben dokumentierten Option-Set-Wert `1 << 3` direkt. Das ist keine
  eigene Routinglogik, sondern nur eine Quellcode-Kompatibilitätsschicht.
- Die gewählte Apple-Polyline wird in das providerneutrale Kartenmodell
  übernommen und kann deshalb auf Apple-, OSM- und CyclOSM-Basiskarten liegen.
- Die Apple-Schritte werden beim Übernehmen in providerneutrale Manöver
  umgewandelt. Ein lokaler Geometriepfad berechnet daraus während der Fahrt
  nächste Anweisung, Entfernung, Reststrecke, anteilige Restzeit und
  Querabstand; GPX ohne Manöver erhält weiterhin Fortschritt und Reststrecke.
- Die derzeitige sichtbare 60-Meter-Abweichung ist eine erste Warnstufe, keine
  behauptete Neuberechnung. Zeitliche Entprellung, Haptik, Sprache und
  kontrolliertes Rerouting folgen getrennt.
- Apple stellt keine Feinregler für Radweganteil, Gravel, Untergrund oder
  Hügel bereit. Diese Profile folgen ausschließlich über den getrennten
  Valhalla-Provider.

## Position anderer Personen

Streckenschmiede liest keine fremden Standorte aus Google Maps oder Apples „Wo ist?“ aus:

- Apples öffentliche Find-My-Seite beschreibt die Einbindung von MFi-Zubehör in die Find-My-App, nicht einen Feed mit Personenpositionen für Drittanbieter-Apps.
- In den geprüften Google-Maps-Entwicklerunterlagen wurde keine öffentliche Schnittstelle gefunden, die private Live-Standortfreigaben von Freunden an beliebige Apps ausliefert. Das ist eine Schlussfolgerung aus dem dokumentierten API-Umfang, keine Behauptung über interne Google-Dienste.

Der zulässige Weg ist eine eigene, freiwillige Gruppenfahrt-Freigabe:

- jede Person tritt aktiv per Einladungslink/QR einer zeitlich begrenzten Fahrtgruppe bei;
- Position, Zeit, Genauigkeit und optional Akku/ETA werden verschlüsselt übertragen;
- Freigabe ist jederzeit sichtbar pausier- und widerrufbar;
- standardmäßig keine Historie auf dem Server und automatische Löschung nach der Tour;
- blockierte/entfernte Teilnehmer verschwinden sofort;
- die Karte kennzeichnet veraltete oder ungenaue Positionen deutlich.

Das benötigt einen Synchronisationsdienst, Datenschutzprüfung, Missbrauchsschutz und Hintergrund-/Batterietests. Es ist kein rein lokales Kartenfeature.

## Primärquellen

- Apple `onOpenURL`: <https://developer.apple.com/documentation/swiftui/view/onopenurl%28perform%3A%29>
- Apple Dokumenttypen: <https://developer.apple.com/documentation/uikit/setting-up-a-document-browser-app>
- Komoot GPX Import/Export: <https://support.komoot.com/hc/fr/articles/360026463992-Erreurs-lors-du-chargement-de-fichiers-GPX>
- Komoot Kartenpreise: <https://www.komoot.com/product/>
- Komoot Premium/Live Tracking: <https://www.komoot.com/premium/live>
- MapLibre Native: <https://maplibre.org/projects/native/>
- OSM Tile Usage Policy: <https://openstreetmap.github.io/owg-website/policies/tiles/>
- Apple Find My Network: <https://developer.apple.com/find-my/>
- Apple Core Location und Standortfreigabe: <https://developer.apple.com/documentation/corelocation>

