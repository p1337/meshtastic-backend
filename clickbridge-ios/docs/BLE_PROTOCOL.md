# BLE-Protokoll und Beleglage

Referenz: MIT-lizenziertes [TrainerHUD](https://github.com/hugoBourretDesmarais/TrainerHUD/tree/fd57f0eb1dd2e15a734e0e976ff6eb7fcb7e3df0), insbesondere `ZwiftProtocol.swift`, `ControllerDevice.swift`, `Util/SelfTest.swift`. BikeControl wurde zum Vergleich gelesen; sein aktueller Code und seine private Unlock-Implementierung sind nicht enthalten. Keine lokalen Hardwaremitschnitte vorhanden.

## GATT

| UUID | Beobachtete Funktion | Verhalten in ClickBridge |
|---|---|---|
| `FC82` | v2-Service | Gefilterter Scan, bevorzugter proprietärer Service |
| `00000001-19CA-4651-86E5-FA29DCDD09D1` | älterer proprietärer Service | Discovery-Fallback, kein Versprechen für Click v1 |
| `00000002-19CA-4651-86E5-FA29DCDD09D1` | asynchron, Notify | Abonnieren, empfangene Pakete validieren |
| `00000003-19CA-4651-86E5-FA29DCDD09D1` | synchrones RX, Write Without Response | Ausschließlich freigegebene Kommandos; Eigenschaften und Flusskontrolle prüfen |
| `00000004-19CA-4651-86E5-FA29DCDD09D1` | synchrones TX, Read / Indicate | Indicate/Notify abonnieren; keine Entsperrung aus einem gecachten Read ableiten |
| `00000100`, `00000101`, `00000102` derselben Basis | Bedeutung nicht verifiziert | Eigenschaften protokollieren; keine Writes und keine geratenen Funktionen |
| `2A19` | Battery Level | Read, falls vorhanden Notify, 0–100 validieren |
| `2A26`, `2A27` | Firmware / Hardware Revision | Read als UTF-8, keine Firmwareänderung |

Hersteller-ID little endian `4A 09`; nächstes Byte `0A` für rechten, `0B` für linken Click V2 laut Referenzen. Fehlende Herstellerdaten erzeugen keine erfundene Seite. Seitenzuordnung ist explizit und eindeutig; es gibt keine RSSI-basierte Identitätsheuristik.

## Gesendete Bytes — vollständige Allowlist

| Bytes | Zweck | Beleg / Grenze |
|---|---|---|
| `52 69 64 65 4F 6E` | `RideOn`-Initialisierung | TrainerHUD `sendRideOn()`, Incyclist unverschlüsselter Pairingpfad. Erst nach beiden Subscription-Bestätigungen. Unterstützt nicht jede Firmware. |
| `00 08 00` | Geräteinformationen anfordern | TrainerHUD `getDeviceInfo`. Opportunistischer Healthcheck im Vordergrund, keine garantierte Hintergrundfreischaltung. |

Keine Reset-Schleifen, Freischalt-Token, Haptik-, DFU- oder Trainerkommandos. Andere Bytes werden am Sendepfad blockiert. Eine Write-Without-Response-Übergabe ist keine Zustell- oder Ausführungsbestätigung.

## Empfang

`RideOn` oder `RideOn 02 03` bestätigt nur die unterstützte Initialisierungsform. Zusätzliche Key-Bytes markieren eine nicht implementierte verschlüsselte Variante. Es wird kein Schlüssel ignoriert und trotzdem Bereitschaft behauptet.

`0x23`: danach Protobuf-Wire-Format. Feld 1 (Varint uint32) ist ein active-low Bitmap: 0 bedeutet gedrückt. Eine fehlende Bitmap darf niemals als 0 und damit „alles gedrückt“ interpretiert werden. Doppeltes Feld 1, ungültiger Wire-Typ, Überlauf, zu großes oder abgeschnittenes Paket werden verworfen. Maximale Paketlänge 512 Bytes. Es gibt keine spekulative Fragmentverkettung ohne nachgewiesene Framingregeln.

| Bit | Taste |
|---|---|
| `0x0001`, `0x0002`, `0x0004`, `0x0008` | Links, Oben, Rechts, Unten |
| `0x0010`, `0x0020`, `0x0040`, `0x0080` | A, B, Y, Z |
| `0x0100` | Minus / linker Schalter |
| `0x1000` | Plus / rechter Schalter |

Weitere Ride-Paddles/Buttons werden nicht als Click-V2-Tasten ausgegeben. `0x19`, Feld 2, liefert Batterie in Prozent. `0x15` wird als Idle behandelt. `0xFE` markiert Kontrollverlust. Die bekannten Stop-Frames `FF 05 00 EA 05` und `FF 05 00 FA 05` sperren die Ereignisausgabe. Andere Opcodes bleiben Diagnose ohne Wirkung.

## Testdaten und Herkunft

`Tests/ClickBridgeCoreTests/Fixtures/reference-vectors.json` enthält zwei TrainerHUD-Capture-Vektoren (Navigation links und Idle, **nicht als lokale Click-V2-Messungen bezeichnet**) und zwei synthetische Minus-/Plus-Pakete. Weitere Tests konstruieren Bitmap-Kombinationen und fehlerhafte Wire-Daten. Damit werden Decoder und Grenzen geprüft; kein Funkverkehr oder Firmwarebetrieb simuliert und als Hardwaretest ausgegeben.

## Zeitabhängiger Ausfall links

Die Referenzprojekte beschreiben einen firmwareabhängigen Eingabeausfall nach etwa einer Minute trotz bestehender Verbindung. Bluetooth-Verbindung und initiale Tasten sind daher keine Stabilitätsabnahme. ClickBridge erkennt explizite Stop-Meldungen, dokumentiert Timeouts und fordert beim Vordergrundcheck einen erneuten linken Tastentest an. Stille kann auch Nichtbenutzung bedeuten; daraus wird keine sichere Sperrdiagnose erfunden. Ein zuverlässiger Offline-Dauerbetrieb beider Pucks bleibt offen.
