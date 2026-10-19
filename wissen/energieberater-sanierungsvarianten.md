---
name: energieberater-sanierungsvarianten
description: "Sanierungsvarianten leben in eberater.zip (PrMedia); eine Variante besteht aus je einem Satz in SIEBEN Tabellen — Anlegen und Sanieren von außen sind erprobt"
metadata:
  node_type: memory
  type: project
  originSessionId: 49e4b8c1-37be-419d-98a1-aa61b55d2177
  modified: 2026-08-11T13:12:13.923Z
---

`PrMedia` enthält neben dem IBP-Blob ([[din18599-anlagentechnik-ibp-blob]]) eine
**`eberater.zip`** mit neun BDE-Tabellen (`.BDExit`). Dort — nicht in SQL — liegt die
Variantenlogik. Es gibt **keine aufrufbare Funktion**: `TableHuellfl`, `SANK_ZAHL`,
`VarianteBez` stehen in `Energie.exe` und in keinem der 511 verwalteten Module.

**Eine Variante besteht aus je einem Satz in SIEBEN Tabellen**, nicht aus zweien:
`TableProjekt` (Kopf), `TableHausDat` (**`HAUSFORM`** — Gebäudeart), `TableAnlage`,
`TableAnbauDat`, `TableResult`, `TableZusatz`, dazu `TableHuellfl` mit einem Satz je
Bauteil. **Der Projektbezug heißt nur in `TableHuellfl` und `TableZusatz` `PROJ_ID`** —
sonst ist er schlicht das *erste Feld* (`HAUPTHAUS_ID`, `ANLAGE_ID`, `Result_ID`).

**Why:** Klont man nur `TableProjekt` + `TableHuellfl`, erscheint die Variante zwar,
gilt aber mangels `TableHausDat` als **Nichtwohngebäude — nachträglich nicht mehr
umstellbar**. Und wer nach einer Spalte `PROJ_ID` sucht, hält fünf der sieben
Tabellen fälschlich für unbeteiligt.

**How to apply:** Container aus `PrMedia` holen, Sätze mit `werkzeuge/bdexit/satz.ps1`
feldweise lesen und neu aufbauen ([[bdexit-format]]), Satzzähler bei Offset 14 und die
`AUTOINCVALUE` nachziehen, neu zippen, zurückschreiben. **`Energie.exe` muss
geschlossen sein** — auch eine verwaiste Instanz ohne Fenster überschreibt still.
Fertiges Werkzeug: `werkzeuge/bdexit/variante-bauen.ps1`.

Saniert wird **nicht** durch eine Kopie, sondern durch eine zweite Spalte: `K_ZAHL` ist
der Ist-U-Wert, **`SANK_ZAHL` der nach Sanierung**. Ein Bauteil gilt als saniert,
sobald `SANK_ZAHL` existiert. Bei Bauteilen ohne Sanierung **fehlt das Feld ganz** —
es muss angelegt werden, nicht überschrieben; Anker-Verfahren finden dort still nichts.

**Erprobt und bestätigt am 11.08.2026** am Testprojekt „Werner Grotz": U-Werte gesetzt
(Software rechnet neu, Bewertung EH 85) und eine **vollständige Variante angelegt**
(Wände 0,20 geerbt, 17 Fenster auf 0,95). Keine Signatur, keine Prüfsumme.

**Die SQL-Modellkopie (144 `BmElement` usw.), die die Software beim Anlegen
mitschreibt, wird nicht gebraucht** — die Variante entsteht allein im Container.

**Schrittanleitung und Fehlerquellen: `SANIERUNGSVARIANTEN.md`, Abschnitte 12 und 13.**
Dort steht die Prüfliste — inklusive der stillen Fehler, die keine Meldung erzeugen
(fehlender Satzzähler bei Offset 14, nicht hochgezähltes `AUTOINCVALUE`, überschreiben
eines Felds, das gar nicht existiert). Vor dem Schreiben immer
[[energie-exe-verwaiste-instanz]] beachten.

Doku: `hsetu-decompiled/SANIERUNGSVARIANTEN.md`. Sicherung und Werkzeuge:
`hsetu-decompiled/werkzeuge/bdexit/`.
