---
name: hottgenroth-daecher
description: "Dächer von außen anlegen — ein Dach trägt zwei verschiedene Polygone; ohne den 3D-Umriss entsteht keine Fläche"
metadata:
  type: project
---

Dächer sind von außen schreibbar und in der Software bestätigt: L-Pultdach und
L-Satteldach aus vier Flächen. Werkzeug für den Regelfall:
`bauteile/tools/New-Satteldach.ps1` (Rechteck → 2 Flächen, L-Form → 4).
Datenmodell: `bauteile/docs/hottgenroth-daecher.md`, Skill: `daecher`.

**Der eine Fehler, der zählt:** ein Dach trägt **zwei** Polygone.

- `<roof><points>` ist der **Dachumriss in 3D** — die Fläche selbst. Fehlt er,
  zeichnet HottCAD die Steigung und sonst nichts. Genau so ist mein erster
  Versuch gescheitert.
- `<plane_definition><points>` ist nur das Markierungsrechteck an der Traufe,
  immer flach auf `z = 0`.

Höhenformel, an einem echten Dach nachgerechnet:
`z = Geschosshöhe + Höhe1 + tan(Neigung) · Abstand von der Traufkante`.

Weitere Stolperstellen: Neigung im XML im **Bogenmaß**, in `BmElement.Slope` in
**Grad**. `ElementType 5` statt 1. Bei einer L-Form müssen die Neigungen der
beiden Schenkel **verschieden** sein, damit die Firste gleich hoch liegen —
`atan(Firstüberhöhung / halbe Schenkelbreite)`.

`intersections`, `segments`, `side_types` und alle Flächenwerte **leer lassen**;
First, Kehle und Grat rechnet die Software selbst.

**Why:** Der Umriss war der Unterschied zwischen „funktioniert" und
„funktioniert nicht", und er sah wie ein Rechenergebnis aus. Ich hatte ihn aus
einem Zwischenstand gelesen, den die Software bei laufender Anwendung führte —
ein Messfehler, kein Denkfehler im Modell.

**How to apply:** Erst Wände ins Dachgeschoss ([[hottcad-cadxmldata-fuehrend]]),
dann das Dach. Probelauf geht auch bei offener Software, echtes Schreiben nicht
([[energie-exe-verwaiste-instanz]]). Danach messen ([[messzyklus-snapshot-diff]])
und in HottCAD ansehen ([[wirkungsprobe-statt-selbstpruefung]]).
