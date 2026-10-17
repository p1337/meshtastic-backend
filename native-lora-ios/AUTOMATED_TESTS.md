# Automatische Tests ab Version 0.2.0

Die App startet bei jedem neuen App-Prozess einen begrenzten automatischen Software-Testlauf. Ein längerer Lauf ist über „Erweiterten Testlauf starten“ verfügbar. Die UI bleibt während der Berechnung bedienbar. Es werden weder Funkmodi umgeschaltet noch unbekannte Modembefehle aufgerufen.

## Prüfumfang

- FFT gegen analytische Einzelton- und Impulsreferenzen.
- CSS-Symbole SF7–SF12 mit deterministischen Symbolwerten.
- Lineare Pegel und konstante Phasendrehungen.
- Positive/negative Frequenzverschiebung; bekannte Verschiebung des FFT-Bins. Keine Frequenzkorrektur.
- Zyklisch verschobene Symbolgrenzen; keine Präambelsuche.
- AWGN-Messreihe: sechs SF, fünf SNR-Punkte, feste Zufallsfolge. Niedrig-SNR-Fehler sind Messwerte; nur +10 dB wird auf Fehlerfreiheit geprüft.
- CF32LE-Parser, NaN/Inf, falsche Größen, Stille und 8-MiB-Grenze.
- Datei-Analyser mit bekannter synthetischer Referenz und Sampleratenprüfung.
- Rechenzeitmessung; kein Nachweis einer Echtzeit-HF-Kette.

Die Software-Symboltests ersetzen keine unabhängigen echten LoRa-Paketaufnahmen. Kein LoRa-Header, keine FEC/CRC und kein Meshtastic-Paketcodec sind implementiert. Rohsymbolfehler unter AWGN sind keine gemessene iPhone-Empfangsempfindlichkeit.

## GitHub

Vor Signierung und Veröffentlichung baut der macOS-Runner die native App für einen verfügbaren iPhone-Simulator, installiert und startet sie mit `simctl`. Der Runner wartet auf den automatisch erzeugten JSON-Bericht und prüft: Simulator-Kennzeichnung, richtige Version, abgeschlossener Lauf, mindestens 700 Software-Testfälle, 30 AWGN-Messpunkte und keine fehlgeschlagene Prüfgruppe. Der Simulator wird danach beendet.

Das Artifact `LoRaLab-simulator-diagnostics` enthält JSON, Screenshot, App-Icon und Build-Log. Es ist kein XCUITest-Klicktest und kein Test der iPhone-Funkhardware. Die Simulator-iOS-Version wird im Bericht angegeben; sie ist nicht mit Roberts echtem iOS 27.2 gleichzusetzen.

Zusätzlich führt der signierte Gerätebuild die erweiterte native CLI-Regressionssuite aus und legt `diagnostics-report.json` und `test-results.txt` ins IPA-Artifact. Eine fehlgeschlagene obligatorische Prüfung verhindert die Veröffentlichung.

## Echtes iPhone

Die Tabs „Tests“, „Dateien“ und „Berichte“ zeigen getrennte Ergebnisse. Version und Build sind sichtbar. Unter „Berichte“ lässt sich `LoRaLab-Latest.json` direkt teilen. Der Bericht wird lokal gespeichert und enthält keine Rohsamples oder dauerhafte Gerätekennung. Kein automatischer Upload oder Fernzugriff ist eingerichtet. Das iPhone muss zum Start des Gerätetests die App öffnen; die GitHub-Suite kann nur den Cloud-Simulator selbst bedienen.

## Dateien

SF7–SF12, BW125/250/500 und Samplerate sind auswählbar. Die Chirp-Auswertung wird nur bei Fs=BW ausgeführt; es gibt keine ungefilterte Unterabtastung. BW500 ist hier eine Offline-Einstellung, keine zulässige Meshtastic-EU868-Sendekonfiguration. Leistung, DC-Komponenten und Anteil nahe ±1 sind normierte Dateimetriken. Der Anteil nahe ±1 beweist keine ADC-Übersteuerung, wenn das Dateiformat keine solche Normierung garantiert.

Mit „Synthetische Referenz erzeugen und prüfen“ wird eine bekannte CF32LE-Datei erstellt und ausgewertet. Diese kann geteilt und unabhängig geprüft werden. Bin und Spitzenenergie sind keine Paketerkennung.

## Icon

`scripts/render-icon.swift` erzeugt reproduzierbar ein opakes 1024px-PNG mit Chirp und Funkbögen. Es wird vor Simulator- und Gerätebuild im AppIcon-Asset-Katalog erzeugt; Xcode kompiliert die benötigten iOS-Größen. Der Quelltext ist die bearbeitbare Bildquelle. Keine privaten Schlüssel oder Signierdateien gehören zu den Testartefakten.
