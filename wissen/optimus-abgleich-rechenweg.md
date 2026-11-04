---
name: optimus-abgleich-rechenweg
description: "Optimus (hydraulischer Abgleich) rechnet je FBH-Kreis mit festen Formeln — Last nach Normleistung 50/40 aufgeteilt, Spreizung 5…15 K geklemmt, +15 % Volumenstrom, Colebrook; Ergebnisse sind flüchtig, nur der Bericht hält sie"
metadata:
  type: reference
---

**Gemessen am 04.11.2026** am Projekt „Jonathan Hilgert_Heizlastberechnung (1)": die
Nachrechnung `skripte/optimus/optimus-nachrechnen.py` trifft kv-Werte und
Voreinstellungen von 15 der 19 Kreise exakt, Durchflüsse auf 3–5 %.

Der Kern ist `TCalcOptimusCalculation` in **`Hsetu.FW.Calculations`** (nicht in
`Hsetu.Optimus.BL`, das ist nur Oberfläche + Einstieg
`CalculateHeatloadAndHydraulicBalancingCommand`). Strategie S5 = Heizlast, S2 = Anlage.
Je Fußbodenheizkreis (`TCalcOptimusSingleCircuitCalcObject`):

- `Q_req = Q_Raum · Q_50/40 / Σ Q_50/40` der Kreise des Raums
- `Δθ_erf = (Q_req/Q_50/40)^(1/1,1) · 25 K`; `t_V,erf = trunc(Δθ_erf + t_i + 2,6)`,
  Grenzen 26 °C und min(52 °C, Kessel-Maximum)
- Spreizung aus Vorlauf und Δθ_erf, **geklemmt auf 5…15 K** — ΔT = 5,0 K überall heißt
  „Vorlauf zu niedrig erzwungen"
- `V̇ = Q_req/(4,2·ΔT)·3,6/993 · 1,15` (15 % Aufschlag fest einprogrammiert)
- Rohr `L = A/VA`, Colebrook mit k = 0,0015 mm, ν = 4,8e-7, ρ = 993
- Verteilerniveau = ungünstigster Kreis (Rohr + Ventil offen); Voreinstellung aus
  `kv = V̇/√(Δp_V/1000)`; Ventil ohne Katalog kvs 0,7, „Abgang Verteiler" kvs 2,4
- Förderhöhe = Sonstiges + max(Zuleitungs-Heuristik `(V̇/(4,3·A_Raum))²·L`, Niveau)

**Nichts davon steht in der Datenbank.** `PmCircuit.*Flow/DeltaP` ist der Normzustand
50/40, nur `PmDistribution.VolumetricFlow/DeltaP` und die Ventile in `PmBranch` werden
beim Speichern geschrieben. Der gedruckte Bericht ist die einzige vollständige
Aufzeichnung eines Laufs.

Vollständig mit Fundstellen, Datenmodell und Prüfliste:
`doku/hsetu/OPTIMUS-HYDRAULISCHER-ABGLEICH.md`. Verwandt:
[[optimus-foerderhoehe-ist-heuristik]], [[hilgert-abgleich-befund]].
