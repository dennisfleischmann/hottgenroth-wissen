---
name: fortrabbit-chunked-rumpf
description: fortrabbit verwirft HTTP-Rumpfe mit Transfer-Encoding chunked und antwortet trotzdem mit 200 — jeder Client muss Content-Length setzen
metadata: 
  node_type: memory
  type: reference
  originSessionId: a986d25c-ab5b-450a-b3ef-f892cbe35bc9
  modified: 2026-08-09T12:59:40.531Z
---

Die Produktion auf fortrabbit reicht Anfragen mit `Transfer-Encoding: chunked`
**mit null Bytes** an PHP weiter — und antwortet trotzdem mit HTTP 200. Gemessen am
09.08.2026 gegen `https://www.fs-energieberater.de`:

```
16 KB mit Content-Length  -> gelesen_bytes=16394   json_lesbar=true    ok
16 KB mit chunked         -> gelesen_bytes=0       json_lesbar=false   HTTP 200
512 KB mit Content-Length -> gelesen_bytes=524298                      ok
```

`post_max_size` steht auf 128 MB, es liegt also nicht an einer Groessengrenze.

**Warum das gefaehrlich ist:** .NET (`HttpClient.PostAsJsonAsync`) serialisiert direkt
in den Netzwerkstrom, kennt die Laenge nicht und schaltet oberhalb seines internen
Puffers — rund 8 KB — auf chunked um. Alles darunter kommt an, alles darueber
verschwindet lautlos. Beim Hottgenroth-Agent gingen so wochenlang alle
Auftragsergebnisse ueber 8 KB verloren; der Server hakte die Auftraege als
"erledigt" ab und speicherte `result = NULL`, weil der Agent sich ueber einen
HTTP-Header ausweist und nicht ueber den Rumpf.

**Regel fuer jeden Client gegen diese Produktion:** vorab in ein Byte-Array
serialisieren und `ByteArrayContent`/`StringContent` verwenden, damit
`Content-Length` feststeht. Nie direkt in den Strom serialisieren.

**Regel fuer den Server:** einen leer angekommenen Rumpf nicht als gueltig
behandeln, wenn die Authentifizierung ueber Header laeuft — sonst sieht ein
verlorener Rumpf wie ein Erfolg aus. In `HottgenrothAgentController::pruefeRumpf()`
umgesetzt.

Messpunkt zum Nachpruefen: `POST /api/hottgenroth/agent/echo` (Agent-Token noetig)
gibt Content-Length, Transfer-Encoding und tatsaechlich gelesene Bytes zurueck.
Siehe [[hottgenroth-agent-testaufbau]].
