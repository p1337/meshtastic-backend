# Kompatibilität

| Kombination | Nachgewiesener Stand |
|---|---|
| iOS 18+ | Mindestziel für verwendete SwiftUI/CoreBluetooth-APIs. Compiler-/Simulatorbelege stehen in VALIDATION.md. |
| Roberts iPhone / iOS 27 | Kein angeschlossenes Gerät, nicht getestet; keine gesonderte iOS-27-Kompatibilitätszusage. |
| Click V2 rechts (`0A`) | Protokollreferenzen vorhanden, Decoder implementiert; physisches Gerät nicht getestet. |
| Click V2 links (`0B`) | Decoder und eigene Sitzung implementiert; bekannte zeitabhängige Sperre ungelöst und firmwareabhängig. |
| Zwei gleichnamige Click V2 | UUID-basierte Trennung und eindeutige Seitenzuordnung implementiert; reale gleichzeitige Verbindung nicht geprüft. |
| Click v1 / Play / Ride | Nicht Produktumfang dieses Prototyps. Gemeinsame UUID bedeutet keine vollständige Unterstützung. |
| Verschlüsselte Controller-Firmware | Wird als nicht unterstützt gemeldet; keine simulierte Entschlüsselung. |
| Van Rysel D100 + Cog | ClickBridge enthält keinen Trainerzugriff. Tatsächliche Incyclist-Schaltung und Streckenlast nicht getestet. |
| Van Rysel D500 V2 | Nur in TrainerHUD-README als getestet genannt. Kein Ersatzbeleg für D100 oder iOS. |
| Unveränderte Incyclist-iOS-App | Kein dokumentierter lokaler Steuerendpunkt nachgewiesen; Standalone-Schaltung blockiert. |
| Incyclist mit eingebettetem Modul | Quellpatch vorbereitet; Aufruf des internen Schaltpfads im Softwaretest geprüft. Vollständiger Native-Build und Hardwaretest separat erforderlich. |
| Incyclist ERG-Workout | Eingebetteter Router verweigert Gangereignisse; kein heimlicher Wechsel der Leistungsregelung. |
| Keine Internetverbindung | ClickBridge-App und BLE-Baustein benötigen keinen Netzwerkdienst. Langzeitbetrieb beider Pucks ohne vorherige externe Freischaltung ist unbewiesen. |

Firmwareupdates können GATT, Initialisierung oder Sperrverhalten ändern. Vor einem Update vorhandene Version und Diagnose sichern; eine neue Version wird zunächst in der Hardwarematrix geprüft. Keine automatische Firmwareänderung oder pauschale Updateaufforderung.
