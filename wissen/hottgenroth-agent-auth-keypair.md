---
name: hottgenroth-agent-auth-keypair
description: Hottgenroth-Agent-Auth soll später von Shared-Token auf Pro-Agent-Keypair mit Admin-Freigabe/Revoke umgestellt werden
metadata: 
  node_type: memory
  type: project
  originSessionId: 9f3853ea-5682-42b9-b8dd-1f3502cfb064
  modified: 2026-08-08T11:50:03.208Z
---

Der Hottgenroth-Agent (Verzeichnis `hottgenroth-agent/`, Server-API unter
`api/hottgenroth/agent`) authentifiziert aktuell über ein **gemeinsames Token**
`HOTTGENROTH_AGENT_TOKEN` (Middleware `api.token`) — derselbe Wert für alle
Arbeitsplätze, alles-oder-nichts.

**Gewünschtes Zielmodell (von Dennis, 2026-08-09, bewusst auf später verschoben):**
Jeder Agent erzeugt beim ersten Start ein eigenes **Schlüsselpaar** (privater
Key bleibt lokal), schickt Public Key + `agent_key` an die fs-app → Agent ist
`pending`. Admin **bestätigt** (approve) → Agent signiert seine Requests mit dem
privaten Key statt Bearer-Token. Gültig bis **Revoke** (einzelner Arbeitsplatz
sperrbar, ohne alle anderen neu auszurollen).

Motivation: echte Einzel-Identität + Freigabe + Widerruf statt eines geteilten
Geheimnisses — wichtig, weil der Agent beliebige Bausteine inkl. `shell.run`
ausführt.

Noch nicht umgesetzt. Betrifft: `HottgenrothAgent`-Model (Status pending/approved/
revoked, public_key), Register-/Claim-Flow im `HottgenrothAgentController`, die
Signaturprüfung als Ersatz/Ergänzung zu `EnsureApiToken`, und den Client
(`AgentOptions`/`ServerClient`, Keypair-Erzeugung neben `agent-key.txt`).
Verwandt: [[hottgenroth-bauteil-sql]].
