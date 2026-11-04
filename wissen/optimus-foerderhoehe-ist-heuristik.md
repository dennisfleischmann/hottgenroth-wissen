---
name: optimus-foerderhoehe-ist-heuristik
description: "Die Optimus-Förderhöhe bei Fußbodenheizung ist keine Rohrnetzrechnung — Zuleitung als (V̇/(4,3·A))²·L geschätzt, explodiert bei erzwungener 5-K-Spreizung; 1 730 mbar im Hilgert-Bericht sind so entstanden"
metadata:
  type: reference
---

**Gelesen** in `TCalcOptimusCircuitDistributionDpPumpCalcObject.CalcDpPump`
(`Hsetu.FW.Calculations~5e976678.cs`, Z. 26500 ff.), **gemessen** am Hilgert-Bericht.

Die Förderhöhe einer FBH-Verteilung setzt sich zusammen aus
`Δp_sonstigeGeräte + Δp_Zähler + max(Δp_Zuleitung, Verteilerniveau)`. Das Verteilerniveau
(ungünstigster Kreis: Rohrreibung + offenes Ventil) ist echte Physik und stimmt (Hilgert EG
≈ 270 mbar). Die **Zuleitung** dagegen ist eine Heuristik:

    R [mbar/m] = max(0,2 ; (V̇_ges [l/h] / (4,3 · A_beheizt [m²]))²),  Δp = R · L_Zuleitung

mit `A_beheizt` = Summe der *Raumflächen* der versorgten Räume und `L_Zuleitung` =
`PmDevice.DistanceToPump` des Verteilers. Sie ist auf ~20 K Spreizung geeicht. Zwingt man den
Vorlauf auf 35 °C bei Bestandsheizlast, klemmt der Kern die Spreizung auf 5 K → vierfacher
Volumenstrom → **16-facher** spezifischer Druckverlust (Hilgert EG: 30,7 mbar/m × 19 m = 583
mbar). Dazu kommt ein weiterer, mit V̇² wachsender Anlagenanteil (EG ≈ 1 150, OG ≈ 210 mbar;
verhält sich wie ein Gerät mit kvs ≈ 2,1, vermutlich der Anlagenpfad, weil „Pumpe nicht
vorhanden" = Anlagenpumpe). **Zerlegung offen** — braucht einen Lauf mit
`calculation.WriteLog = true`.

**How to apply:** Eine FBH-Förderhöhe über ~400 mbar im Optimus-Bericht ist ein Symptom der
Eingaben (zu niedriger fester Vorlauf, zu hohe Heizlast, keine Pumpe eingetragen), kein
Pumpenauslegungswert. Erst `RatedFlowTemperature` freigeben und Heizlast prüfen, dann drucken.

Verwandt: [[optimus-abgleich-rechenweg]], [[hilgert-abgleich-befund]].
