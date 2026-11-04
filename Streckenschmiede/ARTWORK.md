# Eigene Grafiken

## Corporate-Logo und App-Icon

- Verwendung: offizielles App-Icon und zentrales Corporate-Zeichen.
- Projektdateien:
  `Sources/Assets.xcassets/CorporateLogo.imageset/corporate-logo.png` und
  `Sources/Assets.xcassets/AppIcon.appiconset/app-icon-1024.png`.
- Bildidee: eine orange Route als abstrahiertes `S`, Start-/Zielpunkt und ein
  kleiner Schmiede- beziehungsweise Energie-Funke.
- Gestaltungsregeln: OLED-Schwarz, Safety-Orange `#FF7A00`, viel Negativraum,
  kein Text und keine fremden Markenbestandteile.

Verwendeter Prompt:

> Create a polished corporate brand mark and iOS app icon for a modern German cycling navigation app named Streckenschmiede. Icon-only, no words, no letters, no initials. Core symbol: one bold continuous safety-orange bicycle route bends into a subtle S-shaped path, ending in a simple circular destination pin; at the central bend add one tiny angular forging spark, so the idea is route craft / forged routes. Minimal geometric vector-like design, unmistakable silhouette, strong negative space, premium modern outdoor-tech identity, symmetric visual weight, centered, large margins, legible at 32 pixels. Deep OLED black background, orange #FF7A00 main mark, one restrained warm amber highlight only. Flat design, crisp edges, no gradients, no texture, no mockup, no bicycle illustration, no map screenshot, no text, no typography, no watermark, no Apple logo, no existing brand resemblance. Square 1:1 app-icon composition, fully opaque background, artwork must not touch the edges.

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
