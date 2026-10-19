---
name: fenster-g-wert-kommt-aus-dem-katalog
description: "g_senkrecht-Warnung des DIN-18599-Kerns kommt vom Katalogbauteil (TcBuildingElementDimension.GValue), nicht vom CAD-Fenster; die g_tot-Warnung ist bei Wohngebaeuden Normalzustand"
metadata: 
  node_type: memory
  type: project
  originSessionId: 95abe72c-97fd-495d-897d-4daebc52ef8b
  modified: 2026-09-03T15:52:34.464Z
---

Die Kernel-Warnung `P2_Calculator_Warning_0025` tritt bei Fenstern in **zwei
Spielarten** auf, die getrennt zu bewerten sind.

**`g_senkrecht` — echter Fehler.** Der Wert wandert
`TcBuildingElementDimension.GValue` (das **Katalogbauteil**) → `P0Window.fg_perpendicular`
im IBP-Blob. **`BmElementWindow.GValue` ist NICHT die Quelle** — dort steht bei jedem
Fenster unangetastet `0.5`, waehrend im Rechenkern `0` ankommt. Selbst angelegte
Bauteile der Art „3-fach Fenster Uw 1,0" tragen oft nur den U-Wert; das g-Feld bleibt
`0`. Wirkung ist gravierend, nicht kosmetisch: `g_eff = F_s · F_w · F_V · fg`
(DIN18599P2CalculatorV3.cs:4235) wird damit **null — saemtliche solaren Gewinne der
Fenster fallen weg**, der Heizwaermebedarf faellt zu hoch aus. Der Meldungstext „Der
Standardwert wurde angesetzt" ist irrefuehrend: der Code setzt `A_4.fg = 0f`, keinen
Ersatzwert.

**`g_tot` — Normalzustand.** `BmElement.GTot` ist bei **jedem** Wohngebaeude in der
LocalDB leer (Sentinel), weil kein Sonnenschutz definiert ist (`SunShadingType`, `Fc`
ebenfalls null). Nur das Nichtwohngebaeude-Beispiel traegt Werte. Ohne Kuehlung ist
g_tot fuer die Heizbilanz belanglos — nicht als Projektfehler melden.

**Why:** Wer nur `BmElementWindow.GValue` prueft, sieht `0.5` und haelt die Warnung
faelschlich fuer unbegruendet. Und wer beide Spielarten in einen Topf wirft, meldet
einen Dauerzustand als Fehler.

**How to apply:** Auszaehlen, nicht raten —
`JOIN TcBuildingElementDimension d ON d.UId = e.CatalogDimUUID` und `d.GValue > 0.01`
je Projekt. Wirkungsprobe ueber `werkzeuge/ibp/ibp-dump.exe <blob> 1 "Windows"`; Vorsicht
bei der Zuordnung, die Felder stehen **alphabetisch**, `fg_perpendicular` also **vor**
dem `strName` desselben Fensters. `ibp-dump` unterdrueckt `0` und den Sentinel
([[din18599-anlagentechnik-ibp-blob]]) — ein fehlendes Feld heisst „null", nicht
„nicht vorhanden". Behoben wird es im Bauteilkatalog am Fensterbauteil, nicht am
einzelnen Fenster.

Verwandt: [[wirkungsprobe-statt-selbstpruefung]], [[funktionen-wiederverwendbar]]
