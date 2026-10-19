---
name: bmelement-zwei-repositories
description: BmElement hält dasselbe Haus zweimal — nur RepositoryType 1 (mtyModel) ist das gerechnete Gebäude
metadata: 
  node_type: memory
  type: reference
  originSessionId: 89fe4b14-06a0-444c-aa8a-15f248ce566f
  modified: 2026-08-14T20:48:06.606Z
---

`BmElement` in `HsetuPrjData` führt mehrere Bestände desselben Hauses nebeneinander,
unterschieden durch `RepositoryType` (`TModelRepositoryType`): 0 none, **1 mtyModel**,
2 mtyRepository, **3 mtyModelRepository**, 4 mtyVariant, 5 mtyVariantRepository.

- **RepositoryType 1** ist das gerechnete thermische Modell — daraus baut die Software
  ihre Bauteilliste. Jedes Element hat eine `AdjacentType` ≠ 0.
- **RepositoryType 3** ist der Vorrat, aus dem modelliert wurde (bei IFC-/CAD-Import die
  eingelesene Architektur). Dort ist `AdjacentType` **immer** 0.
- Über alle 101 Projekte der lokalen `(localdb)\HSETU` gemessen (14.08.2026):
  13.577 Elemente in Repo 1 (alle mit Angrenzung), 25.614 in Repo 3 (keines mit Angrenzung).

Wer ohne diesen Filter über `BmElement` summiert, zählt jede Fläche zweimal — beim Projekt
„Pohlstraße 133" 1806 m² statt 1119 m². Prüfgröße: die Summe je (ElementType, AdjacentType)
in Repo 1 trifft die Flächen der Bauteilliste auf zwei Nachkommastellen.

`ElementType` ist dieselbe Aufzählung wie `TcBasis.GroupType` (`TTechDataBuildingElementType`:
1 Wand, 2 Tür, 3 Fenster, 4 Decke/Boden, 5 Dach, 8 Gaube, 11 Bodenplatte, 13 Öffnung,
15 Rollladenkasten). `AdjacentType` (`TTechDataBuildingAdjacentType`) ist **nicht** dieselbe
wie `UsageType` am Katalogbauteil — die Umrechnung steht in `HottgenrothBauteilSync::ANGRENZUNG`.

Ergänzt [[hottgenroth-bauteil-sql]], wo `BmElement*` als „noch nicht analysiert" steht.
Enums nachzulesen im [[hsetu-dekompilierter-korpus]] unter `api/Hsetu.Model.Xim.api.txt`
und `api/Hsetu.Model.Core.api.txt`.
