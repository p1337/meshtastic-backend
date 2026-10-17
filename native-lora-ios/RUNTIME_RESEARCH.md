# Laufzeitprüfung 0.3.0: Herkunft und Geltungsbereich

Stand: 17.10.2026. Zielgerät: iPhone16,2, vom Nutzer gemeldetes iOS 27.2. Hardware unverändert. Kein nachgewiesener interner RF-I/Q-Zugang. Version 0.2.0 (12) wurde vom Nutzer auf dem echten Telefon bestätigt: 2567 synthetische Fälle/Messungen, keine fehlgeschlagene Prüfgruppe. Eine kurze Berechnungszeit war keine HF-Beobachtungsdauer.

## Was diese Version neu misst

`RuntimeAudit.swift` erhebt read-only Befunde im tatsächlichen App-Prozess:

- OS-Build über `sysctlbyname("kern.osversion")` und effektive UID des eigenen Prozesses.
- Neun benannte eigene Entitlements über `SecTaskCreateFromSelf` / `SecTaskCopyValueForEntitlement`. Kein pauschales Auslesen sämtlicher Entitlements, keine Änderung der Signatur. Fehlende Werte mit Fehler werden als nicht verfügbar statt als sicher nicht gesetzt behandelt.
- Vorhandensein von sechs Kandidatbibliotheken im aktiven dyld Shared Cache bzw. in den bereits geladenen Images. Private Transportbibliotheken werden dafür nicht geladen oder aufgerufen. Ein negatives Pfadergebnis beweist kein Fehlen einer anders benannten Implementierung.
- Sichtbare IOService-Klassennamen, gefiltert auf Baseband/QMI/ConvergedIPC/Telephony. Höchstens 2048 Einträge und 64 relevante Klassennamen. Keine Registry-Properties mit Hardwarekennungen, kein `IOServiceOpen`, keine UserClient-Selektoren oder RF-Register.
- Metadaten zweier Carrier-Verzeichnispfade und gefilterte Gerätenamen in `/dev`. Keine Inhalte der Carrier-Bundles und keine Geräteknoten geöffnet. Namespace/Sandbox und vollständiges Hardwareinventar sind unterschiedliche Dinge.

Der Simulator überspringt Registry- und Gerätepfadtests, damit Host-Hardware nicht als iPhone-Hardware ausgegeben wird. Der macOS-CLI-Test meldet explizit Host statt iPhone.

Die automatische Zeitdiagnose läuft standardmäßig echte 60 Sekunden im Vordergrund, wahlweise 120 Sekunden. Etwa sekündlich wird nur `serviceCurrentRadioAccessTechnology` abgefragt, ohne SIM-/Netzbetreiber-Kennungen zu speichern. Diese API ist veraltet und kann keine Werte liefern; auch das wird als Beobachtung gespeichert. Monotone Zeitwerte, tatsächliche Abfragen und Lücken bleiben im JSON erhalten. Verspätete Ticks werden nicht als historische Messpunkte erfunden. Hintergrundwechsel bricht ab und wird als Unterbrechung markiert. Die normale Bildschirmsperre wird nur für den laufenden Vordergrundtest verzögert.

**Die Sitzung zeichnet keine RF-Samples auf.** `rfIQSamples=0`, `rfCaptureAvailable=false`; keine RF-Mittenfrequenz wird als Messwert eingetragen. Sichtbarkeit und Entitlement-Information sind Vorbedingungenforschung und kein nachgewiesener Zugriff auf einen nutzbaren I/Q-Stream. Es wird kein Modemkommando gesendet und keine UserClient-Verbindung geöffnet.

Gesamtbericht: `LoRaLab-Latest.json`, äußeres Schema 3, Felder `suite` (bisheriges LabReport-Schema 2), `runtimeAudit`, `accessSession`, optional `importedFile`. Zusätzlich vollständig lokal erzeugter Textbericht. Manuelles Teilen, kein automatischer Upload.

## Nachgeprüfte Primärquellen und Vergleichsprojekte

