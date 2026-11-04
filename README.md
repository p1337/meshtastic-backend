# Streckenschmiede

Native Fahrrad-App für iPhone und perspektivisch Apple TV.

## iOS-App
Quellcode: [Streckenschmiede/](Streckenschmiede/)

Funktionen im Entwicklungsstand:
- Aufzeichnung: GPS, GPX-Export, GPX-Import, Apple-Karten
- Indoor-Training: Bluetooth-Gerätesuche (Van Rysel D100, Zwift Click)
- Schwarz-orange Benutzeroberfläche mit zwei Hauptreitern

## Webstore
Die Datei [index.html](index.html) ist die vorbereitete Streckenschmiede-Webseite.
Die öffentliche GitHub-Pages-Seite wird dadurch **nicht automatisch** umgestellt.
Für eine funktionierende OTA-Installation werden eine signierte IPA, ein manifest.plist und ein korrektes Release-Metadatenfile benötigt.

## Build
Workflow: [.github/workflows/streckenschmiede-ios.yml](.github/workflows/streckenschmiede-ios.yml)
Aktuell ohne bestätigten erfolgreichen signierten Build.

## Wichtiger Hinweis
Die ursprüngliche Meshtastic-Historie und die bestehende Werkbeleg-Verteilung sind nicht gelöscht. Sie dürfen erst nach Sicherung der verwendeten Signierung und Pages-Veröffentlichung bereinigt werden.
