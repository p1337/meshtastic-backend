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

## Verifizierte Veröffentlichung0.3.0 (Build13)

Quellcommit `0664b6551eda353bbe568e04dc7c6da5f82e939b`; [vollständig erfolgreicher Cloud-Lauf](https://github.com/p1337/meshtastic-backend/actions/runs/39037447564). Native Regression und Zustandsprüfungen bestanden. SimulatoriOS18.5:835 Fälle/Messungen,0 fehlgeschlagene Gruppen,19 Auditbefunde; die Zeitdiagnose endete nach60,015663s mit58 tatsächlichen Statusabfragen und maximal1,074742s Abstand. JSON und Screenshot visuell/inhaltsseitig geprüft. Das ist keine Ausführung auf dem physischen iPhone.

Apple-Distribution-Signatur, arm64-Geräteplattform und Ad-Hoc-Profil für ein Gerät wurden im Build verifiziert. Veröffentlichte IPA zusätzlich perHTTPS heruntergeladen:701577Bytes, SHA256 `cbde0512696918606a7efd1cc330b65ebcd43765fc3a884ea9a1980e014dd521`. Manifest-, Seiten- und IPA-Abruf erfolgreich; Bundle0.3.0/13 und Icon geprüft. Profilablauf17.10.2027,11:36:45UTC. [Installieren](https://p1337.github.io/meshtastic-backend/?build=13). Noch kein Nutzerbericht zur physischen0.3-Ausführung.

## Weiterer Ansatz: eSIM und SIM Toolkit

[Apples Anbieter-API](https://developer.apple.com/documentation/coretelephony/ctcellularplanprovisioning/) setzt `com.apple.CommCenter.fine-grained` mit `public-cellular-plan` voraus. Unsere App liest diesen bestehenden Schlüssel, beantragt oder fälscht ihn nicht. Ein legitimes eSIM-Profil über iOS-Einstellungen zu installieren und als eigene App Carrier-Rechte zu besitzen sind unterschiedliche Dinge. Keine eSIM wurde erzeugt, angeboten oder auf das Telefon geladen.

Die gewöhnliche Netz-/Anbieterauswahl ist kein freier CSS-Demodulator und stellt noch keinen ADC-Transport zur App bereit. Ein RX-Tuning im passenden Mobilfunkband wäre nur ein Teilnachweis.

Ein konkreter zusätzlicher Ansatz ist [ETSI TS102223V17.6.0,6.4.23](https://www.etsi.org/deliver/etsi_ts/102200_102299/102223/17.06.00_60/ts_102223v170600p.pdf): Die UICC kann unter dort genannten Unterstützungs-/Aktivierungsvoraussetzungen einen AT-Befehl ans Endgerät geben. Das belegt weder iPhone-Freigabe noch ein vendor-spezifisches RF-Capturekommando. Als nächstes wäre das tatsächliche TERMINAL PROFILE bzw. der CAT-Handler zu prüfen.

**Neuer eigener statischer Befund:** Beide gehashten Mav23-DSP-Images enthalten die Literale RUN AT COMMAND, TERMINAL PROFILE und qmi_cati_get_terminal_profile. Der reproduzierbare [Probe-Code](research/sim-toolkit-probe.py) wurde gegen vier Images ausgeführt. In den zwei ARM-apps.mbn keine Treffer dieser Literale; das widerlegt keine komprimierten/anders benannten Funktionen. In den beiden DSP-Images gibt es passende Zeichenketten, noch keine rekonstruierte Aufrufkette.

| DSP | Dateioffset RUN AT COMMAND | Dateioffset qmi_cati_get_terminal_profile |
| --- | ---: | ---: |
| Mav23-1.00.03 |102713686|102744011|
| Mav23-4.02.04 |103697630|103728131|

Offsets sind Dateibytepositionen, keine Register, Befehlsnummern oder bestätigten Funktionseinstiege. Das geprüfte BaseTrace qmi-service-cat.json enthält keinen GetTerminalProfile-Request. Kein Request oder AT-Capturebefehl wurde daraus erfunden.

## Tatsächlich gelesenes Apple-Diagnoseprofil

[CellGuards eigener Quellcode](https://github.com/seemoo-lab/CellGuard/blob/main/CellGuardAppSwift/CellGuard/API/CellGuardURLs.swift) verweist auf den öffentlichen [Profilspiegel](https://cellguard.seemoo.de/repo/profile/Baseband.mobileconfig). Diese veröffentlichte Kopie wurde heruntergeladen und offline geprüft:17230Bytes, SHA256 `ab7b7a71c89d5b0cc67cd826d533958e02cea015a5715a4cacce78f786f7110f`.

CMS-Signatur und Zertifikatspfad wurden mit OpenSSL gegen die direkt von Apple geladene [Apple Root CA](https://www.apple.com/appleca/AppleIncRootCertificate.cer) erfolgreich validiert (`-purpose any`; keine vollständige Reimplementierung der iOS-Profilpolicy). Root-DER-SHA256 `b0b1730ecbc7ff4505142c49f1295e6eda6bcaed7e2c68c5be91b5a11001f024`. Signierer: AppleCare Profile Signing Certificate; Zwischenstelle: Apple Application Integration2 Certification Authority. Nicht als die aktuellste Apple-Downloadversion oder als auf Roberts Telefon installiert behaupten.

Payload: Baseband and Telephony Logging; com.apple.system.logging sowie com.apple.defaults.managed / Domain com.apple.commcenter. Enthalten sind `EnableBasebandLogging` mit History8/Profile1/Sleep0, TelephonyLoggingPriority3 und TelephonyLoggingVersion18. DurationUntilRemoval604800Sekunden betrifft dieses Diagnoseprofil, nicht die Jahresgültigkeit unserer Appsignierung. AbsoluteRemovalDate13.02.2027,08:00UTC. Mehrere Loggingbereiche einschließlich CommCenter/SIMSetupSupport/Messages werden erweitert und auf Public gesetzt; vollständige Systemlogs deshalb nicht ungefiltert anfordern.

Das Profil ist ein echter, nun inhaltlich verifizierter Loggingweg. Seine tatsächliche Wirkung unter iOS27.2 und nutzbare RF-I/Q-Daten sind weiterhin nicht nachgewiesen. Ein Profile1-Wert wird nicht als frei konfigurierbarer Capturemodus interpretiert. [CellGuards Profilprüfung](https://github.com/seemoo-lab/CellGuard/blob/main/CellGuardAppSwift/CellGuard/System%20Diagnoses/ProfileTask.swift) beobachtet `/private/var/preferences/Logging/Subsystems/com.apple.CommCenter.plist`; unsere0.3-App behauptet noch keine Installationserkennung dafür.

Nächster gezielter Versuch:0.3-Gerätebericht auswerten; dann ggf. vorhandenes Apple-Logging mit einem lokalen, identitätsarmen Filter auf CAT/TERMINAL-PROFILE-Befunde untersuchen. Erst tatsächliche Karten-/Terminalfähigkeit und Vendor-Handler bestimmen. Kein ungeprüftes Carrierprofil, keine erfundene eSIM und kein blindes Durchprobieren von AT-/FTM-Befehlen.

