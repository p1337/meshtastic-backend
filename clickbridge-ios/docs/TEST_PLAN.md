# Testplan und Abnahme

## Automatisierte Softwaretests

`swift test`: 20 XCTest-Methoden für Referenzpakete, alle unterstützten Tasten und Kombinationen, abgeschnittene Pakete, fehlende/doppelte Bitmap, Überläufe, Unknown-Fields, Handshakevarianten, Batteriegrenzen, Herstellerdaten, eindeutige persistierte Zuordnung, Flankenerkennung, Entprellen, langen Druck, zwei unabhängige Tracker, Reconnect-Limits, späte Zustandsereignisse, Ganggrenzen, Ratio-Indizierung, quittierte Zustandsänderung, fehlerhafte Einstellungen und Persistenz.

`node --test integrations/incyclist/shiftRouter.test.cjs`: sieben Tests für tatsächlichen Aufruf des bestehenden Softwarepfads, beide Richtungen, Duplikate, Gültigkeitsdauer, Fahrsitzung, deaktivierte virtuelle Schaltung/ERG, Traineranzahl, Busy-Zustand, Serialisierung, Transportfehler und begrenzte Queue. Testdoubles sind ausdrücklich Softwaredoubles, keine Trainer.

CI: macOS-Runner kompiliert CoreBluetooth und SwiftUI, validiert deterministische Projektgenerierung, baut/startet Simulator-App und erstellt eine unsignierte Geräte-IPA. Screenshot/Smoke-JSON sind Belege eines Appstarts, keine Bluetooth- oder Widerstandsmessungen. Der Incyclist-Patch wird separat auf den festgelegten Quellstand angewendet.

## Vor jedem Gerätetest erfassen

iPhone-Modell, exakte iOS-Version und Buildnummer; ClickBridge-Commit; Incyclist-Version/Build (unverändert oder Integration); D100-Firmware; je Puck Firmware/Hardware und zugeordnete lokale Kennung; Zeitpunkt einer etwaigen vorherigen Zwift-Verbindung. Tests mit vorheriger Zwift-Freischaltung getrennt von Tests nach mindestens 24 Stunden ohne Zwift dokumentieren.

Nur die vorgesehene App soll Controller-Eigentümer sein. Incyclist bindet D100; ClickBridge bindet keinen Trainer. Im eingebetteten Build Clicks ausschließlich über die ClickBridge-Einrichtung zuweisen. Keine gleichzeitige Bindung im alten Incyclist-Controllerpicker.

## Verbindliche zehn Hardwarepunkte

| Nr. | Durchführung und Bestehensbedingung | Status |
|---|---|---|
| 1 | Beide Pucks einzeln aufwecken. Zwei getrennte lokale IDs im Scan, Seiten manuell gegenprüfen. | NICHT GETESTET |
| 2 | Beide verbinden, für jede Seite GATT, zwei Subscriptions und unterstützten Handshake protokollieren. | NICHT GETESTET |
| 3 | Links 100 einzelne Minus-Drücke, zusätzlich Halten/Loslassen. Je Druck genau ein Downshift-Wunsch, keine fremde Taste. Nach 65/120 s wiederholen. | NICHT GETESTET |
| 4 | Rechts entsprechend 100 Plus-Drücke; gleichzeitig/abwechselnd beide Seiten prüfen. | NICHT GETESTET |
| 5 | Incyclist auf genau demselben iPhone fahren lassen; Standalone-Hintergrundtest und eingebetteten Build getrennt führen. | NICHT GETESTET |
| 6 | D100 als Leistung/Kadenz und steuerbarer Trainer in Incyclist, kein zweiter Control-Point-Eigentümer. | NICHT GETESTET |
| 7 | Bei gleichbleibender Route/Kadenz je 5 Gänge hoch/runter. Incyclist-Ganganzeige und nachvollziehbare Last-/Leistungsänderung erfassen, anschließend wieder zum Startgang. | NICHT GETESTET |
| 8 | Danach Flachstück, Steigung und Abfahrt bei gleichem Gang fahren; Streckenlast bleibt wirksam und schaltet nicht unbemerkt in ERG/feste Last. | NICHT GETESTET |
| 9 | Mindestens 60 min, alle 30–60 s beide Schalter betätigen, Latenz/Ausfälle protokollieren. Beide Seiten auch nach längerer Ruhe zuverlässig. | NICHT GETESTET |
| 10 | Jeden Puck außer Reichweite, zurückkehren, erneutes Schalten ohne Neuzuordnung. Bluetooth-Aus/Ein separat. | NICHT GETESTET |

Kein positiver Gesamtstatus, bevor alle zehn Punkte bestanden sind. Ein bloßer Ganganzeigewechsel in ClickBridge erfüllt Punkt 7 nicht. Für „ohne Cloudpflicht“ muss die Fahrt ohne vorherige Zwift-Freischaltung stabil sein. Sollte Freischaltung erforderlich bleiben, ist die strikte Produktanforderung blockiert.

## Lebenszyklusmatrix — ebenfalls noch nicht getestet

| Situation | Prüfung | Unterstützte Erwartung / Grenze |
|---|---|---|
| Vordergrund | Beide Schalter, Diagnoseexport | BLE-Ereignisse und Softwarepfad messen |
| ClickBridge Hintergrund, Incyclist Vordergrund | 10 min beide Schalter | BLE-Zustellung prüfen; Standalone besitzt trotzdem keinen Incyclist-Ausgang |
| Bildschirm gesperrt | 5 min, danach Export | Keine Timer-/Dauerausführung voraussetzen; Incyclists eigener Trainingsbetrieb separat prüfen |
| Anruf | Annehmen/Beenden und weiterfahren | Unterbrechung und Wiederkehr protokollieren |
| Bluetooth 10 s aus | Danach wieder aktivieren | Wiederverbindung/Zuordnung erhalten |
| Controller außer Reichweite | Jede Seite einzeln | Die andere Sitzung bleibt unabhängig |
| Systembeendigung / Speicherdruck | Instrumentierter echter Gerätetest | Restoration nur bei passenden ausstehenden Bluetooth-Aufträgen und iOS-Freigabe |
| Benutzer-Force-Quit | App wegwischen | Kein automatischer Neustart versprechen; manuell öffnen |

## Ergebnisvorlage

Pro Test: Test-ID, Datum, Commit, Geräte-/Firmwareversionen, vorherige Zwift-Verbindung ja/nein, Schritte, Erwartung, tatsächliches Ergebnis, PASS/FAIL/BLOCKED, Zeitstempel und Diagnose-Datei. Keine echten Hardwarekennungen oder privaten Fahrdaten in das öffentliche Repository einchecken.
