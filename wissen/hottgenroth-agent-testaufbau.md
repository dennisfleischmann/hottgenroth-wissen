---
name: hottgenroth-agent-testaufbau
description: Auf FSLAPTOP1 laeuft der Agent aus dist/ gegen die Produktion; Reproduktionen gehen lokal ueber HGA_-Umgebungsvariablen und --once
metadata: 
  node_type: memory
  type: project
  originSessionId: a986d25c-ab5b-450a-b3ef-f892cbe35bc9
  modified: 2026-09-15T05:25:46.353Z
---

Auf FSLAPTOP1 (dem Entwicklungsrechner) gibt es **zwei** Agent-Installationen, und
die falsche zu erwischen kostet Zeit:

- `C:\Projekte_Dev\energieberatung\hottgenroth-agent\dist\hottgenroth-agent.exe` —
  das ist die laufende, aktuelle Fassung. `dist/appsettings.local.json` zeigt auf
  **https://www.fs-energieberater.de**, also die Produktion.
- `%LOCALAPPDATA%\HottgenrothAgent\app\` — veraltet (ohne `hsetu.bridge`), zeigt auf
  ein totes `http://127.0.0.1:8090`, Token passt nicht mehr (401).

Das Arbeitsverzeichnis (downloads/) teilen sich beide: `%LOCALAPPDATA%\HottgenrothAgent\`.
Die heruntergeladenen `.sqproj` liegen dort und lassen sich direkt per SQLite oeffnen —
der schnellste Weg zu der Frage, ob eine Datei ueberhaupt Bauteile enthaelt
(`SELECT COUNT(*) FROM TcBasis WHERE ElementType = 2`).

**Einen Auftrag lokal reproduzieren**, ohne die Produktion anzufassen:

1. Lokalen Server starten: `hottgenroth-agent\lokal-test.ps1` (Port 8090, SQLite,
   portables PHP unter `C:\Projekte_Dev\tools\php84` — systemweit ist keins da).
2. Auftrag in der lokalen DB anlegen (`HottgenrothBauteilSync::auftragFuerBauteile`).
3. Aktuellen Agent einmalig dagegen laufen lassen:
   `$env:HGA_ServerUrl='http://127.0.0.1:8090/api/hottgenroth/agent'`,
   `$env:HGA_Token=<HOTTGENROTH_AGENT_TOKEN aus .env>`, dann `dist\...exe --once`.

Das Token ist app-weit (Middleware `api.token:HOTTGENROTH_AGENT_TOKEN`), nicht pro Agent —
siehe [[hottgenroth-agent-auth-keypair]] fuer die geplante Umstellung.

**Den Agenten selbst testen, ohne Produktion und ohne echte Identität** (seit 2.1.0,
15.09.2026): die mitgelieferte `appsettings.json` zeigt auf **fs-energieberater.de**, also
immer überschreiben — `HGA_ServerUrl` auf eine tote Adresse (`http://127.0.0.1:9/…`),
`HGA_Token` auf irgendwas (verhindert das Browserfenster), **`HGA_WorkDirectory` auf einen
Scratch-Ordner** (sonst schreibt der Test in die geteilte `agent-key.txt` und `agent.log`).
In einen eigenen Ordner bauen (`dotnet build -o …` bzw. `build.ps1 -Ziel …`), nie nach
`dist\`. Gestoppt wird mit `--beenden`, nicht mit Stop-Process. Ein 401-Server lässt sich
mit einem `TcpListener` in einem `Start-Job` nachstellen.

**Warum das wichtig ist:** Ohne diesen Aufbau endet jede Fehlersuche in Bitten an den
Nutzer, in der Oberflaeche nachzusehen. Mit ihm laesst sich derselbe Auftrag mit denselben
Daten in zwei Minuten nachstellen. Siehe [[hottgenroth-bauteil-sql]].
