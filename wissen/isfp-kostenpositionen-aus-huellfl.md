---
name: isfp-kostenpositionen-aus-huellfl
description: "einzelPositionen sind Dialogdaten (0 im Rohexport) und dürfen von außen geschrieben werden — Name = KENNZEICHEN - SANBEZ, Invest = Σ SANKOSTEN, Sowieso = Σ SANKOSTEN − Σ SANKOSTEN_EE"
metadata: 
  node_type: memory
  type: reference
  originSessionId: a9df26c4-f679-4aee-bc74-1016fcac6cb2
  modified: 2026-09-27T06:43:16.012Z
---

Die Kostenseite eines iSFP-Pakets lässt sich vollständig aus `TableHuellfl` rechnen,
je Variante, nur Zeilen mit `SANBEZ`:

| Feld in der XML | Rechnung |
|---|---|
| `einzelPositionen/item/name` | `"KENNZEICHEN - SANBEZ"`, z. B. `BK - Kellerdecke von unten 10 cm WLS 035` |
| `investitionsKosten` | Σ `SANKOSTEN` über alle Zeilen **desselben** SANBEZ |
| `sowiesoKosten` | Σ `SANKOSTEN` − Σ `SANKOSTEN_EE` |
| `foerderung` | `min(Invest, Deckel) × Satz` |

Mehrere Bauteilzeilen mit gleichem SANBEZ sind **eine** Position: vier Außenwandzeilen
5425+8175+5425+8175 ergeben die 27.200 €, die von Hand in MP3 standen. Anlagen
(Wärmepumpe, PV, Lüftung) stehen **nicht** in `TableHuellfl` — die kommen aus
`TableAnlage.InvestKostenText` bzw. `anlagenkosten.json`.

**Why:** Anders als die Komponenten ([[isfp-komponenten-kommen-aus-dem-container]])
erzeugt die Maske die Positionen **nicht** aus dem Modell. Im Rohexport direkt nach
„Erfassung zurücksetzen" steht in allen fünf Paketen `einzelPositionen/item = 0`,
während `sanierungskomponenten/item` schon 1 bzw. 2 zählt. Sie sind reine Dialogdaten
— dieselbe Sorte wie die Texte, und die überleben das Schreiben von außen.

**How to apply:** `isfp-fertigstellen.ps1 -Projekt '…'` rechnet und schreibt das.
Stehen schon Positionen drin, bleiben sie stehen; das Werkzeug bildet dann nur die
Summen daraus und meldet Abweichungen gegen den Container. Zwei Fallen:

- **`foerderungMoeglich`** muss auf `true`, sonst zeigt die Fahrplan-Grafik keinen
  Förderbalken, obwohl der Betrag danebensteht.
- Die **Heizungsförderung** ist nicht ableitbar — Klimageschwindigkeits- und
  Einkommensbonus hängen am Fall. Bei Klenke: gerechnet 14.628 €, richtig waren
  12.880 €. Der Satz in `stammdaten.json` ist ein Vorschlag, kein Ergebnis.
