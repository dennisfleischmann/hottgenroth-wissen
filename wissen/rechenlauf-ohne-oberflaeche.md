---
name: rechenlauf-ohne-oberflaeche
description: "Die DIN-18599-Rechnung läuft ohne Energie.exe — Qh trifft den Container auf die kWh; aber sie schreibt NICHT in den Container zurück"
metadata:
  type: reference
---

**Erprobt am 27.09.2026** an `ZZTEST_Rechenlauf_260927` (importiert aus
`3QHTK_Lennart Krause_260923`, UUID `d7535cb2-d713-491b-ae1d-0354675df8eb`,
Gruppe `a9363d60-2f82-4669-8d1b-afe638d75493`).

## Was geht

**Der Rechenkern läuft von außen**, kopflos, rund 40 s je Lauf, über
`hsetu-bridge.exe`. Kette:

```
  [Laden wie in [[hsetu-projekt-headless-laden]], 31 Schritte]
  geb   = bim.Buildings.GetItem(0)            # kein get_Item! First() geht auch
  basis = geb.Calculation.BuildingCalcBasisType
  set     basis.TypeValue = {$enum TTechDataBuildingCalcBasisType.becGEG2024}
  calc  = new Hsetu.EbCalc.IbpKernel.Calc.KernelCalculator
  set     calc.Domain = bereich.Domain        # NICHT bereich selbst
  call    calc.Initialize() / Check() / Execute()
  geb.CR  0 -> 24 Ergebnisse
```

**Die Lizenz blockiert nicht** — auch der Projektimport über die Brücke, ein
schreibender Aufruf, lief durch.

**Und es rechnet dasselbe Gebäude:** `CalcResultEnergyDemand.NetEnergyHeatingAbsolute`
= **7.138 kWh**, exakt das `Qh` aus `TableHeizung`. Andere Größen sind anders
definiert (FinalEnergyTotal 2.713 gegen Endenergie 2.348) — der Kern stimmt.

Die 24 Ergebnisse tragen unter anderem:
`CalcResultEnergyDemand` · `CalcResultBuildingStructure` ·
**`CalcResultPlantDescriptionHeating`** · **`CalcResultPlantDescriptionDHW`** —
die beiden letzten sind die Quelle von `Beschr_Heiz` und `Beschr_Wass`
([[isfp-komponenten-kommen-aus-dem-container]]).

## Was nicht geht

**Der Delphi-Container bleibt unberührt.** Nach `Execute()` war `eberater.zip`
byte-identisch: gleiche Größe, gleiche SHA-256, gleicher Zeitstempel. Die
Ergebnisse landen in `TModelBuilding.CR` auf der Hsetu-Seite, nicht in
`TableHeizung`/`TableResult`.

**Damit ersetzt dieser Weg das „Variante öffnen und speichern" NICHT.**

**Zweite Grenze:** gerechnet wird das **BIM-Gebäude**, und das gibt es je Projekt
nur einmal — die Maßnahmenpakete liegen je Container-Variante
([[varianten-sind-schnappschuesse]]). Dieser Weg liefert also den Ist-Zustand,
nicht Paket 1 bis 5. Ob sich der Rechner auf eine Variante richten lässt, ist
offen; der Ansatzpunkt wäre der `Kernel18599V5`-Blob statt der BIM-Domain.

## Wofür es trotzdem taugt

1. **Wirkungsprobe ohne Oberfläche.** Den Ist-Zustand von außen nachrechnen und
   gegen den Container halten — das hätte diese Woche mehrere stille Fehler
   gefunden ([[wirkungsprobe-statt-selbstpruefung]]).
2. **`Beschr_Heiz`/`Beschr_Wass` erzeugen** statt von einer anderen Variante
   abschreiben.

Die nativen Kerne (`IBP18599KernelNavigatorV3.dll` u. a.) sind **nicht**
reflektierbar (`BadImageFormatException`); `Hsetu.EbCalc.IbpKernel` ist die
.NET-Hülle, nur über sie führt der Weg.
