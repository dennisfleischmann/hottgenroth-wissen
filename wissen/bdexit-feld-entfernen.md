---
name: bdexit-feld-entfernen
description: "Ein BDExit-Feld entfernt man über die Anwesenheitskarte (2 Bit je Feld, Wert 2 = fehlt); Nullen genügt nicht und erzeugt stille Fehler"
metadata:
  type: reference
---

Am Satzanfang steht die **Anwesenheitskarte**: zwei Bit je Feld, ab Byte 1 des
Vorspanns, vier Felder je Byte.

```
0  = Feld steht im Satz
2  = Feld fehlt        (das schreibt die Software selbst)
```

`BdeSchreib` in `satz.ps1` kann ein Feld nur **freischalten** (Bits auf 0) — es
gibt dort keinen Weg, eines zu entfernen. Dafür jetzt
`werkzeuge/bdexit/entferne-bauteilfeld.ps1`:

```powershell
.\entferne-bauteilfeld.ps1 -Ordner .\arbeit -Proj 3 -Kennzeichen OG -Massnahme
.\uwerte-uebernehmen.ps1   -Ordner .\arbeit -Proj 3     # danach IMMER
```

`-Massnahme` nimmt die acht Felder aus [[sanierungsmassnahme-acht-felder]],
`-Felder` einzelne. Weil Satzlängen schrumpfen, wird der Datenteil ganz neu
geschrieben; die Gegenprobe liest danach jeden Satz zurück.

**Why:** Am 26.09.2026 sollte bei Klenke die oberste Geschossdecke von MP1 nach
MP2 wandern. `setze-massnahme.ps1 -Loeschen` nullte die Felder, ließ sie aber im
Satz — `uwerte-uebernehmen.ps1` trug daraufhin **U = 0,000** ins Rechenmodell ein.
Eine Decke ohne jeden Wärmedurchgang, und keine der drei Prüfungen von
`pruefe-variante.ps1` hätte das gemeldet: die UA wäre gefallen, monoton, und
Bauteilliste und Modell wären sich einig gewesen. Aufgefallen ist es nur, weil
`uwerte-uebernehmen` die Änderung `0.140 -> 0.000` ausdruckt.

**Was ein genulltes Feld im iSFP anrichtet** — gemessen am 30.09.2026 bei Klenke:
in der ersten Variante stand an zwei Kellerfenstern `SANBEZ` = ein einzelnes `0x00`,
`SANK_ZAHL` leer, **aber `SANKOSTEN` mit 4.200 € unverändert stehen**. Für die
iSFP-Maske ist ein leerer Text kein fehlender Text: der Wechsel auf
„Kellerfenstertausch" fiel damit erst in die zweite Variante, und der gedruckte
Fahrplan zeigte im zweiten Paket „Außenwand **und Fenster**", obwohl dort nur die
Fassade saniert wird ([[isfp-komponenten-kommen-aus-dem-container]]). Eine halb
gelöschte Maßnahme schiebt ihre Komponente also ein Paket weiter — mit Kosten, die
niemand dort erwartet.

**How to apply:** Welche Felder zu entfernen sind, nicht raten — den Satz mit
einem Satz derselben Art im **Ist-Zustand** vergleichen und genau die Felder
nehmen, die dort fehlen. Der Ist-Zustand ist von der Software geschrieben und
damit die Referenz für das, was „keine Maßnahme" heißt.
