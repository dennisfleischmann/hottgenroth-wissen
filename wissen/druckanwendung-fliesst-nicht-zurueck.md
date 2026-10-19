---
name: druckanwendung-fliesst-nicht-zurueck
description: "Was in MeinSanierungsfahrplan entsteht, erreicht Hottgenroth nie — und beim Speichern rechnet die Anwendung jedes Bild auf rund 300 px herunter"
metadata: 
  node_type: memory
  type: reference
  originSessionId: a9df26c4-f679-4aee-bc74-1016fcac6cb2
  modified: 2026-09-27T06:59:04.876Z
---

Die `.mSFPprojekt`-Datei und `PrMedia.iSFP2.xml` sind dasselbe Format, aber
**keine** verbundenen Stände. Was in der Druckanwendung ergänzt wird, bleibt
dort.

Bei Klenke am 26.09.2026, Datei 17:35 gegen Projekt 17:11:

| | Hottgenroth | Datei |
|---|---|---|
| Fotos (Titel + fotoHeute + Ansichten) | **0** | 10 |
| Logo, Unterschrift | fehlt | vorhanden |
| Prinzipskizzen MP1/MP2 aus dem iSFP-Handbuch | vorhanden | **verloren** |
| Auflösung aller Skizzen | 591–2024 px | **~300 px** |
| Paketnamen (`massnahmenpakete/item/name`) | vorhanden | Knoten fehlt ganz |

**Beim Speichern rechnet MeinSanierungsfahrplan jedes Bild auf rund 300 px
herunter** — eine Fensterskizze ging von 2024 auf 296 px, eine Handbuchskizze
von 591 auf 300. Deshalb ist die Fassung in Hottgenroth bei den Skizzen immer
die bessere, und Skizzen gehören nicht in die Rückübernahme.

Die restlichen ~360 Pfade, die sich unterscheiden, sind reine Rundung: die
Anwendung schreibt `114.921272277832` als `114.9` zurück. Kein Inhaltsverlust,
aber ein Diff, der ohne Filter unlesbar ist.

**Why:** Ein „Erfassung zurücksetzen" im Projekt hätte die zehn Fotos gekostet,
ohne dass irgendwo eine Warnung erschienen wäre.

**How to apply:** Nach dem Druck einmal zurückholen:

```powershell
.\isfp-fertigstellen.ps1 -Projekt 'Klenke' `
    -Uebernehmen 'C:\Users\...\Klenke_isfp.mSFPprojekt' -Schreiben
```

Die Liste steht in `stammdaten.json` unter `rueckuebernahme`; geschrieben wird
nur, wo Hottgenroth leer ist. Siehe [[isfp-kostenpositionen-aus-huellfl]] und
[[isfp-drei-stufen]].
