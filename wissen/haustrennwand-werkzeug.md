---
name: haustrennwand-werkzeug
description: "Set-Haustrennwand.ps1: Haustrennwand (DHH/Reihenhaus) in einem Aufruf — vier Felder im Rechenmodell + optional Nebengebäude; Probelauf-erprobt 14./15.10.2026, Echtlauf steht aus"
metadata:
  node_type: memory
  type: project
  originSessionId: 69b0e1ac-3e3b-4456-bef5-11d083ab08da
  modified: 2026-10-14T22:21:20.538Z
---

`bauteile/tools/Set-Haustrennwand.ps1` stellt eine Zeichnungswand auf „Wand gegen
beheizt": **vier Felder** an den Repo-1-Elementen (`AdjacentType` 1,
`CladdingSurface` 0, `FxElementType` 19, `MetaDesc`-Property-Cache) — die
Software zieht fehlende Felder sonst erst beim nächsten Öffnen/Schließen-Zyklus
nach, und Spiegel/Rechenlauf/iSFP warten solange. Aufruf: `-Projekt <GUID>`
(Namensteil geht, aber Krause-artige Präfix-Namen sind nie eindeutig),
`-Wand 'AW 004'` oder `-Richtung W` (über `BmElement.Orientation`, ±45°-Fenster;
bei gedrehten Gebäuden `-Wand` nehmen), `-MitNebengebaeude` (Grafik über
Set-Nebengebaeude, Anker = Wand des untersten Geschosses, ein Attachment deckt
alle Geschosse), `-Zuruecknehmen`, `-Probelauf`.

Schutzlogik: stellt vorwärts nur AdjacentType 3 (bzw. 1 als halben Vorlauf) um —
Erdreich-/unbeheizt-Wände im Richtungsfenster werden benannt übersprungen;
Innenwände erkennt es am wall_type der Zeichnung; Flächen ohne
EnergyConsulting-Zeile = benannter Abbruch („Projekt einmal öffnen/schließen");
fremde Anbauten im BmMedia-Blob = Abbruch statt Ersetzen (Set-Nebengebaeude
schreibt stur count=1!).

Mapping Zeichnung→Modell: `BmElement.RepositoryElementUUID` → Repo-3-Wand-UUID,
1:n (Teilung je Raum ODER je Geschoss), Namensmatch auf `NULLIF(ShortDesc,'')`
UND `LongDesc`. Details: `.claude/skills/hottcad-modell/references/datenmodell.md`.

**Why:** Die Zwei-Felder-Umstellung (Einmalskript 14.10.) war unvollständig —
fx=19 kam erst mit der Projektschließung, und solche Nachläufe verrät kein
StampEdit. Wer nur zwei Felder setzt, hat einen Spiegel, der „Wand gegen außen"
zeigt, bis der Berater zufällig öffnet und schließt.

**How to apply:** Immer erst `-Probelauf` (läuft auch bei offener Software, nur
Warnung). Erprobungsstand: 13 Review-Befunde eingearbeitet, Abschlussprobe an
Krause + 260929-Kopie grün — **Echtlauf und H_T'-Wirkungsprobe stehen aus**.
Vier Dateien im bauteile-Repo uncommitted (Set-Haustrennwand neu;
Set-Nebengebaeude, Get-Wandsilhouette: GUID-Zweig; Test-SoftwareLaeuft:
Energieberater-Prozessname). [[krause-3qhtk-neubau]]
