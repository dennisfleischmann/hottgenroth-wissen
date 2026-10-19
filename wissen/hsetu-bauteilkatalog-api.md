---
name: hsetu-bauteilkatalog-api
description: Für Bauteile gibt es eine echte API in Hsetu.ConstructionCatalog.BL — die offene Frage aus bauteile-uebernehmen.md ist damit beantwortet
metadata: 
  node_type: memory
  type: project
  originSessionId: 49e4b8c1-37be-419d-98a1-aa61b55d2177
  modified: 2026-08-09T03:43:36.357Z
---

Die Software hat eine programmierbare Schnittstelle für den Bauteilkatalog. Sie liegt in
**`Hsetu.ConstructionCatalog.BL`** (Modul `Hsetu.ConstructionCatalog.BL.dll`):

- `ConstructionCatalogLogic` (statisch) — `InsertNewConstruction`, `AppendNewConstruction`,
  `CopyConstruction` / `PasteConstruction`, `DeleteConstruction`, `CreateNewConstructionElement(…)`,
  `ListOfProjectConstructions`
- `LayerConstructionLogic` — Schichten: `AppendLayerStructureSingleLayer`, `InsertLayer`,
  `ReplaceLayer`, `DeleteLayer`
- `MaterialCatalogLogic`, `FrameGlazingCatalogLogic` (Rahmen/Verglasung), `ThermalBridgeLogic`
- `LoadConstructionsFromSQL` / `LoadMaterialsFromSQL` / `LoadThermalBridgesFromSQL` — Lesen
  ohne Oberfläche, über `TFWConstructionCatalogListType` und Katalog-GUID

**Why:** `hottgenroth-agent/docs/bauteile-uebernehmen.md` hielt fest, dass vor dem Bau von
`bauteile.copy` erst zu prüfen sei, ob es überhaupt eine solche API gibt — der zeilenweise
Kopieransatz hatte sich beim Projektimport als falsch erwiesen, weil die Software ihr
Objektmodell serialisiert statt Zeilen zu schreiben. Die Prüfung ist erledigt: es gibt sie.

**How to apply:** Bauteilübernahme über `hsetu.bridge` aufrufen statt per SQL nachzubauen —
so wie es der Projektimport in `app/Services/HottgenrothBrueckenImport.php` bereits tut.
Vorbehalt: `ConstructionCatalogLogic` ist statisch und hält Zustand (Auswahl, Zwischenablage)
und stammt aus der Oberflächenschicht; für Automatisierung ist der Weg über
`LoadConstructionsFromSQL` und die `TBO…`-Objekte vermutlich belastbarer. Nichts davon ist
bisher ausgeführt worden — gelesen, nicht erprobt.

Signaturen: `C:\Projekte_Dev\hsetu-decompiled\api\Hsetu.ConstructionCatalog.BL.api.txt`.
Verwandt: [[hsetu-dekompilierter-korpus]], [[hottgenroth-bauteil-sql]]
