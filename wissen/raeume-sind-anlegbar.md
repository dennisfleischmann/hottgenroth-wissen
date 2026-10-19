---
name: raeume-sind-anlegbar
description: "Räume lassen sich von außen anlegen — die alte Gegenbehauptung ist am 20.08.2026 widerlegt worden"
metadata:
  type: project
---

**Belegt:** *Wohnraum 21 / DG2-R1* in Pohlstraße, geschrieben am 17.08.2026 um
04:01 — nur `BmRoom`, `BmRoomData` und die Zeichnung. Die **vierzehn Verweise
auf die begrenzenden Bauteile** ergänzte HottCAD um **11:01 beim Öffnen selbst**.
Erkennungsmerkmal meiner Zeile: `GId = UUID`; HottCADs eigene Räume führen dort
einen abweichenden Wert.

In der Zeichnung eines Raums stehen die begrenzenden Bauteile **gar nicht** —
nur Polygon, `room_type`, `temperature`, `air_change`, `heating_type`, `height`.
`area` und `volume` sind ebenfalls Rechenergebnisse.

`BmRoom` hat 192 Spalten, aber nur **fünf** Verweisspalten: `ProjectUUID`,
`FloorUUID`, `RoomGroupUUID`, `ProfileGroupUUID` und die eigene. Kein
`BIMUUID`, kein `ParentUUID` — deutlich weniger verflochten als ein Bauteil.

**Why:** Die alte Notiz „Räume kann kein Skript anlegen" war eine
Schlussfolgerung, keine Messung, und sie war falsch herum gedacht: **weil**
HottCAD die Verweise rechnet, muss man sie gerade nicht liefern. Dieselbe
Umkehrung wie bei Plattenumriss und Wandfläche ([[hottcad-cadxmldata-fuehrend]]).
Sie stand an fünf Orten und wurde wochenlang zitiert.

**How to apply:** Beim Anlegen dieselbe Fünferregel wie sonst — Zeichnung
schreiben, Abgeleitetes weglassen. Danach greifen die vorhandenen Werkzeuge für
Raumstempel und Zonenzuordnung ([[raum-zone-raumstempel]]). Ein Werkzeug
`New-Raum.ps1` gibt es noch nicht. Denkfehlermuster: `skills/fehlerbilder`.
