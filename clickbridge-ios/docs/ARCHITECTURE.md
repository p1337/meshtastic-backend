# Architekturentscheidung ADR-001

Entscheidung: **eingebettete BLE-Integration in Incyclist**, Standalone-App zunächst für Controllerdiagnose. Parallelsteuerung des D100 bleibt ausgeschlossen, bis ein unabhängiger kooperativer Steuerpfad nachgewiesen wäre.

## Module

| Modul | Verantwortung | Bewusste Grenze |
|---|---|---|
| `ClickBridgeCore` | Herstelleridentität, dauerhafte Seitenzuordnung, strenger Wire-Decoder, Entprellen, Langdruck, Zustandsautomat, Wiederverbindung, Gangkonfiguration und quittierte Softwarezustände | Keine Apple-Frameworks, kein Netzwerk, kein BLE-I/O |
| `ClickBridgeBLE` | Ein CoreBluetooth-Central, separate Sitzungen je Peripheral, GATT, Subscription, freigegebene Initialisierung, Diagnose, Wiederherstellung | Keine Trainerverbindung oder Incyclist-IPC |
| `App` | SwiftUI/MVVM, Dashboard, Zuordnung, Einstellungen, Diagnoseexport | Anzeige eines aktuellen Gangs bleibt leer, solange kein Ausgang bestätigt wurde |
| `integrations/incyclist` | Native React-Native-Brücke, eingebettete Einrichtung, kontrollierte Weiterleitung an bestehende Schaltlogik | Benötigt geänderten Incyclist-Build; Software-Promise ist keine Trainerbestätigung |

## Datenpfad

1. CoreBluetooth empfängt ein Paket der einem Controller zugeordneten Characteristic.
2. Nur gültige, vollständige `0x23`-Pakete erzeugen Tastenzustände. Fehler/Unbekanntes gehen in das Protokoll.
3. Ein Tracker je Controller dedupliziert Frames und liefert Tastenflanken. Jeder Puck liefert nur Tasten seiner zugeordneten Seite.
4. Standalone: Diagnose protokolliert den Schaltwunsch mit „kein Integrationsausgang“.
5. Eingebettet: Aktive Incyclist-Fahrsitzung → NativeEventEmitter → begrenzter serieller Router → `sendUpdate({gearDelta})`.
6. Incyclist setzt seinen CyclingMode und Traineradapter ein. Route und Übersetzung gelangen weiterhin durch denselben Eigentümer zum Trainer.

Der eingebettete Adapter nutzt zunächst Incyclists Ganganzahl und Übersetzungen. Eigene 2–64-Gang-Konfiguration ist im eigenständigen Core fertig implementiert und getestet; sie überschreibt **nicht** ungeprüft die Gangtabelle des fremden CyclingMode. Diese Anpassung wäre eine weitere Incyclist-Änderung.

## Zustände und Fehler

`discovered → connecting → discovering → subscribing → initializing → awaitingInput → receiving`. Jeder Zustand kann nach `disconnected` oder `attention` wechseln. Späte Tastenpakete nach Trennung, verschlüsselte Handshakes, fehlende Bitmap, mehrdeutige Bitmap und Protokoll-Stop werden nicht als Gangschaltung behandelt.

Zwei Notify-Abonnements müssen bestätigt sein, bevor das Initialisierungskommando gesendet wird. Bei Writes ohne Response wird CoreBluetooth-Flusskontrolle beachtet. Verbindungs-, GATT- und Handshake-Timeouts sind endlich. Wiederverbindung hat maximal acht Versuche mit 1/2/4/8/16/32/60/60 Sekunden geplantem Abstand. Hintergrundausführung dieser Timer ist nicht garantiert; ausstehende CoreBluetooth-Aufträge und Wiederherstellung ergänzen dies.

## Hintergrund und Lebenszyklus

Central wird beim Appstart erzeugt; im Incyclist-Patch vor React Native. Restoration verwendet eine eigene Kennung pro Host. Wiederhergestellte Peripherals werden neu an Delegates gebunden und durchlaufen GATT/Subscriptions erneut. Ein alter Handshake wird nicht blind übernommen. Manuelles Trennen entfernt die automatische Verbindungsabsicht. Bluetooth-Aus setzt Transportzustände zurück.

Zeitgesteuerte Keep-alives laufen nicht als angeblich zuverlässiger Hintergrunddienst. Ein freigegebener Device-Info-Read wird beim Vordergrund-Healthcheck opportunistisch gesendet. Langer Tastendruck wird anhand echter Press-/Release-Zeitpunkte erkannt, erst beim Loslassen gemeldet und erzeugt keine zusätzliche Standardschaltung.

## Persistenz und Datenschutz

Zuordnung und Einstellungen: lokales UserDefaults mit versionierten Schlüsseln. Letzter Softwaregang ist historische Information; er wird beim Appstart nicht als live bestätigter Gang dargestellt. BLE-Identitäten werden nicht als MAC-Adressen ausgegeben. Lokale UUIDs können nach Neuinstallation/Identitätswechsel eine neue Zuordnung erfordern.

Diagnose: JSONL, maximal zwei Dateien mit je etwa 2 MiB plus letzter Eintrag; Speicherliste auf 600 Einträge begrenzt. Dateischutz auf iOS bis zur ersten Geräteentsperrung. Export enthält lokale Kennungsfragmente und Firmware/Tastendaten, bleibt bis zur bewussten Freigabe lokal. Keine Telemetrie, HTTP-Clients, Konten, SDK-Tracker oder Cloudzugriffe.

## Nicht implementierte oder unbewiesene Produktteile

Kein Standalone-Ausgang zur veröffentlichten Incyclist-App; keine Firmware-Entsperrung des linken Pucks; keine verschlüsselte ältere Controllerprotokollvariante; keine Geräteabnahme; kein StoreKit-Verkauf und keine App-Store-Einreichung. Diese Punkte sind sichtbare Release-Grenzen.
