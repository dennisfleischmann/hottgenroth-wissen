---
name: sanierungsmassnahme-acht-felder
description: "Zu einer Sanierungsmaßnahme gehören acht Felder; die Sowieso-Kosten stehen nirgends — sie sind SANKOSTEN minus SANKOSTEN_EE, gerechnet auf die BRUTTOfläche"
metadata:
  node_type: memory
  type: reference
  originSessionId: 4f0538bd-ca70-49d8-9f49-7c802c435628
  modified: 2026-09-12T13:52:31.207Z
---

`saniere.ps1` setzt nur `SANK_ZAHL`. Zu einer Maßnahme gehören **acht** Felder in
`TableHuellfl`, und ohne sie bleibt die Wirtschaftlichkeitstabelle leer:

| Feld | |
|---|---|
| `SANBEZ` | Bezeichnung — fehlt sie, ist die Zeile in der Wirtschaftlichkeit namenlos |
| `SANK_ZAHL` | Ziel-U-Wert |
| `SANKOSTENQM` · `SANKOSTEN` | Kosten je m² und gesamt |
| `SANKOSTENQM_EE` · `SANKOSTEN_EE` | energiebedingte Mehrkosten |
| `SANDICKE` · `SANLAMBDA` | Dämmstoff |

**Die Sowieso-Kosten stehen nirgends gespeichert.** Sie sind
`SANKOSTEN − SANKOSTEN_EE`; die Software bildet sie daraus. Wer nur `SANKOSTEN`
setzt, bekommt eine Maßnahme, die zu **100 % als energiebedingt** gilt — und damit
eine zu hohe Förderung im iSFP. Bei der Aufsparrendämmung wären das 30.883 €
förderfähig statt 6.075 €.

**Bezugsfläche ist `FLAECHE_BR` (brutto), nicht `FLAECHE`.** `FLAECHE` ist netto,
nach Abzug von Fenstern und Türen. An 33 Bauteilen geprüft:
`SANKOSTEN / SANKOSTENQM` trifft `FLAECHE_BR` auf die zweite Stelle.

**Die €/m² aus dem Kostentool sind auf die NETTOfläche gerechnet** — sie lassen
sich nicht einfach übernehmen. Bei Klenke: WDVS 24.200 € auf 99,02 m² netto =
244,40 €/m²; `setze-massnahme.ps1` multipliziert das mit `FLAECHE_BR` 121,70 m²
und schreibt **29.742 € statt 24.200 €**, ohne Meldung. Immer aus dem
Zielbetrag zurückrechnen: `KostenQm = Betrag / FLAECHE_BR`, mit vier
Dezimalstellen, dann trifft die Summe auf den Cent. Nur bei Bauteilen ohne
Öffnungen (Decken, Fenster, Türen) sind netto und brutto gleich.

**Why:** Bei drei Maßnahmen ist der volle Betrag energiebedingt und richtig so —
Kellerdeckendämmung, Perimeterdämmung, Innendämmung fallen ohne energetischen
Anlass nicht an. Bei allem, was ohnehin ansteht (Dacheindeckung, Fenstertausch),
ist der Sowieso-Anteil der größere Teil und muss gesetzt werden.

**How to apply:** `setze-massnahme.ps1` setzt alle acht in einem Aufruf und
rechnet die Beträge aus `FLAECHE_BR`. **Auswahl über Bauteilmuster, nicht über das
Kennzeichen** — an einem Kennzeichen hängen oft mehrere Maßnahmen (an `WA` sowohl
„WDVS Außendämmung" 266 €/m² als auch „WDVS Kellerwand" 289 €/m²). `-Vorschau`
rechnet, ohne zu schreiben.

**`-Loeschen` nimmt die Maßnahme NICHT zurück — es nullt sie.** Die acht Felder
bleiben mit `0` bzw. Leerstring im Satz stehen. Zwei stille Folgen:
`uwerte-uebernehmen.ps1` nimmt „SANK_ZAHL wenn vorhanden" wörtlich und trägt
**U = 0,000** ins Rechenmodell ein, und die Software hält das Bauteil weiter für
saniert, weil `SANK_ZAHL` existiert — das Paket sieht dramatisch besser aus als
es ist. Stattdessen `entferne-bauteilfeld.ps1 -Massnahme`
([[bdexit-feld-entfernen]]) und danach `uwerte-uebernehmen.ps1`; dann steht
wieder `K_ZAHL` im Blob.

Teil der Kette: [[sanierungsvarianten-werkzeugkette]].
