# ClickBridge — nachgewiesener Stand

Stand: 23.10.2026. Ergebnis: **Software-Prototyp möglich; Zielkombination auf realer Hardware nicht nachgewiesen. Kein Verkaufsrelease.**

## Entscheidung

**A: Integration in Incyclist verfolgen.** Der BLE-Baustein kann als Swift Package in die native iOS-Hülle eingebunden werden. Incyclist ist React Native/TypeScript, kein SwiftUI-Projekt; ein React-Native-Modul ist daher erforderlich. Eine separat installierte ClickBridge-App kann die unveränderte Incyclist-App derzeit über keine nachgewiesene öffentliche lokale Eingabeschnittstelle schalten. Eine Incyclist-Änderung muss vom Projekt übernommen oder als eigener Build installiert werden.

**B: parallele D100-Steuerung gesperrt.** Zwei BLE-Verbindungen sind keine zwei konfliktfreien Kontrollrechte. FTMS-Control-Point-Befehle der zweiten App könnten die SIM-/ERG-Befehle der ersten überschreiben. Es gibt keinen D100-Nachweis über unabhängige, gleichzeitig nutzbare Steuerpfade, keine nachgewiesene Zusammenführung von Strecke und Übersetzung und hier keinen Hardwarezugriff. ClickBridge verbindet sich deshalb nicht mit dem Trainer und sendet keine Trainerkommandos.

**C: kein vorhandener öffentlicher Eingabe-Endpunkt gefunden.** Die geprüften Quellen enthalten BLE, UI-Gesten, interne Events, MQTT und Backend-Kommunikation. Diese sind kein dokumentierter lokaler Steuervertrag für eine zweite iOS-App. Der Vorschlag in `INCYCLIST_INTEGRATION.md` bevorzugt ein eingebettetes Modul; eine spätere IPC-Schnittstelle ist ausdrücklich ein Vorschlag.

Zusätzlich geprüft: `incyclist/documentation@c2069a99c7144c51f90750bf3def6efec1210ea3` und `incyclist/web-ui@063dd1790f5ad95abc4ca01f010787d1b3fe44db`. Die mobile Info.plist nennt `_openbikecontrol._tcp` als erlaubten Bonjour-Typ und registriert `incyclist://`. Das allein ist kein implementierter Schaltendpunkt. Der geprüfte mDNS-Binding-/Direct-Connect-Pfad sucht Direct-Connect-Trainerdienste; ein OpenBikeControl-Eingabehandler oder URL-Gangkommando ist in diesen Quellständen nicht nachgewiesen.

## Quellenstand (tatsächlich geklont und gelesen)

