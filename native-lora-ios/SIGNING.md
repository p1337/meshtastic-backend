# Regulär mit Apple Distribution signierte IPA aus GitHub

## Status

Der Workflow ist für offizielle Apple-Signierung vorbereitet. Eine erfolgreich signierte IPA gibt es erst nach Bereitstellung gültiger Signierdaten und bestandenem Cloudlauf. Die bislang ausgegebene `LoRaLab-unsigned.ipa` bleibt unsigniert. Die App bietet weiterhin Offline-Tests, keinen Live-LoRa-Empfang.

Apple-Account: der von Robert genannte Entwickleraccount. Private Zugangsdaten gehören ausschließlich zu Apple beziehungsweise in die geschützten GitHub-Secrets, niemals in Issues, Git-Dateien oder Chat.

## Einmalige Apple-Einrichtung

1. In Apple Developer muss die bezahlte Mitgliedschaft **Aktiv** sein; die Bestellbestätigung allein genügt nicht.
2. Das aktuelle iPhone über seine **UDID** als Testgerät registrieren. UDID ist nicht Seriennummer oder IMEI. Sie lässt sich beispielsweise in Apples Windows-Geräteverwaltung/iTunes beziehungsweise in einem vorhandenen Pairing-Werkzeug ablesen. Keine Geräte aus iCloud oder der 2FA-Vertrauensliste entfernen.
3. Eine explizite App ID mit Bundle-ID **`de.p1337.LoRaLab`** registrieren. Keine zusätzlichen Capabilities aktivieren.
4. Ein gültiges **Apple Distribution**-Zertifikat mit dem zugehörigen privaten Schlüssel als **passwortgeschützte P12-Datei** bereitstellen. Eine `.cer` allein enthält keinen privaten Schlüssel. Ein bestehendes noch gültiges passendes Zertifikat darf wiederverwendet werden. Andere Zertifikate nicht unaufgefordert widerrufen.
5. Unter Profiles ein **Ad Hoc**-Profil erstellen: App ID `de.p1337.LoRaLab`, genau dieses Distribution-Zertifikat und das aktuelle iPhone auswählen. Als `.mobileprovision` herunterladen.

Ohne Mac kann ein CSR mit dem lokalen Python-Helfer erstellt werden; Anleitung unten. GitHub braucht nicht das Passwort des Apple-Accounts und keinen 2FA-Code.

## Geschützte GitHub-Einrichtung

Repository `p1337/meshtastic-backend` → Settings → Environments → Environment **`apple-signing`**.

Deployment branches auf `codex/native-lora-ios` einschränken. Wenn verfügbar, einen Required Reviewer für Signierläufe setzen. Anschließend diese drei **Environment Secrets** setzen:

| Secret | Inhalt |
| --- | --- |
| `IOS_DISTRIBUTION_P12_BASE64` | Base64 der P12 inklusive privatem Schlüssel |
| `IOS_P12_PASSWORD` | Passwort der P12 |
| `IOS_ADHOC_PROFILE_BASE64` | Base64 des Ad-Hoc-Profils |

Das Profil wird ausschließlich aus dem Environment Secret `IOS_ADHOC_PROFILE_BASE64` geladen. Ein Fallback auf unmaskierte Variablen entfällt, damit das Profil nicht in den Runner-Logs ausgegeben wird.

PowerShell auf Windows (Pfad jeweils auf die eigene Datei setzen):

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path .\signing-local\distribution.p12))) | Set-Clipboard
```

In das erste Secret einfügen, anschließend für das Profil:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path .\signing-local\LoRaLab.mobileprovision))) | Set-Clipboard
```

In das dritte Secret einfügen. Das Passwort direkt in das zweite Secret eingeben. Base64 ist keine Verschlüsselung; diese Werte nicht teilen oder als Repository Variables speichern. Privater Schlüssel und P12 besitzen Signierrechte und müssen geschützt bleiben.

## Build starten und Ergebnis

