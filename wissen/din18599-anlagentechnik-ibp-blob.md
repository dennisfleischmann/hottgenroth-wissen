---
name: din18599-anlagentechnik-ibp-blob
description: "Die DIN-18599-Anlagentechnik steht NICHT in SQL, sondern als BinaryFormatter-Blob Kernel18599V5.bin in PrMedia — die Pm*-Tabellen sind leere Hüllen"
metadata: 
  node_type: memory
  type: project
  originSessionId: 49e4b8c1-37be-419d-98a1-aa61b55d2177
  modified: 2026-08-11T23:42:43.938Z
---

Die Anlagentechnik der DIN-18599-Berechnung (Zonen, Heizung, Warmwasser, Kessel,
Speicher, Verteilung) liegt **nicht in den `Pm*`-Tabellen**, sondern als
**.NET-BinaryFormatter-Strom** in `PrMedia.Media`:
`MediaName = 'Kernel18599V5.bin'`, Wurzeltyp
`DIN18599DataModel.P0GeneralModel.DIN18599Building` — der Kern des **Fraunhofer-IBP**.

**Die `Pm*`-Tabellen existieren mit vollem Schema, sind aber leer.** Am 09.08.2026
gemessen: `PmPlant` je Projekt eine Zeile mit lauter Sentinel-Werten; von 8
`PmHeatingBoiler`-Zeilen in der ganzen LocalDB trägt **keine** einen echten Wert.
Belegt sind nur `PmSpace`, `PmSpaceArea`, `PmBuildingReference`.

**Why:** Wer die Anlagentechnik per SQL-INSERT setzen will — wie es für Bauteile
funktioniert ([[hottgenroth-bauteil-sql]]) —, schreibt in Tabellen, die der
Energieberater nicht liest. Das Ergebnis bliebe unsichtbar.

**Der Anhang in `PrMedia` ist aber nur die Kopie** (Nachtrag 12.08.2026). Die Quelle
steht im Energieberater-Container: `eberater.zip` → `TableZusatz`, Feld
**`Kernel18599V5`** — **eine je Variante**, byte-identisch mit dem Anhang. Wer nur den
Anhang schreibt, sieht in der Software **nichts**: sie überschreibt ihn beim nächsten
Öffnen aus dem Satz. Das Feld ist ein `4/75`-Memo ([[bdexit-format]]) und muss als
**Rohbytes** geschrieben werden — CP1252 bildet fünf Bytewerte nicht ab und würde den
Graphen zerstören. Praktische Folge: **jede Variante kann eigene Anlagentechnik
haben** ([[energieberater-sanierungsvarianten]]).

**Zwei getrennte Wege, am 12.08.2026 durch Vorher-Nachher-Vergleich entschieden:** die
Erfassung DIN 18599 schreibt in den Blob und gibt `TableAnlage` nur
Beschreibungstexte (`Beschr_Heiz`); die Felder `…_ALT` / `…_NEU` dort gehören
**ausschließlich** zum vereinfachten Weg nach DIN 4701-10. `TableHeizung` ist
Ergebnis, keine Eingabe.

**How to apply:** Über den Objektgraph gehen, siehe [[din18599-modell-fabriken]].
BinaryFormatter gibt es in .NET 10 nicht mehr — aber **nicht** zwingend über die
Brücke, wie hier lange stand. Der Agent lädt die Brücke in seinen eigenen Prozess
und kommt deshalb nicht heran; die `ibp-*.exe` bringen als .NET Framework 4.8
ihren eigenen Prozess mit. Seit 26.09.2026 ruft der Agent sie per `shell.run`
auf, und damit ist die Anlagentechnik **über MCP** erreichbar
(`get_hottgenroth_heizung` / `set_hottgenroth_heizung`, Skill
`hottgenroth-heizung`). Fallen beim Bauen solcher Aufträge:
[[auftraege-mit-shell-run]].

Ausführlich mit Belegen, Feldzuordnung und Werkzeugen:
`C:\Projekte_Dev\hsetu-decompiled\DIN18599-ANLAGENTECHNIK.md`.
Verwandt: [[hsetu-dekompilierter-korpus]]
