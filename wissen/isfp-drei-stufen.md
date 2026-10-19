---
name: isfp-drei-stufen
description: "Ein iSFP durchläuft drei Programme, nicht zwei — die Eingabemaske sitzt bei Hottgenroth, nicht in der Druckapplikation"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 32fdc294-1833-481e-a848-ce79a2baf48b
  modified: 2026-09-13T05:57:27.359Z
---

Wer den iSFP nachbauen oder verstehen will, muss die Arbeitsteilung kennen:

| Stufe | Programm | Was dort geschieht |
|---|---|---|
| 1 | **Energieberater** (`Energie.exe`) | bilanziert nach DIN V 18599, rechnet ~95 Kennwerte |
| 2 | **iSFP 2 – Datenerfassung zur Weitergabe an die iSFP-Druckapplikation** | **die Eingabemaske**: 13 Reiter, 369 Felder, 291 Hints, eigene Warnungsliste |
| 3 | **MeinSanierungsfahrplan** | prüft, markiert Unplausibles, druckt, signiert |

**Stufe 2 steckt im selben `Energie.exe`** unter
`C:\Program Files\HSETU\EnergieberaterPlaner\` (286 MB, Delphi). Das Formular heißt
`TFormAusdr_iSFP20` und liegt als **binäres DFM im Klartext ab Byteversatz 274420260**,
523.996 Bytes. Delphi-Textliterale sind UTF-16LE (`tr -d '\000'` zum Suchen), die
DFM-Hints dagegen UTF-8. Eigene Steuerelementklassen (`TNumEdit` 163×,
`TFormatCheckBoxHS` 53×) — wer nur nach Delphi-Standardklassen sucht, zählt zu wenig.

**`.mSFPprojekt` ist die `iSFP2.xml`** — kein Behälter, keine Kompression. `.mSFP` ist
die Altendung. Dieselbe Datei liegt als Medienanhang in `PrMedia.Media`
([[isfp-export-pruefen]]). Das Modul startet die Druckapplikation mit **positionalem**
Dateinamen plus `--logfile`; `--infile`/`--outfile-sfp`/`--outfile-uh` kennt nur die
Druckapplikation selbst.

**Eingabe oder gerechnet** erkennt man im DFM an `ReadOnly=True` **und** `TabStop=False`
(103 Felder) — deckungsgleich mit `Veränderbar: nein` im Schema. `MaxLength` ist im DFM
**nie** gesetzt; Längen stehen nur im Hint, stimmen aber zu ~95 % mit dem Schema.

**Why:** Ich habe zuerst die Druckapplikation nachgebaut und die Eingabefelder aus dem
Schema erraten — der ganze erste Plan zielte eine Stufe zu weit hinten. Die Maske lag
die ganze Zeit als Formular vor.

**How to apply:** Für Fragen nach *Eingabefeldern, Beschriftungen, Hints, Wertelisten*
ins DFM von Stufe 2 sehen. Für *Druck, Seitenlayout, Plausibilitätsprüfung* in den
Korpus von Stufe 3 ([[isfp2-dekompiliert]]). Die Plausibilität gibt Stufe 2 ausdrücklich
ab: „Rufen Sie hierfür die Druckapplikation auf." Feldzuordnung DFM→Schema ist nur zu
28 % über Namensähnlichkeit möglich — messen statt raten: Feld füllen, speichern,
XML diffen. Autosicherungen dafür liegen alle 10 Minuten frisch unter
`%APPDATA%\HSETU\EnergieberaterPlaner\AutoSicherungISFP\`.