Ein Push auf den bestehenden Branch startet den Workflow. Für den bereits gelaufenen Workflow nach dem Eintragen der Secrets **Re-run all jobs** wählen. `workflow_dispatch` ist zusätzlich vorbereitet; der manuelle Run-Button erscheint bei GitHub nur, wenn GitHub den Workflow auf dem Defaultbranch kennt. Dafür wurde der Hauptbranch nicht verändert.

Der Workflow erstellt eine temporäre Keychain, importiert die Signieridentität, prüft das Profil auf App ID, Ablaufzeit und registrierte Geräte, testet CSS/Parser, archiviert mit Xcode und exportiert per **release-testing** (Ad Hoc). Danach werden Apple-Distribution-Authority, Team ID, eingebettetes Profil, arm64/iOS-Plattform und Code-Signatur geprüft. Nur bei Erfolg entsteht das Artifact **LoRaLab-Apple-signed-IPA**. Es gibt keinen automatischen Rückfall auf eine unsignierte IPA.

Es werden nur die signierte IPA, Prüfsummen, ein öffentlich teilbares Prüfprotokoll ohne Geräte-UDIDs und Softwaretestergebnisse hochgeladen. Schlüssel, P12, rohe Profile, Archive und detaillierte Signierlogs bleiben außerhalb der Artifacts und werden bereinigt. Ein eingebettetes Ad-Hoc-Profil gehört technisch zur installierbaren IPA und enthält die zugelassenen Geräte; die IPA ist deshalb für Roberts Gerät bestimmt und nicht zur unkontrollierten öffentlichen Verteilung vorgesehen. Actions-Artifact-Download erfordert GitHub-Anmeldung mit passendem Zugriff; vollständige Geheimhaltung durch ein öffentliches Repository wird nicht zugesichert. Bei gewünschter vertraulicher Verteilung vorher ein privates Repository verwenden.

Die resultierende IPA wird **nicht erneut durch AltStore oder SideStore signiert**. Installation mit einem geeigneten iOS-Geräteinstaller, der die bestehende Signatur beibehält, zum Beispiel Apple Configurator unter macOS; der konkrete Windows-Installationsweg wird gesondert geprüft. Die Laufzeit richtet sich nach den tatsächlichen Zertifikats-/Profilablaufdaten, nicht pauschal nach der Siebentagefrist eines kostenlosen Accounts. Kein App-Store-Review wird durch Ad Hoc behauptet; TestFlight wäre ein separater Distributionsweg.

## CSR und P12 unter Windows/Linux ohne Mac vorbereiten

Python 3 und die Paketabhängigkeit `cryptography` erforderlich. Im Ordner `native-lora-ios`:

```powershell
py -m pip install cryptography
py scripts/signing-material.py csr
```

Ein lokales Passwort für den privaten Schlüssel festlegen. Der öffentliche CSR `signing-local/distribution.certSigningRequest` wird bei Apple unter Certificates → Apple Distribution hochgeladen. Apple stellt danach das echte Zertifikat aus; dessen heruntergeladene Datei als `signing-local/distribution.cer` ablegen.

```powershell
py scripts/signing-material.py p12
```

Der Helfer fragt das lokale Schlüsselpasswort und ein P12-Passwort verdeckt ab, prüft den passenden öffentlichen Schlüssel und erzeugt `signing-local/distribution.p12`. Er überträgt nichts ins Netzwerk. Unter Linux `python3` statt `py` verwenden.

## Primärquellen

- GitHub: https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications
- Apple Ad Hoc: https://developer.apple.com/help/account/provisioning-profiles/create-an-ad-hoc-provisioning-profile
- Apple Geräte: https://developer.apple.com/help/account/devices/register-a-single-device

## PKCS12-Kompatibilität

Falls Apples Security-Import das moderne PKCS12-Format ablehnt, prüft OpenSSL 3 die Datei mit dem angegebenen Passwort und exportiert dieselbe Identität erneut mit kompatiblem SHA1-MAC und Triple-DES-PBE. Das Zwischen-PEM bleibt verschlüsselt, alle temporären Dateien werden entfernt. Ein falsches Passwort wird nicht umgangen. Zertifikatsbindung, Team- und Signaturprüfungen bleiben aktiv.
