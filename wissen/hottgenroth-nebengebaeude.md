---
name: hottgenroth-nebengebaeude
description: "Nebengebaeude/Umgebung liegen im BmMedia-Blob, nicht in den Bm*-Tabellen - und sind kein Bauteil"
metadata: 
  node_type: memory
  type: reference
  originSessionId: caac87fa-4997-482f-a1b3-27506ccf770e
  modified: 2026-08-23T11:50:45.955Z
---

Ein **Nebengebäude** (Reiter *Umgebung*, Knopf *beheizt/unbeheizt*) ist **kein
Bauteil**. Es erzeugt keine Zeile in `BmElement`, keine Angrenzung, keine
Hüllfläche. Es lebt als `<attachments><attachment …>` im **`BmMedia`-Blob** —
einer eigenen `building3d`-XML neben der Bauteilzeichnung, UTF-8 ohne BOM, CRLF.

- `type="Heated"` / `"Unheated"` ist der Knopf.
- `wall_ref` und `parent_wall` tragen beide die **CAD-GUID aus der Zeichnung**
  (Attribut `GUID` am `<wall>`), nicht `BmElement.UUID`.
- Der Block sitzt nach `</contour_inner>` und **vor** `<surrounding>`.
  `<surrounding>` ist das **Gelände** — dort steht das Nebengebäude nicht drin.

**HottCAD schreibt die Umgebung erst beim `DBL:UNLOAD`**, also beim Schließen
des Projekts, nicht beim Speichern. Bei laufender Software zeigt ein
Vergleichsstand die Änderung nicht — das sah einmal so aus, als wäre nichts
angekommen.

**Die Angrenzung ersetzt es nicht.** `BmElement.AdjacentType = 1` (btaHeated)
entsteht weiterhin erst bei der Übernahme ins Rechenmodell, und
`RepositoryType 1` bleibt davon unberührt — siehe
[[bmelement-zwei-repositories]] und [[bmelement-huellflaeche-flag]]. Über alle
77 Projekte mit Rechenmodell ist für den beheizten Nachbarn **Wert 1** in
Gebrauch; `8 = btaBuilding` benutzt kein einziges.

Werkzeuge und Beispiel: Fertigkeit `nebengebaeude` im
`sanierungsfahrplan-agent`, dazu `bauteile/tools/Set-Nebengebaeude.ps1` und
`Get-Wandsilhouette.ps1`. Erprobt an Test0001, in der Oberfläche bestätigt.
