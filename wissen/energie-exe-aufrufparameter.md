---
name: energie-exe-aufrufparameter
description: "Energie.exe nimmt genau vier Aufrufparameter, alle nur zur Projektauswahl — kein Export, kein Stillbetrieb"
metadata:
  type: reference
---

`ProcessSystemParams` in `Energie.exe` wertet aus:

    -prmproject[:<Name>]        -prmprojectguid[:<UUID>]
    -prmprojectgroup[:<Name>]   -prmprojectgroupguid[:<UUID>]

**Das ist alles.** Kein `-silent`, kein Export, kein iSFP. Die Software lässt sich
sagen, *welches* Projekt sie öffnet, nicht *was* sie dann tut. Mit Parametern gerufen
wird dagegen die **Druckapplikation** `MeinSanierungsfahrplan.exe` — nicht zu
verwechseln, die iSFP-Maske ist ein Formular *in* `Energie.exe` ([[isfp-drei-stufen]]).

**How to apply:** Nützlich, um dem Berater einen Schritt abzunehmen —
`Energie.exe -prmprojectguid:<PrProject.UUID>` öffnet direkt das richtige Projekt.
Für Kopfloses taugt es nicht; dafür bleiben die Brücke (`hottgenroth-agent/bridge/`)
und [[isfp-kernel-exporteur]].
