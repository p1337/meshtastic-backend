# Installation unterwegs auf dem iPhone

## Einmalige GitHub-Einrichtung

Repository **Settings → Pages → Build and deployment → Source: GitHub Actions** auswählen. Eine GitHub-Jekyll-Vorlage muss nicht zusätzlich eingerichtet werden; der native IPA-Workflow enthält den vollständigen Build und Pages-Deploy.

Falls die Deployment-Regeln des Environments `github-pages` nur den Hauptbranch zulassen, unter **Settings → Environments → github-pages → Deployment branches and tags** den Branch `codex/native-lora-ios` erlauben.

Nach Aktivierung den fehlgeschlagenen Pages-Job im jüngsten Lauf erneut starten. Die Apple-Signierdaten bleiben ausschließlich im Environment `apple-signing`. Der Pages-Job hat keinen Zugriff auf diese Secrets.

## Unterwegs

Geplante feste Adresse nach erfolgreichem Pages-Deployment:

https://p1337.github.io/meshtastic-backend/

Die Seite in **Safari** öffnen, **Auf diesem iPhone installieren** antippen und die iOS-Rückfrage bestätigen. Eine IPA lediglich in Dateien herunterzuladen installiert sie nicht. Ein Mac, Windows-PC oder erneute Signierung ist für diesen OTA-Weg nicht vorgesehen. Das konkrete iOS-Verhalten muss einmal auf Roberts registriertem iPhone geprüft werden; ein erfolgreicher Web-Deploy allein ist kein Installationsnachweis.

Jeder erfolgreiche signierte Build erzeugt ein Manifest mit den tatsächlichen Bundle-Daten und eine versionierte IPA-Adresse aus Run-ID und Versuch. Die Buildnummer wird durch GitHubs Run-Nummer gesetzt. Ein Build-Fehler veröffentlicht keine neue App. Bei einer neuen Veröffentlichung enthält die feste Seite nur den jeweils aktuellen Build; ältere Installationslinks müssen nicht bestehen bleiben.

Die Seite bietet zusätzlich einen direkten IPA-Download. Die Anmeldung bei GitHub ist auf der öffentlichen Pages-Seite nicht erforderlich. Die signierte IPA enthält zwangsläufig das Ad-Hoc-Profil; nur dessen registrierte Geräte sind zur Installation berechtigt. Private Schlüssel, P12-Datei und Passwörter werden nicht veröffentlicht.

Die Signierung läuft weiterhin ab; weder Pages noch ein Mail-Link verlängert das Profil. Die aktuelle App ist ein Offline-Test und hat keinen nachgewiesenen nativen LoRa-Empfang.

## Validierung

Der Generator prüft die SHA256-Prüfsumme gegen das erfolgreiche Signaturprotokoll, den Bundle-Identifier und das eingebettete Profil. Manifest und IPA werden gemeinsam über HTTPS veröffentlicht. Ein lokaler Test mit der tatsächlich signierten IPA prüfte Manifest-Metadaten, Linkziele und unveränderte IPA-Bytes sowie die Ablehnung von HTTP-URLs und ungültigen Build-Pfaden.

Primärquellen:

- https://help.apple.com/xcode/mac/current/en.lproj/devde46df08a.html (OTA-Manifest auch bei Ad Hoc)
- https://support.apple.com/guide/deployment/distribute-proprietary-in-house-apps-depce7cefc4d/web (HTTPS und Installationsmanifest; beschreibt Enterprise, keine zusätzliche Enterprise-Mitgliedschaft für unsere Ad-Hoc-Signierung ableiten)
- https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages
