---
name: bmelement-huellflaeche-flag
description: "Die thermische Hülle steht als Flag CladdingSurface in BmElementEnergyConsulting, nicht in BmElement"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 89fe4b14-06a0-444c-aa8a-15f248ce566f
  modified: 2026-08-14T21:47:43.776Z
---

Ob eine Fläche zur **thermischen Hülle** gehört, steht nicht am Element selbst, sondern in
`BmElementEnergyConsulting.CladdingSurface` (bit). Die Tabelle hängt über **dieselbe UUID**
am `BmElement` (`ec.UUID = e.UUID`), eine Zeile je Element.

Das Flag ist **nicht** aus Typ und Angrenzung herzuleiten: am Projekt „Pohlstraße 133"
liegen 34 der 54 Außenwandflächen in der Hülle und 20 nicht (unbeheizter Anbau) — gleicher
Typ, gleiche Angrenzung, gleicher Aufbau.

**Damit erklärt sich die Bauteilliste/Bauteilerfassung der Software**: sie zeigt genau die
markierten Flächen, keinen Baumausschnitt. Gegenprobe am selben Projekt: 88 von 198 Flächen,
**435,37 m²** von 1119,35 m² — exakt die Summe ihrer 37 Listenzeilen und ihrer 12 Kacheln.

Weitere brauchbare Spalten derselben Tabelle: `FxElementType` (Fx-Kategorie), `FxArea`,
`FxPerimeter`, `Area5M`/`UValue5M` (Erdreich), `Extension` (Anbau),
`IsReferenceBuildingComponent` (Referenzgebäude). Im untersuchten Bestand sind sie 0.

## Wie viel es ausmacht: gemessen an zehn Projekten

 Wer ungefiltert summiert, rechnet zu viel — und zwar **unberechenbar** viel:

| Projekt | Flaechen | davon Huelle | alle m² | Huelle m² | Faktor |
|---|---:|---:|---:|---:|---:|
| B5CF9F01 | 4.054 | 1.560 | 38.639 | 14.254 | 2,71 |
| 85AA3B39 | 1.231 | 1.060 | 12.363 | 10.829 | 1,14 |
| 31B79F01 | 829 | 298 | 8.384 | 3.133 | 2,68 |
| 1E8BA001 | 322 | 107 | 3.828 | 874 | **4,38** |

Die Spanne reicht von **1,14 bis 4,38**. Ein pauschaler Korrekturfaktor ist
deshalb ausgeschlossen — es muss gefiltert werden. Fuer Kosten heisst das:
ohne diesen Filter kommen Betraege heraus, die plausibel aussehen, im
Kundengespraech verwendbar sind und um mehr als das Doppelte danebenliegen.
Gemessen am 13.09.2026.

Zusammen mit [[bmelement-zwei-repositories]] die zweite Bedingung für eine richtige
Flächenauswertung: erst `RepositoryType = 1`, dann `CladdingSurface = 1`.
