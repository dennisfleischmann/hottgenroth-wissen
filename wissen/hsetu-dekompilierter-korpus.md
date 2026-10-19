---
name: hsetu-dekompilierter-korpus
description: Dekompilierter Quelltext aller HSETU-Installationen unter C:\Projekte_Dev\hsetu-decompiled — mit Schnittstellenindex; liegt bewusst außerhalb des Repos
metadata: 
  node_type: memory
  type: reference
  originSessionId: 49e4b8c1-37be-419d-98a1-aa61b55d2177
  modified: 2026-08-09T03:43:22.515Z
---

Der vollständige dekompilierte Bestand der Hottgenroth-/ETU-Software liegt unter
`C:\Projekte_Dev\hsetu-decompiled` — **außerhalb** des Repos, weil er nicht weitergegeben
und nicht committet werden darf (§69e UrhG deckt nur die eigene Interoperabilität).

Erzeugt am 09.08.2026 mit `ilspycmd` über alle 21 HSETU-Produkte der Maschine
(`C:\Program Files\HSETU`, `…(x86)\HSETU`, `C:\ProgramData\HSETU`). Inhaltsadressiert:
je SHA-256 eine Datei, 3.901 eindeutige Assemblies aus 19.992 Binärdateien.

Einstieg: `API-UEBERSICHT.md` — was die Software kann, nach Aufgaben geordnet.
Danach `README.md` (Aufbau, Suchrezepte).

Suchen statt lesen — die Fachlogik ist 1 GB groß:

```powershell
Import-Csv api-typen.csv     | Where-Object Typ -match 'ProjectImporter'
Import-Csv api-mitglieder.csv | Where-Object Typ -eq 'TFWSQLiteProjectImporter'
Select-String -Path eigen\*.cs -Pattern 'class TModelGEOReferenceHelper'
```

Neu erzeugen: `werkzeuge\dekompiliere-alles.ps1` (wiederaufnehmbar, `-AusInventar` spart
das erneute Hashen) und `werkzeuge\lies-api.ps1` für den Schnittstellenindex.

Nicht dekompilierbar ist der native Teil — vor allem `Energie.exe` (289 MB), in dem die
Oberfläche steckt. Für die Fachlogik spielt das keine Rolle, die liegt vollständig vor.

Verwandt: [[hsetu-bauteilkatalog-api]], [[hottgenroth-bauteil-sql]]
