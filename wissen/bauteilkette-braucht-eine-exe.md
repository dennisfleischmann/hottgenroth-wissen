---
name: bauteilkette-braucht-eine-exe
description: "Die ganze Bauteil-Sanierungskette ist reines PowerShell bis auf ibp-uwert-setzen.exe - genau ein Programm, nicht die ganze ibp-Suite"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 1f0988c2-fbda-498e-bc4f-0bd047948fdc
  modified: 2026-09-27T22:36:01.018Z
---

Gemessen am 28.09.2026 durch einen `grep` nach `.exe` über alle Skripte in
`C:\Projekte_Dev\hsetu-decompiled\werkzeuge\bdexit\`:

| Skript | fremdes Programm |
|---|---|
| `container.ps1` | keines (nennt `Energie.exe` nur in der Prozessprüfung) |
| `variante-bauen.ps1` | keines |
| `setze-massnahme.ps1` | keines |
| `entferne-bauteilfeld.ps1` | keines |
| `setze-bauteilfeld.ps1` | keines |
| `setze-kernel.ps1` | keines |
| **`uwerte-uebernehmen.ps1`** | **`ibp-uwert-setzen.exe`** |
| `pruefe-variante.ps1` | `ibp-uwert-setzen.exe` (Prüfmodus), `ibp-bauteile.exe` |

**Also: ein Maßnahmenpaket von außen zu bauen braucht genau EIN Programm.** Nicht die
ganze `ibp`-Suite, nicht `DIN18599DataModel.dll` in eigener Hand — nur
`ibp-uwert-setzen.exe`, und die läuft ohnehin nur dort, wo der Energieberater
installiert ist.

`uwerte-uebernehmen.ps1` ist dabei nicht weglassbar: ohne diesen Schritt **zeigt** die
Variante sanierte Werte und **rechnet** mit den alten (siehe
[[sanierungsvarianten-werkzeugkette]]). Der eine Aufruf ist genau der, der die Zahl
bewegt.

Für die Prüfung kommt `ibp-bauteile.exe` dazu. Wer nur schreiben will, braucht sie nicht —
wer belegen will, dass es angekommen ist, schon.

Ausgeliefert wird das über `http.download` ([[agent-kann-dateien-holen]]).
