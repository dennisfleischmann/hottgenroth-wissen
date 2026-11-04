---
name: hilgert-abgleich-befund
description: "Hilgert (260072, Metzingen): der „35 °C End Zustand"-Abgleichbericht wurde aus dem unsanierten Projekt gedruckt, nicht aus der sanierten Variante; dazu Innenwände/-türen und eine Decke als Außenbauteile angesetzt (≈3,3 kW zu viel)"
metadata:
  type: project
---

**Gemessen am 04.11.2026** in `HsetuPrjData`. Drei Projekte in der LocalDB:

| Projekt | UUID | Hülle | Stand |
|---|---|---|---|
| Jonathan Hilgert_Heizlastberechnung | `2268A101-2109-AF7F-95E5-DE25787FDC77` | Bestand (AW 1,14, F 1,6) | 23.10.2026, ohne Anlage |
| … Heizlastberechnung (1) | `63A5A101-16F2-377E-9D40-D15541CB1289` | Bestand | 04.11.2026, Anlage 35/30, 2 275 l/h, 1 730 mbar = **der 35-°C-Bericht** |
| … hydraulischer Abgleich 35 °C (Variante) | `63A5A101-34F2-B373-9606-4BDF9D105235` | **saniert** (AW 0,20, Dach 0,14, F 0,95) | 35 °C, 1 464 l/h, 658 mbar |

Die Raumheizlasten im Bericht „35C End Zustand" (Küche 1 840 W, Wohnraum 4 732 W) sind die
des Bestands → Bericht aus dem falschen Projekt oder falsch beschriftet. Beide Berichte
(35 °C und 45 °C, 01.11.2026) liegen unter `C:\Users\fs-energieberater\Downloads\`.

**Heizlastfehler in allen drei Projekten:** 11 Innenwände `IW …` (U 2,0) und 3 Innentüren
`IT …` mit `AdjacentType 3 = Außenluft` (2 388 W), dazu Decke `Boden OG1 002-29` (U 2,97,
8,15 m²) als Dach gegen Außenluft im Wohnraum EG (865 W) — über dem Wohnraum liegen die
13-°C-Dachräume des OG1. Küche 222 W/m², Gebäude 98 W/m²; eine FBH kann bei 35/30 ≈ 50 W/m².
Deshalb: ΔT = 5 K überall, „kein passender Ventiltyp", „>100 W/m²", „zu klein dimensioniert".

**Noch offen (Entscheidung Dennis):** Angrenzungen korrigieren (in Original *und* Variante),
End-Zustand nur aus der Variante drucken, `RatedFlowTemperature` leer lassen, Pumpe
eintragen. Kreislängen (Küche 60 m bei 6 m²) gegen den Verlegeplan halten.

Verwandt: [[optimus-abgleich-rechenweg]], [[optimus-foerderhoehe-ist-heuristik]].
