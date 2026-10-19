---
name: lokale-testumgebung
description: "PHP liegt unter C:\\Projekte_Dev\\tools\\php84 und ist nicht im PATH; die Suite hat ~47 alte Fehlschläge, die nichts mit neuer Arbeit zu tun haben"
metadata: 
  node_type: memory
  type: project
  originSessionId: 49e4b8c1-37be-419d-98a1-aa61b55d2177
  modified: 2026-08-09T14:59:05.264Z
---

`php` ist auf dieser Maschine **nicht im PATH**. Die Binärdatei liegt unter
`C:\Projekte_Dev\tools\php84\php.exe` (PHP 8.4.24). Für Artisan und Tests:

```bash
export PATH="/c/Projekte_Dev/tools/php84:$PATH"   # Bash-Tool
php artisan test --filter=Hottgenroth
```

Docker ist nicht installiert, lokal läuft SQLite (`database/database.sqlite`).

**Die Suite ist nicht grün, und das war sie vorher schon nicht.** Stand
09.08.2026: 1384 grün, **47 rot**, alle in Skribble, Zoho, Partner/Leistung —
etwa `SkribbleWebhookTest` mit `Undefined property: SendSignedPdfToInbox::$signedPdf`,
weil der Job am 09.05.2026 auf base64 umgestellt und der Test nicht nachgezogen
wurde.

**Why:** Ein voller Lauf sieht nach kaputtem Zustand aus und verleitet dazu, die
eigene Änderung zu verdächtigen oder fremde Tests zu reparieren.

**How to apply:** Nach einer Änderung gezielt den betroffenen Bereich prüfen
(`--filter=…`) und die 47 als Grundrauschen behandeln — aber vorher einmal
gegenprüfen, dass keiner davon den eigenen Bereich berührt.

Verwandt: [[hottgenroth-agent-testaufbau]]
