---
name: leitungslage-nicht-im-austauschformat
description: Das Austauschformat der Anlagentechnik setzt alle drei Leitungen auf "unbeheizt" — die Software führt Anbinde- und Steigleitung dagegen "in Zone"
metadata:
  type: project
---

`ibp-anlage-setzen.exe` kennt an der Leitung nur `art`, `lage` und `daemmung`.
Die **Umgebung** (`AmbientTemperature.enumAmbientType`) kennt es nicht, und die
Fabrik setzt alle drei Rohre auf `1` (StandardBoundaryUnheated). Gemessen am
26.09.2026 gegen `referenz-heizung-konfiguriert.bin`, den die Software selbst
geschrieben hat: dort steht Anbindeleitung `2`, Steigstrang `2`, Verteilleitung
`1`.

`lage` ist **nicht** beheizt/unbeheizt, sondern `HdPipeRunning`
(0 Innenwand, 1 Außenwand).

**Why:** Wer nur das Austauschformat benutzt, rechnet die Verteilverluste der
Anbinde- und Steigleitungen als Verlust nach draußen ab, obwohl sie in den
beheizten Räumen liegen. Das fällt nicht auf — es meldet sich nichts.

**How to apply:** Nach `ibp-anlage-setzen` je Rohr in beheizten Räumen zwei
Schritte, in dieser Reihenfolge (der Schalter allein lässt die Verluste still
durchfallen, siehe [[ibp-sammlungen-schreiben]]):
`ibp-sammlung.exe … "CircuitHeatWater[0].Distributions[0].Pipes[i].AmbientTemperature.AmbientZone" anhaengen "<Zonenkennung>"`,
dann `ibp-feld-setzen.exe … ".AmbientTemperature.enumAmbientType" 2`.
Die Verteilleitung im unbeheizten Keller bleibt auf `1` — dort ist die Vorgabe
richtig. Ebenso richtig sind Erzeuger und Speicher: die stehen von selbst auf
`1`. Gehört zu [[sanierungsvarianten-werkzeugkette]] und
[[din18599-anlagentechnik-ibp-blob]].