| Quelle | Direkt geprüft | Schluss für unser Gerät |
| --- | --- | --- |
| [Apple IOKitLib.h](https://github.com/apple-oss-distributions/IOKitUser/blob/main/IOKitLib.h), Blob `92a1ff3aba76ea410973cbabc6d6740c4818a717` | C-ABIs, Iterator-/Objekt-Freigaben; Matching-Dictionary wird von GetMatchingServices verbraucht | Belegt die aufgerufenen Abfragefunktionen; nicht ihre Berechtigung unter iOS 27.2 |
| [Apple SecTask.h](https://github.com/apple-oss-distributions/Security/blob/main/sectask/SecTask.h), Blob `e712b3878a86efd50b162d36d7320e2a75f277c5` | Eigentask-/Entitlement-Abfrage, CF-Rückgabe und Fehlerparameter | Keine erfundene Entitlement-API; dynamische Verfügbarkeit wird geprüft |
| [Apple dyld.h](https://github.com/apple-oss-distributions/dyld/blob/main/include/mach-o/dyld.h), Blob `7bf19c034af3c3bd61f09e42fdfabb6979563d88` | `_dyld_shared_cache_contains_path` ab iOS14; Cache-Bibliotheken können ohne reguläre Datei vorliegen | `stat` allein wäre für Bibliotheken ein falscher Negativtest |
| [Apple Core Telephony](https://developer.apple.com/documentation/coretelephony/cttelephonynetworkinfo/servicecurrentradioaccesstechnology) | Radio-Access-Technology-Status | Kein ADC-/I/Q-Pfad; kein Rückschluss von LTE/NR auf beobachtete 869,525 MHz |
| [BaseTrace QMI Injector](https://github.com/seemoo-lab/BaseTrace/tree/main/qmi-inject) | README und `agent/send.ts`, Blobs `b4559548ecd5d4c7c261b72eb92dfafd437e2847` / `6cff3c921d92da5419dbfb14c0a4c2bfe6abcb11` | Getestet iPhone12mini/iOS14.2.1, Jailbreak/Frida; Transportzustand und Hooks in CommCenter. Kein direkt portabler normaler IPA-Zugang. Alte Adressen/Typen wurden nicht übernommen |
| [CellGuard Entitlements](https://github.com/seemoo-lab/CellGuard/blob/main/CellGuardAppSwift/entitlements-deb.plist), Blob `cebde9098ad96146714f65ea95975569528c4e95` | Plattform-/Container-/IOKit-Ausnahmen in .deb-Konfiguration; TrollStore-Variante dagegen nur Identität/GetTaskAllow | Unterschiede zwischen Verteilungsformen nicht auf unsere offizielle Ad-Hoc-Signatur übertragen |
| [Jonathan Levins eigenes Entitlement-Inventar](https://newosxbook.com/ent.php?exec=AppleDeviceQueryService&osVer=iOS18) | AppleBasebandPCI/PCIControl.user-access, CommCenter.fine-grained und IOKit-Klassen im iOS18-Systemdienst | Belegt konkrete Namen aus einer Reverse-Engineering-Primärquelle, nicht dass LoRaLab diese Rechte hat oder iOS27.2 identisch ist |
| [TrollStore](https://github.com/opa334/TrollStore), README-Blob `641fa955960a2afd6f4bacd83676874d045d5015` | Support 14.0b2–16.6.1, 16.7RC, 17.0 | Kein belegter Weg für das gemeldete iOS27.2; nicht eingebaut |
| [Dopamine 3.x](https://github.com/opa334/Dopamine/tree/3.x), README-Blob `b6fea8a2586578d9a334b3392e0e7043e80c8681` | arm64e-Support bis17.3.1; erweiterte18.7.1/26.0.1-Angaben sind hardwareabhängig,26 hierA12/A13 | Kein dokumentierter A17/iOS27.2-Zugang. Repository-Metadaten allein wären irreführend; README auf dem echten Defaultbranch3.x gelesen |
| [Nugget](https://github.com/leminlimez/Nugget), README-Blob `35f304caf126fe209c612f77c9a6b30073a5afd8` | Eigener ausdrücklicher Ausschluss von iOS27, Partial-Restore-Methode dort gepatcht; Carriername ist unter Statusleistenfunktionen gelistet | Keine Übernahme dieses Restore-Ansatzes. Ein anderer angezeigter Carriername ist kein Modem-Providerprivileg |
| [misaka26](https://github.com/straight-tamago/misaka26), README-Blob `4c330c299ea07e9a1459b492ff56e240c6920b6c` | Beschriebener Support16.0–26.1/26.2b1, MobileGestalt-/Konfigurationsfunktionen | Kein belegter iOS27.2-I/Q-Weg. Ein „SRD“-Featureflag ist kein Nachweis für produktive Baseband-Debugrechte |

Die Tabelle ist eine gezielte Prüfung veröffentlichter Ansätze, kein Beweis, dass keine weitere oder unbekannte Schwachstelle existiert. Es wurde keine Schwachstelle auf Roberts Gerät ausgenutzt.

## Hypothese: eigenen Carrier installieren

[Apple beschreibt Carrier-Updates](https://support.apple.com/en-us/109324) als Netz-/Dienstekonfiguration etwa für5G oderWi-FiCalling. [ideviceinstaller](https://github.com/libimobiledevice/ideviceinstaller) unterstützt real den Pakettyp `CarrierBundle` für `.ipcc`. Das belegt einen Pakettransportweg, nicht dass ein beliebiges unsigniertes Bundle auf iOS27.2 akzeptiert wird oder native Modem-Codeausführung liefert. Eine solche Installation wurde nicht ausprobiert.

Ein eigener APN, Carriername, ein Konfigurationsprofil oder andere Netzeinstellungen implementieren keinen LoRa-PHY und geben nicht automatisch ADC-Samples heraus. Dieser Schluss folgt aus den getrennten Schichten und dem fehlenden Sample-Transportnachweis; er ist keine vollständige Analyse jedes proprietären Carrier-Konfigurationsschlüssels. Offen bleibt, ob eine tatsächlich akzeptierte Debug-Konfiguration zusätzliche Log-/Capture-Dienste aktivieren könnte. Dafür muss ein konkreter Schlüssel samt Handler und Samplequelle belegt werden. Keine Carrier-Schlüssel oder Diagnosekommandos wurden geraten.

## Nächster verwertbarer Geräteschritt

Version0.3 installieren, mindestens60 Sekunden im Vordergrund geöffnet lassen, Gesamtbericht teilen. Gesucht sind konkrete positive Sichtbarkeitsbefunde, ausgewertete eigene Rechte und exakte Ablehnungscodes. Diese Befunde können den nächsten versionsgebundenen Zugriffstest eingrenzen; sie sind selbst noch kein Capture. Firmwareseitig bleibt die Kette Mav23-Capture-Deskriptor → Handler → Antennen-/Loopback-Quelle → Puffer/Export offen.

Erst ein belegter RF-Lieferant rechtfertigt ein Aufnahmeformat mit Samplerate, Mittenfrequenz, Zeitstempeln und Verlustnachweis. 60sCF32LE bei250kSamples/s wären120MB; die bisherige8-MiB-Dateianalyse ist kein Langzeitrecorder. Bei einem späteren echten Stream ist Streaming/Ringpuffer erforderlich.
