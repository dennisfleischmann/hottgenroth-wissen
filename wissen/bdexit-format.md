---
name: bdexit-format
description: "Das .BDExit-Format des Energieberaters ist entschlüsselt: Anwesenheitskarte je Satz, und Typ ist immer eine Bytezahl — bei Texten die Breite des Längenfelds"
metadata:
  node_type: memory
  type: reference
  originSessionId: 49e4b8c1-37be-419d-98a1-aa61b55d2177
  modified: 2026-08-11T09:02:15.948Z
---

Das Format der neun Tabellen in `eberater.zip` ([[energieberater-sanierungsvarianten]])
ist selbstbeschreibend und vollständig gelesen. Zwei Regeln tragen alles:

**1. Jeder Satz beginnt mit einer Anwesenheitskarte.**
Länge `ceil(Feldzahl * 2 / 8) + 1`. Das **erste Byte gehört nicht zu den Feldern**;
Feld *i* liegt danach in Byte `1 + floor(i/4)`, Schiebung `(i % 4) * 2`.
**Bitwert 1 = Feld fehlt.** Fehlende Felder belegen kein Byte — daher sind Sätze
variabel lang und jede Bauteilart hat ihr eigenes Satzbild.

**2. `Typ` ist immer eine Bytezahl.**
Bei Code 73/75 (0x49/0x4B) ist es die Breite des **Längenfelds** vor dem Text:
`1/73` = 1 Byte, `2/73` = 2 Byte, `4/75` = 4 Byte (Memo). Sonst die Feldbreite selbst:
`2/1` int16, `4/1` int32, `8/4` double, `2/3` 2 Byte, `4/6` Datum.
Die `WIDTH` aus dem Kopf ist bei Memofeldern ein **Subtyp, kein Bytemaß** —
`Herkunft` hat `WIDTH 2` und trägt 1418 Bytes.

Kopf: Offset 8 = Beginn der Feldtabelle, **Offset 12 uint16 Feldzahl, Offset 14 uint16
Satzzahl**. Hinter der Feldtabelle stehen **immer 2 Bytes** (mal `01 00`, mal `00 00`),
dann optional der Eintrag `AUTOINCVALUE` — beides zählt noch zum Kopf. Feldnamen
dürfen **ein Zeichen** lang sein (`TableZusatz`: `A`, `B`, `B1`).

**Why:** Ohne diese beiden Regeln bleibt nur Raten an festen Offsets, und genau daran
ist jeder Schreibversuch gescheitert — zuletzt an sechs Bytes in `TableZusatz`.

**How to apply:** `hsetu-decompiled/werkzeuge/bdexit/` — `bde.ps1` (Kopf), `satz.ps1`
(`BdeLies` / `BdeSchreib`). **Prüfstein vor jedem Schreiben:** einen Satz unverändert
neu aufbauen und mit dem Original vergleichen. Ist er nicht Byte für Byte gleich,
stimmt die Deutung nicht. Über alle neun Tabellen geht das auf.
