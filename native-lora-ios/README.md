# LoRa Lab – native iOS-Test-App

**Kein Live-LoRa-Empfang.** Es gibt noch keinen nachgewiesenen Zugriff auf die internen RF-I/Q-Samples des iPhone 15 Pro Max. Diese App testet den nativen Software- und Installationsweg. Sie enthält keinen erfundenen RadioAdapter und keine privaten Modembefehle.

## Tatsächliche Funktionen

- Synthetischer Chirp-/Dechirp-Selbsttest SF7–SF12 mit nativer FFT.
- Lokaler CF32LE-Dateiimport (Float32 little-endian, I/Q verschachtelt, max. 8 MiB), Leistungsstatistik und angenommener erster SF11-Symbolbin. Kein vollständiger LoRa-Paketdecoder. Samplerate im Formular dient nur zur Dauerberechnung.
- Export von Gerätemodell, iOS-Version und Testergebnissen als Text.
- Keine Internet-, Bluetooth-, Standort-, Mikrofon- oder Mobilfunk-Datenaufnahme. Keine zusätzlichen Entitlements.

## IPA in GitHub Actions bauen

Der Workflow `.github/workflows/native-lora-ipa.yml` baut auf einem macOS-Runner eine **arm64-Geräte-App**, keine Simulator-App. Er führt zuerst eigenständige Swift-Tests aus und erzeugt danach `LoRaLab-unsigned.ipa`. Kein Apple-Account oder Zertifikat wird an GitHub übertragen.

1. Branch `codex/native-lora-ios` öffnen.
2. Unter **Actions → Native LoRa Lab IPA** den erfolgreichen Lauf öffnen.
3. Artifact **LoRaLab-unsigned-IPA** herunterladen und ZIP entpacken.
4. Die darin enthaltene IPA muss vor der Installation signiert werden. Sie lässt sich nicht allein durch Antippen auf dem iPhone installieren.

## Unter Windows auf dem iPhone testen

AltServer und **AltStore Classic** gemäß https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows installieren. AltStore Classic kann die IPA mit dem eigenen Apple-Account signieren und installieren. Kostenlose Accounts müssen Apps üblicherweise nach sieben Tagen erneuern. Apples Developer Mode und Vertrauen in das Entwicklerprofil müssen ggf. aktiviert werden. Die aktuelle Kombination aus iOS-/AltServer-Version ist auf dem konkreten Telefon zu prüfen; hier wurde noch keine Geräteinstallation durchgeführt. AltStore PAL ist nicht derselbe Installationsweg.

Signierdaten ausschließlich selbst in der jeweiligen lokalen Software eingeben. Keine Apple-Passwörter oder privaten Zertifikate ins Repository schreiben.

## Lokal unter macOS

```bash
bash native-lora-ios/scripts/build-ipa.sh
```

Das Xcode-Projekt benötigt keine fremden Swift-Packages oder XcodeGen. Deployment Target iOS 17.0, Produkt `de.p1337.LoRaLab`, Version 0.1.0. Xcode kann das Projekt alternativ mit eigener automatischer Signierung direkt ausführen.

## Nächster Forschungsschritt

Mav23-Capture-Handler und die Quelle der Samples nachweisen. Erst ein echter, auf der installierten iOS-Version erreichbarer Antennen-RX-Pfad ermöglicht die Erweiterung zur Empfangs-App. Erfolgreiches Kompilieren oder Sideloading erteilt keine Modemprivilegien.
