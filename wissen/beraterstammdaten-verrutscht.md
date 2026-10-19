---
name: beraterstammdaten-verrutscht
description: Das Beraterprofil in Energie.exe liefert firma/vorNachname/StrasseHnr um eins verschoben in die iSFP-XML; BAFA-Nr und Anschrift stehen in vier Projekten in drei Schreibweisen
metadata: 
  node_type: memory
  type: project
  originSessionId: a9df26c4-f679-4aee-bc74-1016fcac6cb2
  modified: 2026-09-27T06:43:32.053Z
---

Der `<energieberater>`-Block, den Energie.exe in die iSFP-XML schreibt, ist um ein
Feld verschoben:

```
firma       = (leer)
vorNachname = Firma
StrasseHnr  = FS Energieberater GmbH
PLZ         = 60486             ← ab hier wieder richtig
ort         = Frankfurt am Main
```

Dazu kommt, dass dieselben Angaben in vier Projekten unterschiedlich lauten:
BAFA-Nr. `EB603279` / `603279` / `653345`, Straße `Angelika-Machinek-Straße 14` /
`Angelika Machinek Straße 14` / `Angelika-Machinek-Str. 14`. Richtig ist
**Angelika-Machinek-Str. 14, 60486 Frankfurt am Main**, BAFA **EB603279**,
Firma `Firma`, Name `FS Energieberater GmbH`.

**Why:** Am 26.09.2026 bei Klenke aufgefallen — im Anschreiben stand die Firma
in der Namenszeile und der Name in der Straßenzeile. Von Hand in der fertigen
Datei korrigiert; im Hottgenroth-Projekt steht die Verschiebung weiterhin, also
kommt sie aus dem Beraterprofil und nicht aus einem Tippfehler im Projekt.

**How to apply:** `stammdaten.json` im iSFP-Werkzeug führt die richtigen Werte,
und `isfp-fertigstellen.ps1` **überschreibt** damit — anders als bei allen
anderen Feldern, wo nur Leerstellen gefüllt werden. Jede Korrektur wird als
`alt -> neu` ausgegeben; `-StammdatenLassen` schaltet es ab. Die Quelle selbst
ist damit nicht repariert: das Profil in Energie.exe ist noch offen.
Siehe [[isfp-kostenpositionen-aus-huellfl]].
