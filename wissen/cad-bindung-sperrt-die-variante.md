---
name: cad-bindung-sperrt-die-variante
description: "„Diese Ansicht ist rein informativ\" in einer Sanierungsvariante kommt von TableZusatz.ProjektPfad3D = Art=CAD — ein Feld, kein fehlendes Sanierungs-Flag"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 634a2411-a32e-41c2-8ecf-cb250ec3dc7c
  modified: 2026-10-04T13:08:00.537Z
---

Steht im Energieberater in einer Sanierungsvariante **„Diese Ansicht ist rein
informativ und dient zur Übersicht"** und lassen sich Flächen, Maße oder
Bauteilzuordnung nicht ändern, dann hängt die Variante am HottCAD-Modell.

**Es ist genau ein Feld: `TableZusatz.ProjektPfad3D` im Container.** Steht dort
`Art=CAD`, ist die Variante gebunden und die Bauteilübersicht gesperrt; ist es
leer, ist sie frei bearbeitbar. Der gelbe Kasten ist in Energie.exe das Panel
`PanelCADHinweis` mit dem Label `Label_CadErfassung_Info`.

**Es fehlt kein „das ist eine Sanierung"-Flag** — das war die naheliegende und
falsche Vermutung. Gemessen an einem Projekt mit drei Varianten: Ist-Zustand und
die aus dem Modell erzeugte trugen `Art=CAD`, eine von Hand angelegte nicht, und
nur die ließ sich bearbeiten. Alles andere war gleich: `ProjektGesperrt` in allen
drei **leer**, `PROJEKT_ART`/`ProjAnl_Art`/`ProjAnl_Erfass` identisch,
`VarianteID` bei beiden Varianten gesetzt, `Sperre=1` im `Herkunft`-Block **aller**
Hüllflächen aller Varianten. Von 116 Feldern in `TableProjekt` unterschieden sich
zwei — laufende Nummer und `MBDETAILDATEN` —, und keines davon war ein Schalter.

**Lösen gibt etwas auf.** Eine gelöste Variante folgt dem Modell nicht mehr:
spätere Änderungen an der Zeichnung wandern nicht mehr hinein. Das ist eine
Abwägung, keine Reparatur — vorher fragen und den Preis nennen.

**Werkzeug:** `set_hottgenroth_cad_bindung` (MCP, seit 04.10.2026 in Produktion)
bzw. `hottgenroth-agent/tools/Set-CadBindung.ps1` lokal. Adressiert über den
**Namen** der Variante, nie über die Nummer — siehe
[[varianten-nummer-ist-fluechtig]]. `richtung: setzen` macht es rückgängig und
holt sich den Wert von einer noch gebundenen Variante, statt ihn zu erfinden.
Regeln HA-14 und HA-15 in `docs/regeln/hottgenroth-arbeitsplatz.md`.

**Why:** Am 04.10.2026 im Projekt V4DZX gefunden, nachdem die Vermutung „da fehlt
ein Sanierungs-Flag" sich am Feldvergleich nicht halten ließ. Den Satz selbst
findet man nur in Energie.exe (Delphi-DFM), nicht im .NET-Korpus.

**How to apply:** Bei der Meldung nicht nach einem fehlenden Flag suchen, sondern
nach `ProjektPfad3D`. Verwandt: [[schichtloses-bauteil-verliert-u-wert]],
[[container-ergebnisse-gehoeren-der-software]].
