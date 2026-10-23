# Zweite App und vorhandene Apple-Schlüssel

Bundle-ID: **`de.p1337.ClickBridge`**. Scheme: `ClickBridge`. Keine gemeinsame App-Identität mit Werkbeleg.

Die vorhandene Werkbeleg-Pipeline nutzt das Environment `apple-signing` und die Secret-Namen:

- `IOS_DISTRIBUTION_P12_BASE64`
- `IOS_P12_PASSWORD`
- `IOS_ADHOC_PROFILE_BASE64`

Es wurden keine geheimen Werte in das Repository kopiert oder in Diagnoseausgaben aufgenommen. Das vorhandene Werkbeleg-Skript prüft ein explizites Profil für **`de.p1337.LoRaLab`**. Dieses Profil wird nicht auf eine andere Bundle-ID umgeschrieben. Mit derselben ID würde die neue App Werkbeleg ersetzen; das ist keine zweite App.

`scripts/audit-signing.py` kann auf dem macOS-Runner ausschließlich Metadaten des Profils prüfen. Es gibt keine Schlüssel oder Geräte-UDIDs aus und erstellt keine signierte IPA. Das Ergebnis steht in `build/signing-audit.json`. Ein passendes optionales `CLICKBRIDGE_ADHOC_PROFILE_BASE64` hat Vorrang; andernfalls wird das vorhandene Profil nur auf Kompatibilität geprüft.

Der GitHub-Connector erlaubt hier Quellcode/Branches/PRs, aber keine Einrichtung von Repository-Secrets, neuen GitHub-Repositories oder Apple Developer App-IDs/Profilen. Es gibt keinen verbundenen Apple-Developer-API-Zugang. Deshalb konnte die Bedingung für ein neues Repository einschließlich aller Schlüssel nicht erfüllt werden; die vom Nutzer autorisierte Alternative ist der neue App-Ordner im vorhandenen Repository.

## Weg zu einem separat installierbaren Build

1. Eigene App-ID `de.p1337.ClickBridge` im bestehenden Apple-Team registrieren.
2. Ein neues Ad-hoc-Profil für diese ID, das vorhandene Distribution-Zertifikat und das reale iPhone ausstellen. Ein korrekt passendes Wildcard-Profil wäre ebenfalls zu prüfen.
3. Dieses Profil unter eigenem Secret-Namen bereitstellen. Das Distribution-P12 kann innerhalb desselben Teams weiterverwendet werden; sein privater Schlüssel muss nicht kopiert oder öffentlich gemacht werden.
4. Mit gültiger Profil-/Zertifikatbindung archivieren, exportieren und Signatur auf Authority, Team, Bundle-ID, Ablauf und Gerätebindung prüfen. Erst danach darf eine Installation angeboten werden.

Aktuell erzeugt CI ausdrücklich `ClickBridge-UNSIGNED.ipa`. Sie ist **ohne erneute Signierung nicht installierbar**. Es wird keine funktionierende OTA-Installation behauptet und die bestehende Werkbeleg-Installationsseite wird nicht ersetzt.

Der Workflow `.github/workflows/clickbridge-store.yml` ist für die getrennte Distribution vorbereitet. Er akzeptiert ausschließlich `CLICKBRIDGE_ADHOC_PROFILE_BASE64`, prüft die Bindung an `de.p1337.ClickBridge`, importiert das vorhandene Distribution-P12 in einen temporären Schlüsselbund, archiviert mit manueller Signierung und prüft anschließend Codesign-Authority, Team, eingebettetes Profil, Bundle-ID und arm64-Binary. Erst danach erzeugt er den OTA-Eintrag unter `/clickbridge/`.

Die gemeinsame Store-Seite behält den letzten veröffentlichten Werkbeleg-Build: Manifest und IPA werden vor dem neuen Deployment erneut geladen und gegen die veröffentlichte SHA-256-Prüfsumme geprüft. ClickBridge und Werkbeleg bleiben getrennte Apps. Wenn das ClickBridge-Profil fehlt oder nicht passt, bricht der Workflow vor Signierung und Pages-Deployment ab; die bestehende Werkbeleg-Seite bleibt online.

Tatsächliche Prüfung: [Lauf 40021688060](https://github.com/p1337/meshtastic-backend/actions/runs/40021688060), Job `signing-audit`, bestand am 23.10.2026. Zertifikat-/Passwortwerte vorhanden, Profil nicht abgelaufen und Ad-hoc-Profil vorhanden, aber **`matchingProfile=false`** für ClickBridge. Separates ClickBridge-Profil nicht vorhanden. Dies ist eine Profilkompatibilitätsprüfung, keine erneute kryptographische Prüfung des P12 und keine Signierung.

Für einen Incyclist-Fork gilt dessen eigene Bundle-ID/Signierung. ClickBridge-Profile lösen nicht automatisch die Signierung einer veränderten Incyclist-App.
