---
name: hottgenroth-abruf-diagnose
description: "Spiegel nach refresh_hottgenroth_components unverändert? Fast immer zu früh gelesen oder in Hottgenroth nicht gespeichert; Agent-Konsole per AttachConsole lesbar, wenn kein agent.log da ist"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 4f0538bd-ca70-49d8-9f49-7c802c435628
  modified: 2026-09-15T16:13:02.720Z
---

`refresh_hottgenroth_components` stellt nur einen Auftrag ein. Liest ein Modell
direkt danach `get_hottgenroth_components`, sieht es den **alten** Stand — am
15.09.2026 zweimal hintereinander (Vorgang 112: noch 0 Bauteile, 20 s später
da; Vorgang 113: gelesen um ~16:35:00, abgeholt erst 16:35:12). Der Nutzer hielt
das für einen Bug.

**Der Spiegel ist der gespeicherte Stand, nicht der Bildschirm.** Katalogbauteile
(`TcBasis`) schreibt Hottgenroth sofort; Flächenzuweisungen (`BmElement.
CatalogBasisUUID`/`UValue`) erst beim Speichern des Projekts. `BmElement.StampEdit`
bleibt dabei stehen — am Zeitstempel ist die Zuweisung nicht zu erkennen.

**Nachweisen, ob ein Auftrag lief:** Der Agent druckt jeden Auftrag mit Uhrzeit
und Zeilenzahlen auf die Konsole. `agent.log` gibt es nur mit `--tray`; läuft
er ohne, den Konsolenpuffer lesen: Hilfsprozess mit `FreeConsole` →
`AttachConsole(pid)` → `CONOUT$` → `ReadConsoleOutputCharacterW`, versteckt
starten (sonst verliert die eigene Shell ihre Konsole). Rein lesend.

**Was nicht hilft:** `sys.dm_exec_query_stats` (LocalDB hält kaum Pläne),
`sys.dm_db_index_usage_stats` (bei Auto-Close zurückgesetzt), `fn_dblog`
(einfaches Wiederherstellungsmodell, nach Checkpoint weg).

**How to apply:** Erst fragen, ob in Hottgenroth gespeichert war, dann abrufen,
~30 s warten, dann lesen. „erledigt" am Agenten heißt nur HTTP 200 — scheitert
die Übernahme am Server, steht das nur als Warnung am Auftrag.

**Seit 15.09.2026 (Commit 160e2652) sagt der Spiegel es selbst:**
`stand.letzter_abruf.status` (`wartet_auf_arbeitsplatz` · `wird_gelesen` ·
`uebernommen` · `nicht_uebernommen` · `fehlgeschlagen`, dazu `problem`),
`stand.gelesen_am` und `stand.in_hottgenroth_gespeichert_am`. Zuerst dort
nachsehen, den Konsolen-Trick nur, wenn das nicht reicht. Regeln HA-01/HA-02 in
`docs/regeln/hottgenroth-arbeitsplatz.md`. Gebaut ohne Migration: alles wird aus
Auftrag, Ergebnis und Ereignissen gelesen, die ohnehin gespeichert sind.

Verwandt: [[energie-exe-verwaiste-instanz]] · [[hottgenroth-agent-testaufbau]]
