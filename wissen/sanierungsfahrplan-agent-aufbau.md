---
name: sanierungsfahrplan-agent-aufbau
description: Aufbau des geplanten Anthropic-SDK-Agenten für Sanierungsfahrpläne — vier Schichten, Erprobungsstand je Skill, Tool Runner
metadata:
  type: project
---

Skelett in `energieberatung/sanierungsfahrplan-agent/`: `system.md` (380 Wörter,
nur Invarianten), `skills/` (sechs SKILL.md mit Auslöser + `erprobungsstand:`),
`daten/` (Tabellen direkt aus der Datenbank erzeugt), `tools/` (noch leer).

Die tragende Entscheidung: **die erprobten PowerShell-Skripte werden Werkzeuge,
nicht Promptwissen.** Der Agent bekommt keine Datenbankverbindung — er ruft
`Setup-Wohngebaeude.ps1`, `Test-Wohngebaeude.ps1`, `Snapshot`/`Diff`/`Restore` auf,
jeweils zuerst mit `-Probelauf`. Fläche: Tool Runner
(`client.beta.messages.tool_runner`), Modell `claude-opus-5`, adaptives Denken.
Managed Agents passt nicht: die Anthropic-Sandbox erreicht die LocalDB nicht.

**`erprobungsstand:` je Skill ist Pflichtfeld** — `geschrieben-und-gegengeprueft`
(Zone/Räume), `erprobt` (Varianten, Messen), `teilweise-gemessen`
(Anlagentechnik), `teils-widerlegt` (Bauteile), `unerprobt` (iSFP-Dokument). Bei
den letzten zwei läuft der Agent trocken und gibt zurück.

**Why:** Ein Agent, der Spaltennamen im Prompt trägt und daraus INSERTs baut, ist
die schlechtere Version der Skripte, die schon geprüft sind — und behandelt ohne
das Erprobungsfeld die widerlegte Bauteil-Annahme so zuversichtlich wie den
geprüften Zonen-Ablauf.

**How to apply:** Zwei Hindernisse waren am 18.08.2026 offen — **Python ist auf
dem Arbeitsplatz nicht installiert** (Node v24 und .NET 10 sind im PATH, PHP 8.4
unter `tools/php84` ohne Composer), und es gibt **keine Zugangsdaten** (kein
`ANTHROPIC_API_KEY`, keine `ant`-CLI). Beides klären, bevor Code entsteht.
Gehört zu [[wohngebaeude-einzonenmodell]] und [[raum-zone-raumstempel]].
