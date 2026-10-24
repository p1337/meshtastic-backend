> **Aktuelles Projekt: Werkbeleg.** Die neue native Handwerker-App ist in [WERKBELEG.md](WERKBELEG.md) dokumentiert. Das LoRa-Forschungsprojekt bleibt gestoppt; die folgenden Abschnitte beschreiben die frühere Test-App.

# LoRa Lab für iPhone

Version **0.3.0 (Build13)**, erfolgreich Apple-signiert und veröffentlicht. Native Forschungs-App für das iPhone15ProMax. Noch kein nachgewiesener interner RF-I/Q-Zugang und kein Live-LoRa-Empfang.

## Auf dem iPhone

[Installationsseite](https://p1337.github.io/meshtastic-backend/). Über den vorhandenen Apple-signierten Ad-Hoc-Weg aktualisieren. Nach Veröffentlichung zeigt die Seite die aktuelle Version/Buildnummer. Profil und Zertifikat müssen für das registrierte Gerät gültig sein.

App öffnen und **60 Sekunden im Vordergrund lassen**. Der neue Tab **Funkpfad** startet automatisch eine Geräteprüfung und eine Zeitdiagnose. Danach **Gesamten JSON-Bericht teilen** oder den Textbericht exportieren. Optional120 Sekunden wählen. Ein Hintergrundwechsel beendet die Beobachtung mit entsprechendem Status.

Diese Minute ist eine reale Beobachtung von Zugriffsmerkmalen und öffentlichem Mobilfunkstatus, **keine RF-Aufnahme**. Es werden keine künstlichen I/Q-Daten als Funkempfang ausgegeben. `rfIQSamples=0` bleibt ausdrücklich sichtbar.

## Neu in0.3

- Tatsächlicher iOS-Build und eigene Prozessrechte.
- Ausgewählte eigene Entitlements über SecTask; Rückgabefehler werden erhalten.
- dyld-Cache-/Image-Prüfung für mögliche Modem-Transportbibliotheken.
- Sichtbare Baseband-nahe IORegistry-Klassennamen und Gerätepfade; genaue Rückgabecodes.
- Monoton protokollierte60-/120-Sekunden-Sitzung, tatsächliche Statusabfragen und erkennbare Lücken/Abbrüche.
- Gemeinsamer lokaler JSON-Bericht, äußeres Schema3, sowie Textbericht.

Keine neuen privaten Entitlements, keine Carrier- oder Modemkonfiguration geändert, kein UserClient geöffnet und kein Modemkommando gesendet. Sichtbare Bibliotheken oder Registry-Dienste beweisen keinen erreichbaren I/Q-Stream. Herkunft und Grenzen stehen vollständig in [RUNTIME_RESEARCH.md](RUNTIME_RESEARCH.md).

## Vorhandene Signalwerkzeuge

Automatischer synthetischer Softwarelauf:835 Fälle/Messungen; erweiterter Lauf2567. FFT-Referenzen, SF7–SF12, Pegel/Phase, Frequenz-/zyklische Zeitversätze,30 deterministische AWGN-Punkte, Parsergrenzen und Benchmark. Niedrige SNRs dürfen Symbolfehler enthalten. Kein Paketcodec, keine Präambelsynchronisation und keine iPhone-Empfindlichkeitsmessung.

CF32LE-Dateianalyse bis8MiB: Fs/SF/BW, Leistung/DC, ausgerichteter Chirp nur beiFs=BW. Eine exportierbare Referenzdatei bleibt klar als synthetisch markiert. BW500 ist eine Offline-Einstellung, kein EU868-Sendepreset. Die Dateiwerkzeuge sind kein Langzeitrecorder.

## Automatisierung und Quelltext

Vollständiger Quelltext: `Sources/`, Xcode-Projekt ohne externe Paketabhängigkeiten, reproduzierbarer CoreGraphics-Icongenerator. Mindestziel iOS17. Der spezialisierte Branch ist `codex/native-lora-ios`; `master` bleibt unverändert.

GitHub Actions führt native Hosttests aus, baut/startet eine separate Simulator-App und wartet auf deren tatsächliche60-Sekunden-Diagnose samt JSON-Bericht. Anschließend werden arm64-Geräte-IPA, Apple-Distribution-Signatur, Profilbindung und OTA-Veröffentlichung geprüft. Der Simulator installiert keinen gerätegebundenen Ad-Hoc-Build und bestätigt keine Telefon-HF-Fähigkeit.

Details: [AUTOMATED_TESTS.md](AUTOMATED_TESTS.md), [SIGNING.md](SIGNING.md), [OTA_INSTALL.md](OTA_INSTALL.md).


Aktueller verifizierter Build: [39037447564](https://github.com/p1337/meshtastic-backend/actions/runs/39037447564). Native Tests und reale60-Sekunden-Simulator-Sitzung bestanden, veröffentlichte IPA/Metadaten/Hashes geprüft. Siehe [RUNTIME_RESEARCH.md](RUNTIME_RESEARCH.md) auch für das tatsächlich gelesene und signaturgeprüfte Apple-Debugprofil sowie die neue, weiterhin unbewiesene SIM-Toolkit-Spur. Keine eSIM installiert und kein RF-Zugang behauptet.
