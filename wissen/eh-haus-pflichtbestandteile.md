---
name: eh-haus-pflichtbestandteile
description: "Zu einem BEG-Effizienzhaus gehören immer eine Lüftungsanlage und ein hydraulischer Abgleich — nicht als Option, sondern als fester Bestandteil der Planung"
metadata: 
  node_type: memory
  type: project
  originSessionId: 49e4b8c1-37be-419d-98a1-aa61b55d2177
  modified: 2026-08-13T15:41:44.564Z
---

**Eine Lüftungsanlage ist bei einem Effizienzhaus immer dabei.** Vorgabe des Nutzers,
gedeckt vom Referenzprojekt `20260626_HottCAD_82024`, dessen EH-Variante führt:

```
Photovoltaik (PV) Anlage 10 kWp
Lüftungsanlage mit WRG, zentral
Hydraulischer Abgleich - 10 Heizkörper
Wärmepumpe (WP LW) Luft 5 kW
```

Eine Wärmepumpe allein reicht für eine EH-Stufe nicht — sie senkt die Primärenergie,
aber nicht die Nutzenergie. Die Lüftungsanlage mit Wärmerückgewinnung ist der einzige
Posten, der an die **Lüftungsverluste** herankommt; keine Dämmung erreicht die.
Zum hydraulischen Abgleich siehe [[waermepumpe-vorgabesatz]].

**Why:** Am 13.08.2026 an Werner Grotz durchgespielt: BEG-EM-Hülle komplett plus
Wärmepumpe plus Wärmebrückenzuschlag 0,05 brachten Qp auf 76,09 kWh/m² — EH85
verlangt < 76,0. Verfehlt um 0,09. Der Weg über immer teurere Bauteile ist an dieser
Stelle zu Ende; was fehlt, sind Lüftung und PV.

**How to apply:** Das technische Vorgehen (welche Felder die Lüftungsanlage im Modell
und in den `.BDExit`-Tabellen setzt) wird über `schnappschuss.ps1` ermittelt —
Aufnahme vorher, Nutzer konfiguriert, Aufnahme nachher, Differenz nennt die Felder.
Ergebnis gehört hierher, sobald es vorliegt.
Siehe [[wirkungsprobe-statt-selbstpruefung]].
