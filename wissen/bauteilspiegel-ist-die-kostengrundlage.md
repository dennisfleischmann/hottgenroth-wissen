---
name: bauteilspiegel-ist-die-kostengrundlage
description: "Die Bauteilliste fürs Kostentool kommt aus dem Server-Spiegel hottgenroth_bauteil_flaechen — er trägt Kennung, Bruttofläche und Hüllen-Flag bereits"
metadata: 
  node_type: memory
  type: project
  originSessionId: b8deec60-f5ed-4083-9896-980684ff4300
  modified: 2026-09-13T19:05:31.855Z
---

Für einen Kostenbericht kommt die Bauteilliste aus dem **Spiegel auf dem Server**
(`hottgenroth_bauteile` / `hottgenroth_bauteil_flaechen`), nicht aus einem neuen
Auslesen des Containers und nicht aus einer hochgeladenen Excel-Datei.

Der Spiegel trägt alles Nötige:

| | |
|---|---|
| Kennung | `HottgenrothBauteil::KOSTENTOOL_CODES` bildet `group_type/usage_type` auf `AW`, `OG`, `BK` … ab |
| Menge | `flaeche_m2` **und** `brutto_m2` |
| Hülle | `huelle` je Fläche |
| dazu | `u_wert`, `orientierung`, `neigung`, `teilflaeche` |

Abrufbar über `/admin/hottgenroth/bauteile/…` mit der Schaltfläche
**„Bauteile abrufen"**; gefüllt wird er von `HottgenrothBauteilSync` über die
vorhandene Auftragskette (`bauteile.export`, vier lesende `sql.query`-Schritte —
am Agenten ist dafür nichts zu ändern).

**Why:** Ich hatte am 13.09.2026 den Weg über `TableHuellfl` im Container
empfohlen, mit der Begründung, dem Spiegel fehlten Kennung und Bruttofläche.
Das war falsch — beides steht dort seit dem 15.08.2026, und der Kommentar über
`KOSTENTOOL_CODES` sagt wörtlich, dass die Tabelle genau diese Lücke schließt.
Dennis hat widersprochen und auf die laufende Kachelansicht verwiesen, in der
Kennung, Fläche und U-Wert zu sehen sind.

**How to apply:** Vor einer Architekturempfehlung das **laufende System**
ansehen, nicht nur die Modelle — eine Seite, die es schon gibt, beweist mehr als
ein Schemaauszug. Und wenn Dennis einer Empfehlung widerspricht, zuerst prüfen,
ob seine Beobachtung sie widerlegt, statt sie zu verteidigen.

Was der Spiegel **nicht** trägt: vorhandene Sanierungsmaßnahmen
(`SANBEZ`, `SANKOSTENQM`). Wer die braucht, kommt an
[[energieberater-sanierungsvarianten]] nicht vorbei — aber für einen
Kostenbericht aus dem Ist-Zustand braucht man sie nicht.

Vor jeder Kostenrechnung gilt [[bmelement-huellflaeche-flag]]: nur Flächen mit
gesetztem Hüllen-Flag zählen. Die Zuordnung selbst steht in
[[kostentool-zuordnung-admin]].
