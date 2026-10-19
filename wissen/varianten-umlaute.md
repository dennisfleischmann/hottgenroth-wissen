---
name: varianten-umlaute
description: "BDExit speichert Text als CP1252 — Variantennamen und Maßnahmenbezeichnungen mit echten Umlauten schreiben, nicht als ASCII-Umschrift"
metadata:
  node_type: memory
  type: feedback
---

**Keine ASCII-Umschrift in Feldern, die der Kunde im iSFP sieht.** Also
„MP3 Außenwand", nicht „MP3 Aussenwand"; „Haustür Ud 1,3", nicht „Haustuer".
Anweisung Dennis, 26.09.2026.

Das geht problemlos: `satz.ps1` liest und schreibt Text mit
`[System.Text.Encoding]::GetEncoding(1252)`. Betroffen sind vor allem
`TableProjekt.VarianteBez` und `TableHuellfl.SANBEZ` — beide landen im Ausdruck.

```powershell
.\setze-feld.ps1       -Ordner .\arbeit -Tabelle TableProjekt -Feld VarianteBez `
                       -Wert 'MP5 Fenster, Haustür, Lüftung' -Proj 7
.\setze-bauteilfeld.ps1 -Ordner .\arbeit -Proj 7 -Kennzeichen TA -Feld SANBEZ `
                       -Wert 'Haustür Ud 1,3'
```

`SANBEZ` steht **je Variante**: eine Maßnahme, die in MP3 beginnt, trägt ihren
Namen auch in MP4 und MP5 — dort mit umbenennen, sonst stehen zwei Schreibweisen
nebeneinander.

**Why:** Die PowerShell-Konsole zeigt CP1252-Bytes als Mojibake („mÂ²"), was wie
ein Kodierungsfehler aussieht. Ist es nicht — in der Datei stehen sie richtig.
Das war der Grund, aus dem ich zunächst zur Umschrift gegriffen habe.

Teil der Kette: [[sanierungsvarianten-werkzeugkette]].
