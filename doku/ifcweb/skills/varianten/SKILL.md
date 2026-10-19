---
name: varianten
description: Sanierungsvarianten im EE-Berater - Variante anlegen, Bauteile sanieren, Fx-Faktoren und unbeheizte Nachbarn. Ausloeser - Variante, Sanierung, SANK_ZAHL, eberater.zip, Fx, Daemmung ansetzen.
erprobungsstand: erprobt
---

**Stand:** Anlegen einer Variante und Sanieren von Bauteilen sind **erprobt**, ohne
SQL-Modellkopie. Das BDExit-Format ist vollständig entschlüsselt.

**Beschreibung:** `hsetu-decompiled/SANIERUNGSVARIANTEN.md`.
**Werkzeuge:** `hsetu-decompiled/werkzeuge/bdexit/` — `bde.ps1` liest den Kopf,
`satz.ps1` liest und baut einen Satz feldweise neu, `saniere.ps1` setzt Kennwerte.

## Fallen

- **Ein Projekt kann mehrere eberater-Container in `PrMedia` führen.** Maßgeblich
  ist der mit dem jüngsten `StampEdit`; der andere ist ein Überrest. Wer den
  ersten nimmt, den die Datenbank liefert, liest je nach Laune den falschen.
- **Prüfstein vor jedem Schreiben:** einen Satz unverändert neu aufbauen und mit
  dem Original vergleichen. Nicht Byte für Byte gleich heißt Deutung falsch, also
  nicht schreiben.
- **`Zone2` ist keine zweite Zone**, sondern der angrenzende unbeheizte Bereich;
  `Zone2Bez` trägt den Fx-Wert als Text und `REDFAKTOR` dieselbe Zahl.
- **Satzgrenzen nie raten.** Eine Suche nach dem Muster, irgendwo stehe schon der
  gesuchte Wert, trifft Zufallstreffer — in `TableZusatz` sechs Bytes hinter dem
  echten Satzanfang.