| Projekt | Commit | Relevante Dateien / Ergebnis |
|---|---|---|
| [incyclist/devices](https://github.com/incyclist/devices) | `fc33350859f9b4089548c546e3b862a2df668e1f` | `src/ble/zwift/play/sensor.ts`, `adapter.ts`, `src/modes/antble-smarttrainer.ts`: vorhandene Click-v1-/Play-/Ride-Logik, 24 Übersetzungen, Modi `Incyclist`, `SmartTrainer`, `Mixed`. Keine expliziten Click-v2-Typen 0A/0B und keine FC82-Erkennung in diesem Sensor. Herstellertyp wird fehlerhaft aus Zeichen 2–4 statt 4–6 des Hexstrings gelesen. |
| [incyclist/services](https://github.com/incyclist/services) | `ab878e216c67167e3149de50f27a42697ff53f3b` | `src/devices/ride/service.ts`: `sendUpdate({gearDelta})` nutzt die bestehenden gestarteten Traineradapter und aktualisiert `gearStr`; `src/ride/display/service.ts`: interne Gang-/Leistungssteuerung. Das ist eine interne API, keine IPC-Schnittstelle. |
| [incyclist/mobile](https://github.com/incyclist/mobile) | `1969e6442a9ae807b1f9ae0b9cd865400d7d6873` | React Native 0.83.10, `react-native-ble-manager`, `ios/Incyclist/AppDelegate.swift`, `src/pages/RidePage/RidePage.tsx`. Quellversion 1.0.9; keine Aussage über die tatsächlich auf Roberts iPhone installierte Binary. Mindestziel des bestehenden Projekts 15.5; ClickBridge-Einbettung hebt es auf 18 an. |
| [OpenBikeControl/bikecontrol](https://github.com/OpenBikeControl/bikecontrol) | `f461fa22813b6f0de4543ce0b18cb2333a32e30a` | `lib/bluetooth/devices/zwift/`: zwei v2-Typen, FC82, separate Seiten. Linker Puck mit zeitabhängiger Sperre; Teile der neueren Logik im privaten `prop`-Submodul. Aktuelle Lizenz verbietet kommerzielle Übernahme ohne Erlaubnis. Kein Code übernommen. |
| [zubinkavarana/swiftcontrol](https://github.com/zubinkavarana/swiftcontrol) | `284d2ca70fef11ffff5ad56dda0a8ebaff92ec94` | Älterer Flutter-Fork, GPL-3.0; README schließt Steuerung einer zweiten App auf demselben iPhone per Touch/HID aus. Kein Code übernommen. |
| [hugoBourretDesmarais/TrainerHUD](https://github.com/hugoBourretDesmarais/TrainerHUD) | `fd57f0eb1dd2e15a734e0e976ff6eb7fcb7e3df0` | MIT, eigenständige macOS-App. `ZwiftProtocol.swift`, `ControllerDevice.swift`, `SelfTest.swift` liefern überprüfbare Protokollreferenzen. README nennt **D500 V2**, nicht D100, als getestet. Decoderwissen und zwei Capture-Vektoren mit Attribution verwendet. |

Die Repositories können weitergehen als die veröffentlichte iOS-Version. Aus dem Quellcode lässt sich **keine verifizierte Click-v2-Unterstützung der installierten Incyclist-App** ableiten. Version/Build und Firmware müssen im Hardwareprotokoll erfasst werden.

## Tatsächlicher Schaltpfad

Eingebettet: Click V2 → CoreBluetooth → strenger Paketdecoder → dedupliziertes Tastendruckereignis → React-Native-Brücke → Incyclist `useDeviceRide().sendUpdate({gearDelta})` → vorhandener CyclingMode → derselbe Traineradapter. Incyclist bleibt Eigentümer seiner Strecken-/Trainingssteuerung. Eine erfolgreiche JS-Promise beweist nur die Softwareweiterleitung, keine physikalische Widerstandsänderung.

Standalone: Click V2 → Diagnose. Es gibt **keinen aktiven Ausgang zu Incyclist**. Dashboard, Fehlermeldungen und deaktivierte Gangtasten machen diesen Zustand sichtbar. Keine vorgetäuschten Gangbestätigungen.

## Protokoll und linke Seite

FC82 plus proprietäre Notify-/Write-/Indicate-Characteristics sind in den Referenzimplementierungen bestätigt. Herstellerdaten `4A 09 0A …` / `4A 09 0B …` erlauben eine Seitenvermutung. Name oder RSSI sind keine Identität. Gespeichert wird die lokale CoreBluetooth-UUID; manuelle Zuordnung bleibt möglich, nach Neuinstallation/Adresswechsel eventuell erneut notwendig.

[BikeControl #68](https://github.com/OpenBikeControl/bikecontrol/issues/68) dokumentiert den Ausfall von Tastenereignissen nach etwa einer Minute. Neuere Quelldateien und TrainerHUD beschreiben den rechten Puck als unabhängig nutzbar, beim linken weiterhin Zwift-Freischaltung oder Neustarts. Diese Beobachtungen sind firmwareabhängig. Kein Dauerbetrieb beider Seiten ohne Zwift-Abhängigkeit nachgewiesen. ClickBridge implementiert **keine periodischen Firmware-Resets oder nicht verstandenen Freischaltsequenzen**. Es meldet Handshake-/Eingabeprobleme und protokolliert bekannte Stop-Meldungen. Auch eine erfolgreiche Initialisierung ist kein Entsperrnachweis.

## Öffentliche iOS-Funktionen

Verwendet: CoreBluetooth Central, `bluetooth-central`, Restoration-Identifier und `willRestoreState`. Mehrere Peripherals können eigene GATT-Sitzungen haben; eine garantierte Gerätezahl oder D100-Koexistenz folgt daraus nicht.

[Apple Background Guide](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html): BLE-Ereignisse dürfen die App im Hintergrund wecken, Scans werden eingeschränkt und zusammengefasst; keine garantierte Dauerausführung und keine verlässlichen Hintergrundtimer. [TN3115](https://developer.apple.com/documentation/technotes/tn3115-bluetooth-state-restoration-app-relaunch-rules): Wiederstart hängt von Beendigungsgrund und ausstehenden BLE-Aufträgen ab. Nach Benutzer-Force-Quit ist manuelles Öffnen erforderlich. Sperrbildschirm, Telefonat und Speicherdruck benötigen Gerätetests.

Keine öffentlichen APIs zur systemweiten Touch-Injektion; keine lokale Bluetooth-HID-Schleife, keine private API, keine Audio-Endlosschleife zum Wachhalten. URLs würden die andere App öffnen und bieten hier keinen belegten unterbrechungsfreien Schaltpfad. App Groups können fremde Apps nicht ohne gemeinsame Berechtigungen verbinden.

## Build und Signierung

Vorhandenes Repository `p1337/meshtastic-backend`, Basis `codex/native-lora-ios`, neue Arbeit in `codex/clickbridge-ios`, Ordner `clickbridge-ios`. GitHub-Connector kann weder neues Repository noch Apple-Profile/Secrets einrichten. Damit greift Roberts ausdrücklich erlaubter zweiter Weg.

Eigene Bundle-ID `de.p1337.ClickBridge`; **nicht** `de.p1337.LoRaLab`, weil dies Werkbeleg ersetzen würde. Das vorhandene Signing-Skript verlangt ein exakt auf LoRaLab gebundenes Ad-hoc-Profil. Ein Zertifikat kann mehrere Apps signieren, ein explizites App-Profil jedoch nicht. Ohne passendes neues Profil kann ein Simulator-Build und eine **unsignierte** IPA erstellt werden, keine als installierbar bezeichnete Apple-signierte zweite App. Es werden keine Schlüsselwerte gelesen, kopiert oder ausgegeben. Siehe `SIGNING.md`.

## Offene Abnahme

Kein iPhone, keine Clicks und kein D100 sind an diese Ausführungsumgebung angeschlossen. Die zehn Abnahmepunkte sind vollständig **NICHT GETESTET**. Softwaretests und Simulatorbelege werden getrennt geführt. Produktionsreife, App-Store-Zulassung, Offline-Dauerbetrieb beider Pucks und reale Fahrwirkung bleiben offen.
