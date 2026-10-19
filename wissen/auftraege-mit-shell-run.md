---
name: auftraege-mit-shell-run
description: "Zwei Fallen bei Agent-Aufträgen mit shell.run — die Vorgangsdeutung hält ihn immer für schreibend, und file.write löst relative Pfade anders auf als er"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 6673e711-68da-4da1-bfe3-5ffe6a156def
  modified: 2026-09-26T09:19:38.604Z
---

Beide am 26.09.2026 beim Bauen von `heizung.lesen` / `heizung.setzen` gefunden,
beide fallen erst im Betrieb auf.

**1. `shell.run` gilt als schreibend — immer.** `VorgangDeutung::LESEND` führt nur
`agent.diagnose, assert, sql.query, set, sleep, file.read, file.list`; alles
andere ist schreibend. Ein Auftrag, der `shell.run` für **lesende** Arbeit nutzt,
bekommt damit schon im ersten Schritt den Stempel — und `get_vorgang` muss nach
jedem Abbruch `geschrieben: "ungewiss"` melden. Bei einem nicht idempotenten
Auftrag ist das die teuerste aller Antworten.

Der Ausweg steht schon im Schema: **`payload.meta.schreibt_ab`** (1-basierte
Schrittnummer) wird gegenüber der Heuristik bevorzugt. Wer `shell.run` benutzt,
setzt sie **explizit** — am Schrittnamen, nicht am Bausteintyp. Kein Schreiben im
ganzen Auftrag heißt `count($schritte) + 1`.

**2. `file.write` und `shell.run` haben verschiedene Arbeitsverzeichnisse.**
`shell.run` setzt `WorkingDirectory = Options.WorkDirectory`; `file.write` ruft
`File.WriteAllTextAsync` mit dem Pfad, wie er ist — ein relativer löst also gegen
das CWD des Agent-**Prozesses** auf. Die beiden müssen nicht dasselbe sein, und
dann legt der eine Schritt die Datei dorthin, wo der nächste sie nicht findet.

Praktische Regel: **ein Auftrag, ein Weg.** Wer mit relativen Pfaden in
`shell.run` arbeitet, schreibt seine Dateien auch dort. Großen Inhalt dabei als
**Base64** übergeben (`[Convert]::FromBase64String`) — `[A-Za-z0-9+/=]` ist in
einer Kommandozeile injektionsfrei, und die Frage nach dem richtigen Escaping
stellt sich nicht. Nebeneffekt: UTF-8 ohne BOM, was `file.write` nicht kann.

**Why:** Der Agent ist erweiterungsfrei gebaut — ein neuer Auftragstyp ist eine
neue Kombination der Bausteine, kein Rollout ([[din18599-anlagentechnik-ibp-blob]]).
Das gilt aber nur, solange man die Eigenheiten der Bausteine kennt; beide Fallen
hätten einen Auftrag erzeugt, der läuft und trotzdem falsch berichtet.

**How to apply:** Der Ablauf gehört in einen Service auf dem Server (Muster:
`HottgenrothBrueckenImport`, `HottgenrothHeizung`), nie in den Agent. Nichts aus
einem Modell gelangt in einen Befehl: GUID gegen ein Muster, Zahlen als `int`,
Dateinamen gegen eine **Positivliste** statt einer Pfadprüfung, freier Text als
Base64 oder Datei. Geprüft wird das in
`tests/Feature/Ai/McpHottgenrothHeizungTest.php` — dort steht auch die Probe, dass
ein Projektname nie in einer Kommandozeile landet.
