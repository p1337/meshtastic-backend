# LoRa Lab – native iOS-Test-App

**Aktueller Buildweg: reguläre Apple-Distribution-Signierung in GitHub Actions. Einrichtung und fehlende Signierdaten: [SIGNING.md](SIGNING.md).**

Die unten stehenden Angaben zum unsignierten Build beschreiben den historischen ersten Test; der aktuelle GitHub-Workflow erzeugt ausschließlich nach erfolgreicher Signaturprüfung eine signierte IPA.

**Kein Live-LoRa-Empfang.** Es gibt noch keinen nachgewiesenen Zugriff auf die internen RF-I/Q-Samples des iPhone 15 Pro Max. Diese App testet den nativen Software- und Installationsweg. Sie enthält keinen erfundenen RadioAdapter und keine privaten Modembefehle.

## Tatsächliche Funktionen

- Synthetischer Chirp-/Dechirp-Selbsttest SF7–SF12 mit nativer FFT.
- Lokaler CF32LE-Dateiimport (Float32 little-endian, I/Q verschachtelt, max. 8 MiB), Leistungsstatistik und angenommener erster SF11-Symbolbin. Kein vollständiger LoRa-Paketdecoder. Samplerate im Formular dient nur zur Dauerberechnung.
- Export von Gerätemodell, iOS-Version und Testergebnissen als Text.
- Keine Internet-, Bluetooth-, Standort-, Mikrofon- oder Mobilfunk-Datenaufnahme. Keine zusätzlichen Entitlements.

## Apple-signierte IPA in GitHub Actions bauen

Der Workflow `.github/workflows/native-lora-ipa.yml` verwendet einen macOS-Runner und eine echte Apple-Distribution-Identität mit einem passenden Ad-Hoc-Profil. Die Einrichtung steht in [SIGNING.md](SIGNING.md). Die drei Signier-Secrets gehören in das GitHub-Environment `apple-signing`; niemals als Quelltext ins Repository.

Der Build führt die Swift-Tests aus, archiviert die arm64-Geräte-App, exportiert eine signierte IPA und prüft Signatur, Team und Profil. Nur bei Erfolg entsteht das Artifact **LoRaLab-Apple-signed-IPA**. Fehlende Signierdaten führen zu einem ausdrücklichen Fehler. Es gibt keinen unsignierten Fallback.

Die IPA kann auf den im Profil registrierten Geräten installiert werden. Ein passender Installationsweg unter Windows muss separat geprüft werden; eine Geräteinstallation ist noch nicht verifiziert. Eine erneute Signierung durch AltStore ist für diesen Build nicht vorgesehen.

Der erste erfolgreiche historische Build erzeugte eine unsignierte IPA. Das erhaltene Skript `scripts/build-ipa.sh` erzeugt weiterhin nur diesen unsignierten lokalen Testbuild.

## Lokal unter macOS

```bash
bash native-lora-ios/scripts/build-ipa.sh
```

Das Xcode-Projekt benötigt keine fremden Swift-Packages oder XcodeGen. Deployment Target iOS 17.0, Produkt `de.p1337.LoRaLab`, Version 0.1.0. Xcode kann das Projekt alternativ mit eigener automatischer Signierung direkt ausführen.

## Nächster Forschungsschritt

Mav23-Capture-Handler und die Quelle der Samples nachweisen. Erst ein echter, auf der installierten iOS-Version erreichbarer Antennen-RX-Pfad ermöglicht die Erweiterung zur Empfangs-App. Erfolgreiches Kompilieren oder Sideloading erteilt keine Modemprivilegien.
