---
name: mp5-waermebrueckenzuschlag-005
description: "Wärmebrückenzuschlag steht an ZWEI Stellen: TableHausDat.BERUECKSWB ist nur die Anzeige, gerechnet wird Zones[0].enumModeThermalBridge im IBP-Blob (3 = 0,05)"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 1f0988c2-fbda-498e-bc4f-0bd047948fdc
  modified: 2026-09-26T11:40:12.689Z
---

**Der Wärmebrückenzuschlag steht an zwei Stellen, und die Tabelle ist die
falsche.**

| | |
|---|---|
| `TableHausDat.BERUECKSWB` (+ `WBPAUSCHAL = 1`) | was der Dialog **anzeigt** |
| `Zones[0].enumModeThermalBridge` im `Kernel18599V5` | was **gerechnet** wird |

`P2Enums.ConsiderationOfThermalBridges` (aus `DIN18599DataModel.cs`):

```
0 HeatBridgesIncluded          4 Delta_U_wb_Calculated
1 Delta_U_wb_010               5 LinearThermalHeatCoefficients
2 Delta_U_wb_015               6 Use_Default
3 Delta_U_wb_005               7 Delta_U_wb_003
```

Die einzelnen Bauteile tragen `enumModeThermalBridge = 6` (`Use_Default`) und
erben von der Zone — **nur die Zone ändern**:

```powershell
ibp-feld-setzen.exe blob.bin neu.bin "Zones[0].enumModeThermalBridge" 3
```

**Why:** Am 26.09.2026 bei Klenke MP5 `BERUECKSWB` auf 0,05 gesetzt,
zurückgeschrieben, die Variante in der Software geöffnet und neu rechnen
lassen — `HTSTRICH` blieb bei 0,3115, also weiter `Σ(A·U·Fx)/ΣA + 0,1000`. Die
Software zieht die Tabelle **nicht** ins Rechenmodell nach, anders als bei den
U-Werten. Ich hatte die Änderung als erledigt gemeldet, bevor ich `HTSTRICH`
nachgerechnet hatte — [[wirkungsprobe-statt-selbstpruefung]].

**How to apply:** Beide Stellen setzen, sonst weichen Dialog und Ergebnis
voneinander ab. Gegenprobe ist `HTSTRICH − Σ(A·U·Fx)/ΣA` aus `TableResult` und
`TableHuellfl`; fehlen beide Felder, rechnet die Software mit **0,10**.

**Fachlich:** Der Zuschlag ist der einzige Hebel, der 1:1 in H'T durchschlägt,
weil das Referenzgebäude mit seinem eigenen festen Zuschlag rechnet und nicht
mitwandert — [[ht-strich-referenz-wandert-mit]]. 0,05 trägt nur im Endzustand,
wenn alle Anschlussdetails saniert sind (Gleichwertigkeitsnachweis DIN 4108
Beiblatt 2), deshalb allenfalls im letzten Paket.

**Bei Klenke ist es bei 0,10 geblieben** (Entscheidung Dennis, 26.09.2026): EH85
wird auch so erreicht. In `CCKZL_Messinger_260908 (1)` steht `BERUECKSWB` bei
allen Varianten auf 0,05 und nur der Ist-Zustand auf 0,1 — dort also anders
gehandhabt. **Vor dem Setzen fragen, nicht als Regel annehmen.**

Teil der Kette: [[sanierungsvarianten-werkzeugkette]].
