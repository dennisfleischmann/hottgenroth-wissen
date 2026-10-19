---
name: neues-projekt-zone-raeume
description: Regelfall für ein neues Wohngebäude — Zone anlegen und Räume beheizt/unbeheizt einstellen; was ich vorher wissen muss
metadata:
  type: feedback
---

Wenn der Nutzer für ein Projekt „Zone anlegen und Räume einstellen" verlangt:
Kurzfassung in `bauteile/docs/neues-projekt-zone-und-raeume.md`, ein Aufruf
erledigt beides.

```powershell
cd C:\Projekte_Dev\energieberatung\bauteile\tools
.\Setup-Wohngebaeude.ps1 -Projekt "<Name>" -Beheizt EG,DG1,DG2 -Unbeheizt Keller -Probelauf
.\Setup-Wohngebaeude.ps1 -Projekt "<Name>" -Beheizt EG,DG1,DG2 -Unbeheizt Keller
```

**Vier Angaben brauche ich vorher** — fehlt eine, nachfragen statt raten:
Projekt (Ausschnitt oder GUID) · beheizte Geschosse · unbeheizte Geschosse ·
Ausnahmen je Raum. Jedes Geschoss mit Räumen muss zugeteilt sein.

Raumgenaue Ausnahmen über `-Geschoss * -Raum EG-R9` bei `Set-Raumstempel.ps1`
und `Set-Raum-Zone.ps1`.

Drei Dinge, die beim Bauen Fehler verursacht haben und jetzt abgesichert sind:

- **Die Zone heißt hinterher nicht mehr wie beim Anlegen.** Die Software benennt
  sie beim Zuweisen des Nutzungsprofils nach dem Profil um („Wohnen" →
  „Wohnung Einfamilienhaus"). Zuordnungen deshalb immer über die **Zonen-UUID**,
  nie über den Namen.
- **Nach einer raumgenauen Ausnahme meldet `Test-Wohngebaeude.ps1` diesen Raum
  als Fehler**, weil die Prüfung je Geschoss argumentiert. Erwartet — gehört in
  die Projektnotiz, sonst hält man es später für einen echten Fehler.
- **Ein Projekt kann mehrere eberater-Container in `PrMedia` führen**; maßgeblich
  ist der jüngste `StampEdit`.

**Why:** Der Ablauf besteht aus vier Einzelschritten in fester Reihenfolge, und
jeder Fehler darin ist still — ein vergessenes Geschoss, ein Raum in keiner Zone,
ein Heizstatus nur an einer der beiden Stellen. Der eine Aufruf prüft
Vorbedingungen vorher und 21 Invarianten hinterher; von Hand zusammengesetzt
fehlt genau das.

**How to apply:** Immer erst `-Probelauf`. Räume sind von außen anlegbar — die frühere Notiz, das ginge nicht, ist am 20.08.2026 widerlegt worden. Am Ende Wirkungsprobe in der Oberfläche
([[wirkungsprobe-statt-selbstpruefung]]): steht die Zonenfläche noch auf dem
Sentinel, hat die Software die Zuordnungen nicht verrechnet.

Gehört zu [[wohngebaeude-einzonenmodell]] und [[raum-zone-raumstempel]].
