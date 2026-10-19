---
name: dachschritt-einsparung-plausibel
description: "„Paket spart fast nichts" prüfen mit k = ΔQ_h/(A·ΔU): bei 15 Dach/OGD-Schritten Median 70, Spanne 55–103; Prozente taugen nicht zum Vergleich"
metadata:
  type: reference
---

Wenn ein Paket „kaum etwas bringt", **nicht in Prozent vergleichen**. Prozente
hängen am Ausgangszustand und an der Paketposition: dieselbe Deckendämmung spart
bei Steidl als Paket 1 **3,3 %**, im Schwesterprojekt als Paket 3 **8,2 %** —
absolut 1.437 gegen 1.367 kWh/a, also dasselbe.

**Vergleichbar ist die Einsparung je m² je Punkt U-Wert:**

```
k = ΔQ_h / (A_Bauteil × (U_vor − U_nach))      [kWh/a je m²·W/m²K]
```

Stand 16.09.2026, 15 reine Dach-/OGD-Schritte aus 33 verschiedenen Gebäuden der
LocalDB: **Median 70, Spanne 55–103.** OGD gegen unbeheizten Dachraum (F_x 0,8)
liegt eher unten (Steidl 61), Steildach gegen außen eher oben. Liegt ein Projekt
darin, rechnet es richtig — dann ist das Ausgangs-U der Grund, nicht ein Fehler.
Ein Dach mit U 2,1 spart je m² achtmal so viel wie eines mit 0,38.

**Datenquelle ohne Hottgenroth-Neurechnung:** Die `iSFP2.xml` in `PrMedia` trägt
für den Ist-Zustand (`/iSFP-Projekt/bilanz`) und für **jedes** Paket
(`massnahmenpakete/item/bilanz`) `energie/Q_h_b`, `H_T`, `H_V`, `Q_f`, `Q_P` sowie
`bauteile/A_*` und `U_*`. Pakete sind kumulativ: Differenz zum vorigen Schritt =
Wirkung des Pakets; geändertes `U_*` = betroffenes Bauteil. Kopien derselben
Gebäude über die Ist-Signatur (H_T, Q_h) zusammenlegen, sonst zählen Messinger &
Co. mehrfach. Der Export ist ein Schnappschuss — sein Datum nennen.

**Vorher ausschließen:** Rechnet die Variante die Maßnahme überhaupt? `K_ZAHL` in
der Bauteiltabelle bleibt beim Ist-Wert stehen, maßgeblich ist `Constructions[n].fU`
im Kernel der Variante — siehe [[sanierungsvarianten-werkzeugkette]].

Verwandt: [[isfp-export-pruefen]]
