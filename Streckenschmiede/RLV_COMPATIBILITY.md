# RLV-Kompatibilität – Real-Life-Video für Indoor-Fahrten

Stand: 4. November 2026. „RLV“ bezeichnet eine Produktklasse, aber **keinen einzelnen offenen Standard**. Streckenschmiede trennt deshalb einen portablen Basiskorridor von herstellerspezifischen Binärformaten.

## Portabler Basiskorridor

Die erste herstellerübergreifende Stufe ist ein Video mit einer zeitlich passenden GPX-Spur:

- Video: bevorzugt MP4 mit H.264 oder H.265; AVI bleibt ein Import-Fallback.
- Steuerdatei: gleichnamige GPX-Datei, zum Beispiel `Remstal.mp4` und `Remstal.gpx`.
- GPX enthält mindestens einen Track mit geordneten `trkpt`-Punkten, Latitude/Longitude und Zeitstempel. Höhe ist für Steigung und Trainerregelung praktisch erforderlich.
- Video- und GPX-Start müssen zeitlich zugeordnet sein. Streckenschmiede verwendet zusätzlich seine QR-/Timecode-Anker und darf einen Offset beziehungsweise eine Driftkorrektur speichern.
- Fehlende Höhe, unplausible Zeitfolgen, GPS-Lücken und Sprünge werden sichtbar gemeldet; sie dürfen nicht stillschweigend zu Trainerkommandos werden.

BigRingVR dokumentiert genau diesen kleinsten gemeinsamen Importumfang: Video und GPX/RLV/PGMF mit gleichem Basisnamen, H.264/H.265 in MP4/AVI, Zeitstempel in jedem GPX-Trackpunkt und synchroner Start. Damit kann Streckenschmiede kompatible, eigene Video-/GPX-Paare erzeugen, ohne ein proprietäres Tacx-Format zu erfinden.

## Tacx-RLV/PGMF

Tacx-Real-Life-Video besteht typischerweise aus mindestens drei zusammengehörigen Dateien:

| Datei | Zweck | Bekannte Kerndaten |
|---|---|---|
| Video (`.avi`/`.mp4`) | Bild und optional Ton | Frames und Bildrate |
| `.rlv` | Video-/Strecken-Synchronisierung | Videodateiname, Bildrate, Frame-Offset, Frame-zu-Distanz-Zuordnung, Segmente und optionale Infoboxen |
| `.pgmf` | Trainer-/Höhenprogramm | Kursname, Starthöhe, Distanz- oder Zeitprogramm, Steigung/Watt/Puls, Abschnittslänge und Rollwiderstand |

Die öffentlich einsehbare, MIT-lizenzierte Incyclist-Implementierung bestätigt:

- RLV-Dateikennung `2000`, PGMF-Dateikennung `1000`.
- RLV-Blöcke `2010` Video-Info, `2020` Frame/Distanz, `2030` Infobox und `2040` Kursinfo.
- PGMF-Blöcke `1010` Allgemeine Info und `1020` Programm.
- Ein Frame-/Distanz-Datensatz besteht aus Framenummer und Distanz pro Frame.
- Ein PGMF-Programmdatensatz enthält Abschnittsdauer/-distanz, Lastwert und Rollwiderstand; der Lastwert wird je nach Programm als Watt, Steigung oder Puls interpretiert.
- Für eine RLV-Strecke erwartet Incyclist beide gleichnamigen Begleitdateien `.rlv` und `.pgmf`; ein Steigungs- und Distanzprogramm ist erforderlich.

`CAF` und `IMF` gehören zur verwandten Tacx-Dateifamilie, sind aber nicht gleichbedeutend mit dem RLV-/PGMF-Paar und werden getrennt geplant.

## Kompatibilitätsstufen der Streckenschmiede

1. **RLV Portable:** MP4/H.264 oder H.265 plus GPX 1.0/1.1 mit Zeit und Höhe importieren, synchronisieren und lokal abspielen.
2. **RLV Portable Export:** Eigene Action-5-Pro-Clips mit gleichnamiger GPX-Datei und dokumentiertem Offset ausgeben. Originalvideo bleibt unverändert.
3. **Tacx Read:** `.rlv` und `.pgmf` defensiv lesen; unbekannte Blöcke und Versionen ablehnen oder unverändert referenzieren.
4. **Trainerkopplung:** Steigungsprofil nur über `TrainerCore` und innerhalb der vom FTMS-Trainer gemeldeten Grenzen anwenden.
5. **Tacx Export:** Erst nach Referenzdateien und Gegenprüfung in mindestens Incyclist und GoldenCheetah. Kein Versprechen, solange Roundtrip-Tests fehlen.

## Rechte und Sicherheit

- Parsercode kann nur unter Beachtung seiner Lizenz übernommen werden. Bei Incyclist ist dies MIT einschließlich Copyright-Hinweis.
- Das Dateiformat macht ein Video nicht frei nutzbar. Gekaufte oder fremde RLV-Videos dürfen nicht automatisch kopiert, hochgeladen oder verteilt werden.
- Streckenschmiede importiert lokale Dateien und erzeugt standardmäßig nur Verknüpfungen/Metadaten; eine Kopie oder Veröffentlichung erfordert eine ausdrückliche Aktion.
- Steigungsdaten aus unbekannten Dateien steuern den Trainer nie ungeprüft. Wertebereiche, Sprünge, Dateigröße und Parsergrenzen werden validiert.

## Primär- und Referenzquellen

- Incyclist Tacx-Parser (MIT): <https://github.com/incyclist/services/blob/2b44911692f93c2204628adbb39541b08d5f0f58/src/routes/base/parsers/tacx/TacxParser.ts>
- Incyclist RLV-Reader: <https://github.com/incyclist/services/blob/2b44911692f93c2204628adbb39541b08d5f0f58/src/routes/base/parsers/tacx/rlv.ts>
- Incyclist PGMF-Reader: <https://github.com/incyclist/services/blob/2b44911692f93c2204628adbb39541b08d5f0f58/src/routes/base/parsers/tacx/pgmf.ts>
- Incyclist Formatkonstanten: <https://github.com/incyclist/services/blob/2b44911692f93c2204628adbb39541b08d5f0f58/src/routes/base/model/tacx.ts>
- BigRingVR FAQ zu lokalen RLV-Dateien: <https://www.bigringvr.com/faq/faq>
- GoldenCheetah Diskussion zu RLV/PGMF/Video: <https://github.com/GoldenCheetah/GoldenCheetah/issues/2526>
- GPX 1.1 Schema: <https://www.topografix.com/GPX/1/1/>

