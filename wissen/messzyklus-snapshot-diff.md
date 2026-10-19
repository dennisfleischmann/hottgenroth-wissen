---
name: messzyklus-snapshot-diff
description: "Wie Änderungen am Hottgenroth-Modell gemessen werden — Snapshot, Diff, SQL-Trace, und die Fallen dabei"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: a79f8008-5d86-4c71-9f3c-51871403afa1
  modified: 2026-08-17T20:27:55.044Z
---

Um zu verstehen, was die Software beim Klicken schreibt: `Snapshot-Projekt.ps1`
vor dem Schritt, Schritt in der Software tun, speichern, zweiter Snapshot,
`Diff-Snapshot.ps1`. Beide in `bauteile/tools/`. Der Snapshot packt auch den
ZIP-Blob aus `PrMedia` aus und liest die `.BDExit`-Tabellen feldweise — ohne das
meldet der Vergleich nur „Blob geändert". Für die *Reihenfolge* der Schreibvorgänge
zusätzlich den SQL-Trace (`create-bauteil-trace-v3.sql`); der Snapshot zeigt nur
den Endzustand.

Fünf Fallen, die je einen Messdurchgang gekostet haben:

- **Die Extended-Events-Session überlebt keinen LocalDB-Neustart.** Die Instanz
  fährt nach Leerlauf herunter, die Session bleibt angelegt und läuft nicht mehr.
  `ALTER EVENT SESSION … WITH (STARTUP_STATE = ON)` — im Bauteil-Skript fehlt der
  Schalter.
- **PowerShell 5.1 liest `.ps1` ohne BOM als ANSI**; Umlaute zerlegen den Parser.
  Mit UTF-8-**BOM** speichern.
- **PowerShell entrollt eine `DataTable` beim `return`** in ihre Zeilen,
  `.Rows.Count` ist danach still `0`. `return , $tab` verhindert es.
- **`$pid` ist schreibgeschützt** (Prozess-ID). Als Variablenname liefert es
  überall dieselbe Zahl, ohne dass die Auswertung erkennbar falsch aussieht.
- **`BACKUP … WITH COMPRESSION` geht nicht** — die LocalDB ist Express Edition.

**Why:** Der Zyklus ist der einzige Weg, das Datenmodell zu verstehen, ohne zu
raten — und mehrere dieser Fallen scheitern *still*, liefern also ein plausibles
falsches Ergebnis statt eines Fehlers.

**How to apply:** Vor dem Schreiben immer frisch sichern — eine Sicherung von
vor der letzten Arbeitssitzung des Nutzers ist schlimmer als kein Rückweg.
Danach die Wirkung in der Oberfläche prüfen
([[wirkungsprobe-statt-selbstpruefung]]), und Werkzeuge parametriert bauen statt
als Einmalskript ([[funktionen-wiederverwendbar]]).
