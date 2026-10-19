---
name: vorlauftemperatur-zwei-stellen
description: "Die Auslegungstemperatur steht an zwei unabhängigen Stellen — Heizkreis und Wärmepumpe selbst; für hohe EH-Stufen müssen beide 35/28 tragen, zusammen mit Flächenheizung"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 49e4b8c1-37be-419d-98a1-aa61b55d2177
  modified: 2026-08-13T21:21:31.117Z
---

**Regel: Standard-iSFP 55/45 mit Heizkörpern. Soll eine hohe Effizienzhaus-Stufe
erreicht werden, dann 35/28 mit Flächenheizung — und zwar an BEIDEN Stellen.**

Die Auslegungstemperatur steht an **drei** Stellen, alle drei müssen zusammenpassen:

| Oberfläche | Feld |
|---|---|
| **Verteilsystem** | `P5HeatWaterCircuit.ftheta_VA` / `.ftheta_RA` |
| **Wärmepumpe selbst** (Reiter Erfassung, „Auslegung") | `P58HeatGeneratorHeatPumpComponent.ftheta_VA` / `.ftheta_RA` |
| **„niedrige Temperaturebene"** | `P5HeatWaterCircuit.bLowerTemperatureLevel` |

Der dritte ist der leicht zu übersehende: ohne ihn bleibt die Arbeitszahl auf dem
Wert der hohen Temperaturebene, **obwohl 35/28 dasteht**. Gemessen am selben
Projekt: `False` bei 55/45, `True` nach der Umstellung auf 35/28.
`ibp-anlage-setzen.exe` leitet ihn seitdem aus der Vorlauftemperatur ab
(≤ 45 °C → `True`) und meldet ihn in der Ausgabe.

Dass sie unabhängig sind, ist belegt: ein Projekt der Erhebung führt Kreis 80/60 neben
Kessel 70/55, ein weiteres Kreis 66/51 neben Kessel 70/55. Im Austauschformat sind es
deshalb getrennte Angaben — `heizung.auslegung` für den Kreis, `vorlauf`/`ruecklauf`
je Erzeuger für die Wärmepumpe.

**Nicht mitziehen:** die Senke `ftheta_si_out`/`ftheta_si_in`. Sie steht in allen 24
Wärmepumpenprojekten auf 60/50 und beschreibt den Prüfpunkt der Kennlinie
([[ibp-bauart-felder]]).

**Why:** Am 13.08.2026 stand das Verteilsystem auf 35/28, die Wärmepumpe aber auf
55/45 — die Arbeitszahl blieb schlecht, und EH40 war nicht erreichbar. Der Nutzer hat
es gefunden, nicht ich: mein Vorgabesatz setzte beide auf 55/45, und beim Anheben auf
EH40 hatte ich nur die Bauart auf Sole/Wasser umgestellt, nicht die Auslegung.

**35/28 verlangt Flächenheizung.** An Heizkörpern deckt diese Vorlauftemperatur die
Heizlast nicht. Die 15 Flächenheizungsprojekte der Erhebung führen durchgängig:
Kreis 35/28, Erzeuger 35/28, `WaterPanel`, Regelung 7, `fTemperatureRise` = 0.

**How to apply:** Zwei Vorgabesätze in `werkzeuge/ibp/vorgaben/` —
`waermepumpe-sanierung.json` (55/45, Heizkörper, Standardfall) und
`waermepumpe-flaechenheizung.json` (35/28, Flächenheizung, hohe EH-Stufe).
Siehe [[waermepumpe-vorgabesatz]] und [[eh-haus-pflichtbestandteile]].
