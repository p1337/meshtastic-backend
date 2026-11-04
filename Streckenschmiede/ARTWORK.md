# Eigene Grafiken

## `RideHero` und App-Icon

- Verwendung: Routen-Leerzustand in der iPhone-App.
- Projektdatei: `Sources/Assets.xcassets/RideHero.imageset/ride-hero.png`.
- App-Icon: quadratischer 1024-Pixel-Ausschnitt derselben Originalgrafik unter
  `Sources/Assets.xcassets/AppIcon.appiconset/app-icon-1024.png`.
- Erzeugt: 4. November 2026 mit der integrierten OpenAI-Bildgenerierung.
- Rechte-/Markenvorgabe: originelles Motiv, keine fremden Logos, Marken oder kopierten Fitmeter-Elemente.

Verwendeter Prompt:

> Badass moderne Gravel-Fahrerin beziehungsweise moderner Gravel-Fahrer auf einer dunklen alpinen Waldstraße; eine leuchtend orange GPS-Routenlinie führt weit nach vorn. OLED-Schwarz, Anthrazit, Safety-Orange, dezente Höhenlinien, hochwertige kontrastreiche 3D-Illustration, Fahrer im unteren Drittel, keine Schrift, keine Logos, keine Wasserzeichen und keine erkennbaren markenspezifischen Fahrradteile.

Der App-Icon-Ausschnitt wurde als Xcode-Asset eingebunden und wird durch den
CI-Build mit Apples Asset-Compiler geprüft. Vor einer Verwendung als
Store-Material oder Marketinggrafik sind die jeweiligen Plattformvorgaben
getrennt zu prüfen.
