---
name: agent-kann-dateien-holen
description: "Der Hottgenroth-Agent hat eine http.download-Primitive - beliebige Dateien, auch .exe, erreichen den Arbeitsplatz; die .ps1-Positivliste gilt nur für Uploads zum Server"
metadata: 
  node_type: memory
  type: project
  originSessionId: 1f0988c2-fbda-498e-bc4f-0bd047948fdc
  modified: 2026-09-27T22:35:43.889Z
---

Die Frage „wie kommen die `ibp-*.exe` auf einen Arbeitsplatz" war am 27.09.2026 als
offene Entscheidung notiert, mit der Begründung, der Endpunkt erlaube nur `.ps1`.
**Das war eine Verwechslung zweier Richtungen.**

- `McpDateiController::ARTEN` ist eine Positivliste für **Uploads zum Server**
  (`.sqproj`, `.jpg`, `.png`). Sie betrifft, was ein Mensch oder Modell hochladen darf.
- Der Weg **zum Arbeitsplatz** ist eine Auftrags-Primitive:
  `{ "use": "http.download", "with": { "url": "files/…" } }` in
  `hottgenroth-agent/src/HottgenrothAgent/Steps/Primitives/FilePrimitives.cs`. Sie lädt
  über `context.Server.DownloadAsync` — also mit demselben Bearer-Token und ohne
  Endungsprüfung — und gibt `path`, `name`, `size` zurück.

Daneben liegen `file.write` (Skripte ablegen) und `shell.run` (ausführen). Zusammen heißt
das: **ein Auftrag kann sich seine eigene Werkzeugkette mitbringen.** Für ein neues
Werkzeug muss der Agent nicht neu ausgerollt werden, und `hottgenroth-agent/tools/*.ps1`
ist eine Bequemlichkeit, keine Voraussetzung.

**Wofür das den Ausschlag gibt:** die Sanierungsvarianten-Kette braucht genau eine `.exe`
(siehe [[bauteilkette-braucht-eine-exe]]). Die ist damit ausliefertbar, sobald sie unter
dem token-geschützten `files/`-Pfad liegt.

Zu bedenken bleibt: `shell.run` ist Codeausführung auf dem Rechner eines Menschen und
hängt an `AgentOptions.AllowShell`. Wer den Server oder das Token kontrolliert, hat damit
den Arbeitsplatz. Jeder Aufruf wird protokolliert.
