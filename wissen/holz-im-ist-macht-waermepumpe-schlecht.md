---
name: holz-im-ist-macht-waermepumpe-schlecht
description: "Steht im Ist-Zustand eine Holzfeuerung, verschlechtert eine Wärmepumpe Primärenergie und CO2 und spart keine Energiekosten — das ist kein Rechenfehler, sondern die GEG-Faktorik"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 2963b319-1199-4575-8f0a-1805717533cc
  modified: 2026-09-28T13:37:10.384Z
---

Bei Pavlov (2HAM5, 28.09.2026) wies MP1 „Boden + Heizung" nach 76.000 € aus:
Endenergie 54.893 → 10.891 kWh, aber **Primärenergie 12.364 → 19.603 kWh**,
**CO2 1,75 → 6,10 t** und **Energiekosten 2.500 → 2.500 €**. Alle drei Zahlen
sind richtig gerechnet — nachgerechnet und auf die Nachkommastelle getroffen.

Die Ursache ist ein einziger Umstand: **Ist = Stückholz, Variante = Strom.**

| | Stückholz | Strom-Mix | Verhältnis |
|---|---|---|---|
| Primärenergiefaktor | 0,2 | 1,8 | ×9 |
| CO2-Faktor (GEG Anlage 9) | 20 g/kWh | 560 g/kWh | ×28 |
| Arbeitspreis | ~7,5 ct/kWh | ~32 ct/kWh | ×4,3 |

Eine Wärmepumpe senkt die Endenergie um Faktor 4–5. Gegen Faktoren von 9, 28
und 4,3 verliert sie damit **zwangsläufig** — bei Primärenergie, CO2 und Kosten
gleichzeitig. Gegen Gas oder Öl (f_P 1,1, ~240/310 g/kWh, ~10 ct) gewinnt
dieselbe Wärmepumpe deutlich. **Der Energieträger im Ist entscheidet über das
Ergebnis, nicht die Qualität der Maßnahme.**

**Gegenprobe, die den Rechenweg bestätigt:** Primärenergie und CO2 setzen an der
Endenergie auf **Heizwert** an (`Q_End_Heizwert`), die Anzeige „Endenergie" am
Brennwert. Holzanteil = `Q_End_Heizwert` − `Q_Prim_Wass`/1,8. Bei Pavlov:
49.567 × 0,2 + 1.361 × 1,8 = 12.364 ✓ und 49.567 × 20 g + 1.361 × 560 g =
1.754 kg ✓.

**How to apply:** Vor jeder Diagnose „die Variante rechnet falsch" erst
`TableHeizung.Erz1Brennst` je Variante ansehen. Stehen dort verschiedene
Energieträger, ist der Fall erklärt und die Arbeit verlagert sich von der
Fehlersuche auf drei Prüfungen:

1. **Stromtarif.** Die iSFP-Maske setzt `EA_STROM_NORMAL` — Haushaltsstrom, bei
   Pavlov 32 ct. Ein Wärmepumpentarif (eigener Zähler, § 14a EnWG) liegt bei
   22–28 ct. Allein das macht aus 0 € Ersparnis rund 550–780 €/a.
2. **Verbrauchsfaktor je Zeile.** Bei Pavlov: Ist 0,51, die Pakete 0,70–0,84.
   Ungleiche Faktoren rechnen die Einsparung klein — [[verbrauchsfaktor-energiekosten]].
3. **Die Botschaft im iSFP.** Steht im Ist eine Teilbeheizung mit Öfen (Pavlov:
   drei Kaminöfen, keine Heizungsanlage, Behaglichkeit „schlecht", Kälte und
   Feuchte), dann vergleicht die Tabelle **ein kaltes Haus mit einem warmen**.
   Für gleiches Geld gibt es Vollbeheizung — das ist das Ergebnis, nicht
   „Sie sparen nichts". Wer das nicht ausspricht, liefert einen Fahrplan, der
   sich selbst widerlegt.

Die Erfassung war in diesem Fall **korrekt** — DENA-Liste Teil D nannte die drei
Kaminöfen mit 40/30/30 % und den elektrischen Durchlauferhitzer, und genau so
stand es im Modell. Die Unterlagen zu prüfen war trotzdem richtig: erst dadurch
war „Rechenfehler" ausgeschlossen ([[partnerlisten-sind-hinweis]]).

Verwandt: [[dachschritt-einsparung-plausibel]] · [[variantenanalyse-quellen]].
