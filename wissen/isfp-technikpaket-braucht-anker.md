---
name: isfp-technikpaket-braucht-anker
description: "Ein Maßnahmenpaket ohne Änderung an SANBEZ oder Beschr_Heiz/Wass/Luft bleibt im iSFP leer — PV allein trägt nie ein eigenes Paket"
metadata:
  type: feedback
---

**Kein Maßnahmenpaket ohne Anker.** Ein Paket erscheint im iSFP nur, wenn sich darin
mindestens ein Beschreibungstext gegenüber dem Vorgänger ändert
([[isfp-komponenten-kommen-aus-dem-container]]): ein neuer `SANBEZ` an einem Bauteil,
oder ein neues `Beschr_Heiz` / `Beschr_Wass` / `Beschr_Luft`.

**Photovoltaik hat kein eigenes Feld** und kann damit nie allein ein Paket tragen. Bei
`EG2KU_Hesse_260815` steht sie im selben Paket wie die Wärmepumpe und erscheint als
dritte Ausführung von `SK_HEIZUNG`. Genau so planen — PV zur Wärmepumpe, nicht als
eigener Schritt.

**Dasselbe gilt für Lüftung, hydraulischen Abgleich und Rohrleitungsdämmung**, solange
sie nicht im DIN-18599-Modell stehen. Eine Lüftung, die die Kette nicht setzen kann,
lässt `Beschr_Luft` auf „Keine Lüftung vorhanden" — sie ist im iSFP unsichtbar, egal
welche Kosten danebenstehen.

**Why:** Bei Klenke waren MP2 (PV allein) und MP4 (Wärmepumpe allein) beide leer. Zwei
von fünf Paketen. Der Kunde hätte in MP2 25.900 € ausgegeben, ohne dass im Fahrplan
etwas dazu steht — und ohne dass sich die Energiekostenzeile bewegt, weil PV die
Endenergie Heizung nicht berührt. Das zweite Argument gilt unabhängig von jeder Maske.

**How to apply:** Beim Zuschneiden der Pakete durchgehen, was sich in jedem Paket am
Modell oder an den Bauteilen **ändert**. Ändert sich nichts, gehört die Maßnahme in ein
Nachbarpaket. Technik, die von außen nicht setzbar ist, muss in der Software erfasst
werden, bevor das Paket steht.

Siehe auch [[isfp-drei-stufen]] · [[isfp-planung]].
