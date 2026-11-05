# Eigene Grafiken

## Corporate-Logo und App-Icon

- Verwendung: offizielles App-Icon und zentrales Corporate-Zeichen.
- Projektdateien:
  `Sources/Assets.xcassets/CorporateLogo.imageset/corporate-logo.png` und
  `Sources/Assets.xcassets/AppIcon.appiconset/app-icon-1024.png`.
- Bildidee: ein exakt kreisförmiges schwarzes Rennrad-Vorderrad auf
  Safety-Orange; vom mittigen Nabenkreis läuft eine steile gerade Gabel zu
  einem angeschnittenen Rennlenker. Ober- und Unterrohr verlassen das Icon
  rechts kurz nach dem Rahmenbeginn.
- Gestaltungsregeln: Safety-Orange, tiefes Schwarz, sehr zurückhaltende
  Satin-/Glaslichter, große Formen, kein Text und keine fremden
  Markenbestandteile. Die Bilddatei bleibt quadratisch und ohne eingebrannte
  Eckenmaske; iOS schneidet die App-Icon-Form selbst.

Verwendeter Prompt:

> Preserve the safety-orange background, black front wheel, steep black fork, cropped black frame tubes, and restrained satin Apple-style finish. Place the exact center of the circular wheel hub at the center of the square canvas; make the wheel ring a perfect circle. Keep one straight steep fork from the centered hub to the compact head tube. Refine the drop handlebar into one clean curved hook above the head tube whose low/drop segment ends as a short horizontal bar pointing right. Show one short top tube and one short down tube behind the head tube, both immediately cropped by the right edge. Keep large simple shapes and 24px readability. No text, letters, anvil, hammer, rider, second wheel, full bike, extra detail, texture or watermark. Opaque square with no baked rounded corners.

## `RideHero`

- Verwendung: Routen-Leerzustand in der iPhone-App.
- Projektdatei: `Sources/Assets.xcassets/RideHero.imageset/ride-hero.png`.
- Erzeugt: 4. November 2026 mit der integrierten OpenAI-Bildgenerierung.
- Rechte-/Markenvorgabe: originelles Motiv, keine fremden Logos, Marken oder kopierten Fitmeter-Elemente.

Verwendeter Prompt:

> Badass moderne Gravel-Fahrerin beziehungsweise moderner Gravel-Fahrer auf einer dunklen alpinen Waldstraße; eine leuchtend orange GPS-Routenlinie führt weit nach vorn. OLED-Schwarz, Anthrazit, Safety-Orange, dezente Höhenlinien, hochwertige kontrastreiche 3D-Illustration, Fahrer im unteren Drittel, keine Schrift, keine Logos, keine Wasserzeichen und keine erkennbaren markenspezifischen Fahrradteile.

Corporate-Logo und App-Icon werden durch den CI-Build mit Apples Asset-Compiler
geprüft. Vor einer Verwendung als Store-Material oder Marketinggrafik sind die
jeweiligen Plattformvorgaben getrennt zu prüfen.

## Hauptreiter-Symbole

- `OutdoorTab`: stark vereinfachter, bei Tab-Größe lesbarer Vektor aus einem
  einzelnen Baum und einer breiten Strecke, die zur oberen rechten Ferne führt;
  keine kleinteiligen Richtungspfeile oder überlagerten Konturen.
- `IndoorTab`: vereinfachter Vektor mit genau einem sichtbaren Vorderrad,
  angedeutetem Diamantrahmen und einem klaren dreieckigen Hometrainer-Ständer
  an der Hinterachse; keine zweite Radkontur und keine Produktkopie.
- Beide SVGs sind einfarbige Template-Assets, damit iOS sie im Tab-Balken mit
  der aktiven oder inaktiven Systemfarbe rendert. Sie enthalten weder fremde
  Markenformen noch D100-Produktgrafiken.

## Fahrradprofil-Schattenbilder

- Die Profilvorschauen sind eigene, zur Laufzeit gezeichnete SwiftUI-Vektoren;
  es werden keine Herstellerbilder, Produktfotos oder fremden Markenformen
  gespeichert.
- Orange Kartenfläche, tiefschwarze Silhouette, große Räder und wenige kräftige
  Rahmenlinien bleiben auch als kleine Vorschau erkennbar.
- Typmerkmale wie Rennlenker, Aeroaufsatz, Federung, Gepäckträger, Lastenbox,
  Tandemsitz, Faltgelenk oder E-Bike-Akku werden nur abstrahiert angedeutet.
  Das Bild ist Orientierung, keine maßhaltige Produktdarstellung.
