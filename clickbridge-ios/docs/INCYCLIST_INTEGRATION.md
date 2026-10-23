# Konkrete Incyclist-Integration

## Was tatsächlich vorbereitet ist

Ein eigenständiges Swift Package und ein installierbarer Quellpatch gegen `incyclist/mobile@1969e6442a9ae807b1f9ae0b9cd865400d7d6873`. Ein lokaler Fork enthält die geänderte native Hülle, Paketabhängigkeiten, Bluetooth-Einrichtung und React-Native-Weiterleitung. Der vollständige Patch wird mitgeliefert; es wurde noch kein externer Incyclist-Fork auf GitHub angelegt und kein Upstream-PR abgeschickt. Der vorhandene Connector hat keine Repository-/Fork-Erstellfunktion. Der Entwurfs-PR im eigenen Repository ist kein vorgetäuschter Upstream-PR.

`integrations/incyclist/install.py` prüft den exakten Commit und einen sauberen Arbeitsbaum, bevor es Quelländerungen einfügt. Es kopiert das unabhängige Package in `clickbridge-kit`, aktualisiert Xcode und Pod-Mindestziel auf iOS 18, erzeugt die Brücke und ergänzt eine Einrichtungs-Schaltfläche im RidePage. Das ist ein konkreter Quellvorschlag, keine vorhandene Plugin-Schnittstelle in Incyclist.

## Ereignisvertrag innerhalb der App

`ClickBridgeShift`: eindeutige Event-ID, Fahrsitzungs-ID, `direction` ±1, Emissionszeitpunkt und logische Seite. Es gibt keinen Netzwerksocket oder URL-Endpunkt. Die NativeEventEmitter-Verbindung ist rein intern.

Der Router prüft bei der tatsächlichen Ausführung: aktive Fahrsitzung, passender Session-Token, Alter maximal 1,5 Sekunden, genau ein gestarteter/steuerbarer/nicht pausierter Traineradapter, SIM-Modus mit aktiver virtueller Schaltung und kein laufendes Incyclist-Update. Er dedupliziert IDs, serialisiert maximal acht Aufträge und verwirft alte Sitzungen beim Unmount. Endlosschleifen und nachgespielte Hintergrundkommandos sind ausgeschlossen.

Aufruf: `useDeviceRide().sendUpdate({gearDelta: direction})`. Kein paralleles BLE-FTMS, kein `targetPower`, keine Überschreibung der Steigung. Der bestehende Incyclist-CyclingMode bleibt für die Synthese von Fahrstrecke, Last und Gang verantwortlich.

**Wichtige Beweisgrenze:** Incyclist `waitForUpdateFinish()` verwendet im geprüften Stand `Promise.allSettled` und propagiert nicht jeden Adapterfehler. Das Adapterergebnis heißt daher `submitted` / „Schaltauftrag abgegeben“, niemals „Trainer bestätigt“. Auch `gearStr` ist nur der Softwarezustand. Die Hardwareabnahme muss reale Last-/Leistungsänderungen und erhaltene Streckensimulation prüfen.

## Einsatz

In der geänderten Incyclist-App D100 normal verbinden. Während einer Fahrt „ClickBridge“ öffnen, beide Pucks suchen, eindeutig links/rechts zuordnen und Tasten testen. Die alte Incyclist-Controllerverbindung für dieselben Pucks und die Standalone-App dürfen nicht gleichzeitig als Eigentümer eingerichtet werden. Die Standardbelegung ist Minus links herunter, Plus rechts hoch.

Der Integrationsprototyp verwendet Incyclists vorhandene Gänge/Übersetzungen. ClickBridges frei konfigurierbare Gangtabelle ist im Core verfügbar, aber in diesem Pfad nicht in den Incyclist-CyclingMode gepatcht. Die bestehende Incyclist-Ganganzeige ist maßgeblich. ERG und Mehrtrainerbetrieb werden zurückgewiesen.

## Noch zu verifizieren

Kompletter Incyclist-Native-Build mit React Native 0.83; Modulregistrierung/Legacy-Interop in dessen New Architecture; Einrichtung während einer echten Fahrt; eventuelle interne Änderung der `incyclist-services`-Version gegenüber dem Quellpin; linke Firmwarefreischaltung; alle zehn Hardwarekriterien. Der Patch darf unabhängig von der Standalone-App nicht als bestanden bezeichnet werden.

## Vorschlag für eine spätere öffentliche Schnittstelle

Incyclist könnte einen stabilen `ShiftInputProvider`-Vertrag anbieten: gerätebezogene Quellen, autorisierte Fahrsitzung, einzelne Gangedeltas, Fehler-/Annahmeergebnis und tatsächlich gemeldeter Trainerzustand. Zunächst eingebettet mit einer Swift-/React-Native-Grenze. Eine separat laufende App benötigte zusätzlich ein ausdrücklich implementiertes und versioniertes IPC-Protokoll mit Authentifizierung, Deduplizierung und Hintergrundtests; ein vorhandener MQTT-Client ist kein solcher Vertrag. Dieser Vorschlag erzeugt noch keine unterstützte Schnittstelle in der veröffentlichten App.
