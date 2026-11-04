---
name: optimus-foerderhoehe-ist-heuristik
description: "Die Optimus-Förderhöhe einer FBH-Verteilung = Verteilerzuleitung als Rohr (d_i aus dem Vorlaufanschluss, Standard 20 mm, Länge DistanceToPump) + ungünstigster Kreis, mindestens eine Netz-Heuristik; Hilgert 1 730 mbar = 15-mm-Zuleitung × vierfacher Durchfluss"
metadata:
  type: reference
---

**Gelesen** in `TCalcOptimusCircuitDistributionDpPumpCalcObject.CalcDpPump` /
`CalcMaxPressureLoss` und `TCalcOptimusDistributorCalcObject.CalcDpPipe`
(`Hsetu.FW.Calculations~5e976678.cs`), **gemessen** an beiden Hilgert-Berichten
(Nachrechnung 1 818/611 gegen 1 730/571 mbar bei 35 °C, 1 202/149 gegen 1 070/152 bei 45 °C;
Rest = quadrierter Durchfluss-Überhang von 3–5 %).

    Förderhöhe = Δp_sonstigeGeräte + Δp_Zähler + max( Netz-Heuristik , Δp_Zuleitung + Δp_Rohr,worst + Δp_Ventil,offen )

- **Δp_Zuleitung** ist ein echtes Rohr: Colebrook über `PmDevice.DistanceToPump` (einfache
  Länge) mit `d_i = PmConnection.InnerDiameter` des Verteiler-**Vorlaufanschlusses**
  (`PmDistributor.SupplyConnectorUUID`); ist er leer, nimmt der Kern **20 mm**. Durchfluss =
  Summe aller Kreise. Für die Ventilwahl wird dieser Anteil wieder abgezogen — die
  Voreinstellungen hängen also nicht davon ab, nur die ausgewiesene Förderhöhe.
- **Netz-Heuristik** `R = max(0,2; (V̇[l/h]/(4,3·A_Raum[m²]))²)` mbar/m × Zuleitungslänge —
  auf ~20 K Spreizung geeicht, bei erzwungenen 5 K 16-fach; sie greift nur, wenn sie über
  dem Rohrpfad liegt (bei Hilgert erst ab ~25 mm Zuleitung).

Hilgert: beide Verteiler tragen `InnerDiameter 0,015`, 19 bzw. 26 m. 2 275 l/h (ΔT auf 5 K
geklemmt, weil 35 °C fest bei Bestandsheizlast) durch 15 mm = 3,7 m/s ≈ 1 500 mbar. Mit 20 mm
wären es 666, mit 25 mm 583 mbar (dann Heuristik). Kein Rechenfehler — zwei Eingaben.

**How to apply:** Förderhöhe > 400 mbar bei FBH → zuerst Vorlaufanschluss-Durchmesser und
`DistanceToPump` des Verteilers prüfen, dann ob ΔT überall 5,0 K ist (Vorlauf zu niedrig
erzwungen). `skripte/optimus/optimus-nachrechnen.py --di 20` zeigt den Unterschied; ob die
15 mm eingegeben oder aus einer Vorlage stammen, steht nicht in der DB.

Verwandt: [[optimus-abgleich-rechenweg]], [[hilgert-abgleich-befund]].
