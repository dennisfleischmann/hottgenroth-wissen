---
name: varianteid-verweist-auf-ist-zustand
description: "TableProjekt.VarianteID ist kein Zähler, sondern die PROJEKT_ID des Ist-Zustands; hochgezählt meldet die Software 'Ist-Zustand nicht vorhanden!' und der Variantenwähler bleibt leer"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 1f0988c2-fbda-498e-bc4f-0bd047948fdc
  modified: 2026-09-26T11:14:28.117Z
---

`TableProjekt.VarianteID` **verweist** auf das Projekt, aus dem die Variante
abgeleitet ist — es ist **keine laufende Nummer**. Beim Ist-Zustand fehlt das
Feld ganz.

An zwei Projekten ausgezählt:

| Projekt | PROJEKT_ID | VarianteID |
|---|---|---|
| `20260626_HottCAD_82024` | 2 · 4,5,6,7,8 · 9 | fehlt · **2,2,2,2,2** · 3 |
| `CCKZL_Messinger_260908 (1)` | 2 · 17,18,19,20,21 | fehlt · **2,2,2,2,2** |

Die 3 beim letzten Satz von 82024 ist kein Gegenbeispiel: dort gab es einmal
eine `PROJEKT_ID 3`, sie wurde gelöscht — die Nummernfolge springt deshalb von
2 auf 4.

**Why:** `variante-bauen.ps1` schrieb bis zum 26.09.2026 `max+1`. Die Varianten
erscheinen damit in der Variantenliste **vollständig und richtig eingerückt**,
aber in der Variante meldet die Software **„Ist-Zustand nicht vorhanden!"**, der
Variantenwähler sagt „Noch keine Variante vorhanden!", und der Ist-Balken im
Ergebnisvergleich zeigt eine **fremde Variante** statt des Ist-Zustands. Bei
Klenke zeigte MP1 auf die nicht existierende 1 und MP5 auf MP3 — der
„Ist"-Balken wies 15.777 kWh aus statt 30.547. Keine der drei Prüfungen von
`pruefe-variante.ps1` schlägt an: die Bauteile und das Rechenmodell sind
einwandfrei, nur die Verknüpfung fehlt.

**How to apply:** Die Regel ist `VarianteID der Vorlage, sonst VonProj` — eine
aus dem Ist-Zustand abgeleitete Variante bekommt dessen `PROJEKT_ID`, eine aus
einer Variante abgeleitete erbt deren Wert. So ist `variante-bauen.ps1` seit dem
26.09.2026 gepatcht (Sicherung `variante-bauen.ps1.vor-varianteid-fix`).
Nachträglich geradeziehen:

```powershell
.\setze-feld.ps1 -Ordner .\arbeit -Tabelle TableProjekt `
                 -Feld VarianteID -Wert 2 -Proj 3,4,5,6,7
```

**Die UUID hat damit nichts zu tun.** In 82024 tragen alle Varianten eine
gemeinsame, vom Ist-Zustand verschiedene UUID; in Messinger mischen sich beide
(17 und 21 tragen die des Ist-Zustands, 18–20 eine andere) und es funktioniert
trotzdem. Die UUID der Varianten ist zudem **keine** Zeile in `PrProject`.

Teil der Kette: [[sanierungsvarianten-werkzeugkette]] ·
[[energieberater-sanierungsvarianten]].
