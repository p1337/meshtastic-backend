# Eigene Grafiken

## Corporate-Logo und App-Icon

- Verwendung: offizielles App-Icon und zentrales Corporate-Zeichen.
- Projektdateien:
  `Sources/Assets.xcassets/CorporateLogo.imageset/corporate-logo.png` und
  `Sources/Assets.xcassets/AppIcon.appiconset/app-icon-1024.png`.
- Bildidee: ein orangefarbener Schmiedeamboss als unverwechselbare
  Markensilhouette; eine geschwungene schwarze Fahrradstrecke ist als
  Negativraum in den Amboss geschnitten und führt zu einem Zielpunkt am Horn.
  Ein einzelner heller Funke steht für die Schmiede.
- Gestaltungsregeln: OLED-Schwarz, Safety-Orange `#FF7A00`, viel Negativraum,
  kein Text und keine fremden Markenbestandteile.

Verwendeter Prompt:

> Design one iconic, highly distinctive corporate app icon for a German bicycle navigation and training brand called Streckenschmiede. Create a single memorable emblem that fuses two ideas into one silhouette: a blacksmith anvil and a winding bicycle road. The outer shape is a compact, bold safety-orange anvil seen from the side; a clean black negative-space road cuts through the anvil in an elegant S curve, beginning as a small round wheel/hub at lower left and ending as a precise destination dot near the horn. Add exactly one tiny four-point forge spark above the horn. This must feel like an enduring global sports-tech logo: instantly recognizable, ownable, simple enough to draw from memory, legible at 24px, strong balance and negative space. Deep solid black square background, flat safety orange #FF7900 emblem, optional tiny off-white spark only. No text, no letters, no gradients, no shadows, no 3D, no photo, no bicycle rider, no literal bicycle, no map screenshot, no pin symbol, no lightning bolt, no existing brand resemblance, no watermark. Centered with generous optical padding, crisp vector-like geometry, premium iOS app icon composition, fully opaque.

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
