---
name: waermepumpe-vorgabesatz
description: "Vorgabewerte für eine Wärmepumpensanierung, wenn zum Projekt keine weiteren Angaben vorliegen — hydraulischer Abgleich gehört immer dazu"
metadata: 
  node_type: memory
  type: project
  originSessionId: 49e4b8c1-37be-419d-98a1-aa61b55d2177
  modified: 2026-08-12T22:08:17.904Z
---

Liegen zu einem Projekt keine weiteren Angaben vor, wird die Wärmepumpensanierung mit
`hsetu-decompiled/werkzeuge/ibp/vorgaben/waermepumpe-sanierung.json` gebaut.

**Der hydraulische Abgleich ist immer Teil einer Wärmepumpensanierung** — Vorgabe des
Nutzers, und die Software hält sich daran: alle 24 Wärmepumpenprojekte der LocalDB
führen ihn. Er steht an **zwei** Stellen, die zusammengehören:
`P5HeatDistribution.enumHydraulicBalance = 2` und `P58CircuitPumpComponent.bHydraulicBalance = true`.

Weiter im Vorgabesatz: Auslegung **55/45 °C**, Heizkörper mit PI-Regler (Regelung 5),
Netzform **Etagenring**, **Gruppe 1**, Pumpe **delta-p variabel** und **optimiert**
(nicht überdimensioniert — das ist nur der Wert, den die Fabrik mitbringt).
Warmwasser: **ohne Zirkulation**, **zentral über Steigestrang**, **Gruppe 1**.

**Why:** Ohne diesen Satz greifen die Vorgabewerte der Fabriken, und die passen zum
Bestandskessel, nicht zur Sanierung — 70/55 statt 55/45, kein Abgleich,
überdimensionierte Pumpe. Die Warmwasser-Verteilung wurde vorher **gar nicht**
angelegt; der Reiter blieb leer.

**How to apply:** Als Ausgangspunkt kopieren und projektspezifisch ergänzen, nicht
im Werkzeug fest verdrahten. Herkunft jedes Werts steht in
`DIN18599-ANLAGENTECHNIK.md`, Abschnitt „Vorgabesatz Wärmepumpe".
Siehe [[ibp-bauart-felder]] und [[din18599-modell-fabriken]].
