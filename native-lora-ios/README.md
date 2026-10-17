# LoRa Lab – native iOS-Forschungs-App

Version **0.2.0**. Die App läuft lokal und empfängt noch keine LoRa-Pakete. Ein nutzbarer I/Q-Zugang zur internen Funkhardware des iPhone 15 Pro Max ist weiterhin nicht nachgewiesen.

## Installieren und aktualisieren

Auf dem registrierten iPhone in **Safari** öffnen:

https://p1337.github.io/meshtastic-backend/

„Auf diesem iPhone installieren“ antippen und die iOS-Rückfrage bestätigen. Der veröffentlichte Build ist mit dem eigenen Apple-Distribution-Zertifikat und einem passenden Ad-Hoc-Profil signiert. Einrichtung: [SIGNING.md](SIGNING.md); drahtlose Verteilung: [OTA_INSTALL.md](OTA_INSTALL.md). Profil und Zertifikat haben Ablaufdaten.

## Funktionen

- Automatischer Startlauf mit **835 Prüf-/Messfällen**; erweiterter Lauf mit **2567 Fällen**.
- Analytische FFT-Referenzen, CSS SF7–SF12, Pegel/Phase, Frequenz- und Zeitversätze, 30 AWGN-Messpunkte, Parser-/Eingabegrenzen und DSP-Laufzeit.
- CF32LE-Dateianalyse bis 8 MiB mit auswählbarer Samplerate, SF und Bandbreite, Leistungs-/DC-Statistik und erstem ausgerichtetem Symbolbin. Chirp-Auswertung nur bei Fs=BW.
- Generierbare und teilbare synthetische Referenzdatei.
- Automatisch gespeicherte JSON- und Textberichte; Teilen im Tab „Berichte“. Kein automatischer Upload, keine Rohsamples im Bericht.
- Sichtbare App-/Buildnummer und eigenes opakes iOS-Icon aus einer reproduzierbaren Grafikquelle.

Ein Symbolbin ist keine Paketerkennung. Kein LoRa-Header, keine FEC/CRC und kein Meshtastic-Paketcodec. Die Störsignaltests messen keine iPhone-RF-Empfindlichkeit. BW500 dient nur Offline-Analysen und ist kein Meshtastic-EU868-Sendepreset.

## Automatische GitHub-Prüfungen

Der Workflow `.github/workflows/native-lora-ipa.yml` führt native Regressionen aus, baut einen separaten Simulator-Build, startet die App und prüft ihren automatisch erzeugten JSON-Bericht. Danach wird die echte arm64-Geräte-App archiviert, mit Apple Distribution signiert und geprüft. Nur erfolgreiche Gerätebuilds werden über Pages veröffentlicht.

Der Simulator benötigt keine Gerätefreigabe. Die Ad-Hoc-IPA bleibt auf die registrierten iPhones beschränkt. Der Simulator prüft keine HF-Hardware. Er ist kein Ersatz für einen Bericht vom echten Gerät.

Artifacts: `LoRaLab-native-diagnostics`, `LoRaLab-simulator-diagnostics`, `LoRaLab-Apple-signed-IPA`. Umfang und Grenzen: [AUTOMATED_TESTS.md](AUTOMATED_TESTS.md).

## Lokal unter macOS

```bash
bash native-lora-ios/scripts/build-ipa.sh
```

Das Skript rendert das Icon, führt die native Suite aus und erzeugt einen **unsignierten** lokalen Testbuild. Für normale Xcode-Builds das Icon vorher erzeugen:

```bash
xcrun swift native-lora-ios/scripts/render-icon.swift native-lora-ios/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

Keine fremden Swift-Packages oder XcodeGen nötig. Deployment Target iOS 17.0; Bundle-ID `de.p1337.LoRaLab`. Der produktive Cloud-Pfad verwendet ausschließlich die drei Environment Secrets in `apple-signing`; private Schlüssel und P12-Dateien gehören nicht ins Repository.

## Nächster Hardware-Forschungsschritt

Mav23-Capture-Handler, tatsächliche Samplequelle und erreichbare Schnittstelle nachweisen. Der erfolgreich installierte Offline-Test öffnet keinen Baseband-Zugang.
