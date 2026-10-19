---
name: hsetu-geometrie-in-geodesc
description: "Die Gebäudegeometrie steht in BmElement.GeoDesc als XML, nicht in den leeren Geo*-Tabellen"
metadata: 
  node_type: memory
  type: reference
  originSessionId: da0215b4-d437-4ebb-9c3d-60a23ed95a70
  modified: 2026-08-15T07:20:39.689Z
---

Die Hüllflächengeometrie eines HSETU-Projekts liegt in der Spalte
**`BmElement.GeoDesc`** (nvarchar(max)) — je Bauteil ein XML-Baum:

```
GEO/geoData/geoDataData              Lagematrix M11..M33, Mx/My/Mz (meist Einheitsmatrix)
GEO/geoLoop/geoLoopData              eine ebene Schleife; LongDesc nennt die Konvention
GEO/geoLoop/geoPoint/geoPointData    Punkte mit Px/Py/Pz, über ParentUUID an der Schleife
```

**Die Tabellen `GeoPoint`/`GeoLine`/`GeoLoop`/`GeoFace`/`GeoShell`/`GeoData` und
`BmGeometry.Geo` sind leer — das ist kein fehlendes Modell.** Ebenso sind
`BmElementReference.XCoordinate*` durchgehend 0. Wer nur dort nachsieht,
schließt fälschlich, das Projekt habe keine Geometrie (am 14.08.2026 genau so
passiert; der daraus gebaute IFC-Export war unbrauchbar).

Jedes Bauteil trägt **mehrere Schleifensätze** nebeneinander, benannt nach der
Messkonvention: `Inner`, `DIN18599_2011`, `DIN18599`, `EN12831`. Am Projekt
Pohlstraße 133 (198 Bauteile) summieren sie zu 1004,72 / **1192,70** / 627,63 /
104,35 m². **`DIN18599_2011` trifft `SUM(GrossArea)` = 1193,32 m²** und ist damit
der Satz der Wahl; `NetArea` (1119,35) ist brutto minus Öffnungen.

Koordinaten sind Weltkoordinaten in Metern (Größenordnung 640/643 — ein lokales
Netz, nicht Gauß-Krüger). Das Gebäude misst dort 16,6 × 7,8 m, z von −2,20 bis
7,80 m.

Der 3D-Datensatz von HottCAD selbst liegt daneben in `BmMedia` mit
`BuildingMediaType = 3, MediaType = 11` als XML `<topitem application="building3d">`
— enthält aber nur Layer, Einstellungen, Gelände und die Gebäudekontur, **keine
Wände**. Für einen Export ist `GeoDesc` die Quelle.

**Drei verschiedene Summen, die man nicht verwechseln darf** (Pohlstraße 133):

| Größe | Wert | Herkunft |
|---|---|---|
| Alle Bauteilflächen netto | 1119,35 m² | `SUM(NetArea)`, Repo 1 |
| Alle Bauteilflächen brutto | 1193,32 m² | `SUM(GrossArea)` = Geometriesumme |
| **Hüllfläche A der Software** | **435,37 m²** | nur `CladdingSurface = 1`, 88 Bauteile |

Die Oberfläche „Gebäudegeometrie" zeigt **435,37**. Wer 1119 oder 1193 exportiert,
liefert das ganze Haus inklusive Innenwänden und Geschossdecken — nicht die Hülle.
Siehe [[bmelement-huellflaeche-flag]].

Weitere Kennzahlen derselben Seite stehen in `BmBuilding`
(`BuildingBasicFloorArea` 110,62 / `Area` 343,21 / `UsefulArea` 339,43 /
`Height` 7,80 / `HeatedVolumeOfBuilding` 512,78) und `BmBuildingDimensioning`
(`DIN18599V2011NetHeatedVolumeOfBuilding` 389,71). **Nicht** gespeichert sind
Hüllfläche A (= Summe der markierten Flächen) und `A_N` (= 0,32 × V_e nach GEG,
hier 164,09) — beide rechnet die Software zur Anzeige aus.

Werkzeuge: `hottgenroth-agent/tools/Export-Ifc.ps1` (schreibt IFC4 mit
`IfcFaceBasedSurfaceModel`, Schalter `-NurHuelle`) und `Test-Ifc.ps1` (rechnet
Fläche und Hüllfläche aus der geschriebenen Datei zurück). Siehe
[[bmelement-zwei-repositories]] für den Pflichtfilter `RepositoryType = 1` und
[[wirkungsprobe-statt-selbstpruefung]].
