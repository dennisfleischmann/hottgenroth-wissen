---
name: ibp-blob-lesefallen
description: "Beim Messen am flachgezogenen IBP-Blob: OperatingData wird gar nicht serialisiert, fValue ist nur bei Energien die Jahressumme, und die Zonen-Ergebnisschicht fehlt ganz"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 1f0988c2-fbda-498e-bc4f-0bd047948fdc
  modified: 2026-09-28T05:19:37.641Z
---

Drei Fallen beim Messen am `Kernel18599V5`-Blob. Jede hat schon einen falschen
Befund erzeugt, zwei davon am 27./28.09.2026 an derselben Lüftungsfrage.

## 1 — `OperatingData` steht nicht im Container

`P6RVSystemUnit.GetObjectData` serialisiert 44 Felder, **`OperatingData` ist
nicht dabei**. Bytetest an `mp5.bin`: `m_OperatingData` und `P5OperatingData`
kommen **nullmal** vor, `m_enRVSystem` genau **einmal** (die Stelle an der Zone).

Beim Laden wird es als `new P5OperatingData()` neu gebaut. Alles, was ein
flachgezogener Auszug unter `UnitRV[0].OperatingData.*`,
`UnitHeating[0].OperatingData.*`, `CircuitHeatWater…OperatingData.*` zeigt, sind
also **Vorgabewerte nach dem Laden** — nicht der Zustand des Rechenlaufs. Das
erklärt auf einen Schlag: `enRVSystem = ExhaustSystem`,
`Monthly[*].feta_WUET_mth = 0`, `bHeatRecovery = False`,
`bIsNonResidential = True`. Keines davon ist ein Befund.

Folge fürs Werkzeugbauen: die zweite `enRVSystem`-Stelle am Gerät kann man nicht
setzen, und man muss es auch nicht. `GetConfigurationUnit` setzt sie je Lauf erst
auf `ExhaustSystem` zurück und bildet dann das Maximum über die Zonenbereiche.
**Was ein Werkzeug sichern muss, ist die Verweiskette** Gerät → Luftkreis →
Übergabe → Zonenbereich (`UnitCircuitInterrelation`-Eintrag, `strIDLink`,
`strLinkedRVDomain`). Fehlt `strLinkedRVDomain`, bleibt der Wert 0 und der Kern
rechnet still mit `ExhaustSystem` weiter.

## 2 — `fValue` ist nur bei Energien die Jahressumme

Monatsgrößen tragen `fJan..fDec` plus ein `fValue`. Über 2.119 solche Gruppen in
einem Blob gemessen, 93 davon belegt:

| Verhalten von `fValue` | Fälle | wo |
|---|---|---|
| Jahressumme | 33 | `fQ_*`, `Q_*`, Zähler `ft_h`, `fHH_t`, `fHDH_*`, `ft_ON_*` |
| 12er-Mittel | 11 | Temperaturen `ftheta_i`, Außentemperaturen — **und `E_sol`, eine Energie** |
| eigenständig gerechneter Jahreswert | 36 | `fSPF_h`, `IntensityOfRadiation`, `WindSpeed` |
| 0 trotz belegter Monate | 5 | u. a. `feta_WUET_mth`, `ftheta_L_m_Zuluft` |

**Die Dimension entscheidet nichts, der Name auch nicht.** `ftheta_L_m_Zuluft`
(12 × 21 °C) hat `fValue = 0`, `ftheta_i` (13/22 °C) hat 15,25 — beides
Temperaturen.

Regel zum Messen: **maßgeblich sind immer die zwölf Monate.** `fValue`
ungeprüft nur bei `fQ_*`/`Q_*` und den Zählern. `fValue = 0` ist **kein Befund,
sondern eine Leerstelle.** Verhältnisgrößen nie aus Monatsverhältnissen
rekonstruieren, sondern aus den gespeicherten Jahressummen von Zähler und Nenner
— `fSPF_h = ΣfQ_outg_h_WP / (ΣfQ_h_f + ΣfQ_h_g_aux) = 2,479402`, auf 4,5e-08.
Vergleiche mit relativer Toleranz ~1e-6, alles ist float32.

## 3 — Die Zonen-Ergebnisschicht wird nie gespeichert

`Zones[0].P2Results`: von 4.240 Zeilen stehen 4.113 auf 0.
`Zones[0].P5ResultsHeating` 938 Zeilen alle 0, `P8ResultsDHW` 209 alle 0,
`UnitRV[0].ResultsEnergy` 938 alle 0 — obwohl das Projekt unbestritten Heizung
und Warmwasser hat. Auch `ff_z = 0` bei `bf_z_Standard = True`, wo die Formel 1
braucht.

**Wer eine Wirkung auf der Zonenseite belegen will, findet sie im Blob nicht.**
Es bleiben die Endenergie in `TableResult`, die `iSFP2.xml` — oder der
Rechenlauf ohne Oberfläche mit Zugriff auf `P2Results` im Speicher
([[rechenlauf-ohne-oberflaeche]]).

Gegenstück: [[wirkungsprobe-statt-selbstpruefung]] sagt, dass man messen muss.
Diese Notiz sagt, **woran** man messen darf.
