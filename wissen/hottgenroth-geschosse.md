---
name: hottgenroth-geschosse
description: "Ein Geschoss braucht vier Zeilen — BmFloor allein genügt nicht, die Oberfläche liest die Geschossliste aus der Zeichnung"
metadata:
  type: project
---

Ein vollständiges Geschoss besteht aus **vier** Zeilen, nicht aus einer:

| Zeile | Inhalt |
|---|---|
| `BmFloor` | die Kenngrößen |
| `BmFloorData` | Rechenergebnisse, **gleiche UUID** |
| `BmData 'CADXMLData'` | `<floor GUID=… elevation=… type=…>` |
| `BmData 'is_auto_generated'` | der Wert `1` |

**`BmFloor` allein genügt nicht.** Ich hatte zwei Geschosse angelegt, und der
Dialog „Geschosse anlegen und löschen" zeigte weiter nur das EG — HottCAD liest
die Geschossliste aus der **Zeichnung**, nicht aus der Tabelle. Dasselbe Muster
wie bei Wänden und Dächern.

Gemessen an 19 Mehrgeschossern:

- `FloorType` 1 = DG, 2 = OG, 3 = EG, 6 = Keller
- `type` im XML: 1 → `Roof`, 2 und 3 → `Standard`, 6 → `Cellar`
- `SortNum` zählt von **oben** nach unten
- `FloorCount` in `building_data` = Zahl der Geschosse **über dem EG** (OG + DG).
  Keller und EG zählen nicht mit; Werner Grotz hat fünf Geschosse und `3`.
- `ElevationOfRefHeight` ist zugleich das **z der Wandpunkte** dieses Geschosses

Werkzeug: `bauteile/tools/New-Geschoss.ps1` — idempotent, trägt fehlende Zeilen
für alle Geschosse nach und setzt `FloorCount` neu.

**Die Software gewinnt bei Namen und Höhen.** Aus `1.OG` wurde `OG1`, aus `DG1`
wurde `DG`, und die Höhenlagen wurden auf ihr eigenes Schema normiert
(Bodenstärke + lichte Höhe). Nicht dagegen anschreiben.

**Why:** Der Fehlschlag war still — die Zeilen standen richtig da, nur sah die
Oberfläche sie nicht. Ohne den Blick in ein Mehrgeschoss-Projekt wäre das nicht
zu finden gewesen.

**How to apply:** Nach dem Anlegen einmal öffnen und den Geschossdialog
ansehen; was dort nicht steht, existiert für die Software nicht. Wände über
`Copy-Geschosswaende.ps1` übernehmen — das verschiebt z um die Differenz der
Höhenlagen, statt es zu setzen. Siehe [[hottcad-cadxmldata-fuehrend]].
