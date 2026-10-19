---
name: hottgenroth-dachtypen-stand
description: "Welche Dachtypen ich in HottCAD zeichnen kann und welche nicht — laufende Liste, wird beim Dazulernen fortgeschrieben"
metadata:
  type: project
---

Fortlaufende Liste. **Beim Dazulernen hier eintragen**, nicht neu anlegen.
Mechanismus und Fallen: [[hottgenroth-daecher]].

## Kann ich

| Dachtyp | Flächen | Werkzeug | Stand |
|---|---|---|---|
| Satteldach über L-Form | 4 | `New-Satteldach.ps1` | **in der Software bestätigt** |
| Pultdach, beliebiger Umriss | 1 | `New-Dach.ps1` | **bestätigt** |
| Einzelne Fläche, beliebiges Polygon | 1 | `New-Dach.ps1` | **bestätigt** |
| Satteldach über Rechteck | 2 | `New-Satteldach.ps1` | **in der Software bestätigt** (23.08., Test0001) |
| Flachdach | 1 | `New-Dach.ps1 -Neigung 0` | gerechnet, nicht gesehen; offen ob HottCAD auf `type="Flat"` umstellt |


**Bestätigt am 23.08.2026 an Test0001** (Amselweg 8, 6,65 × 9,29 m, 33°):
HottCAD hat die zwei Flächen angenommen, die Giebeldreiecke sind an den
Längswänden entstanden (26 statt 24 Punkte je Wand — die zwei zusätzlichen sind
die Giebelspitze), die Traufwände wurden auf 15 cm heruntergeschnitten. Aus dem
IFC nachgemessen: Traufe 5,75 → First 8,65, Dachfläche 36,42 m² je Seite.

## Kann ich noch nicht

**Rechenbar, nur noch nicht gebaut** — der Mechanismus (N Ebenen aus Traufkante,
Neigung, 3D-Umriss) trägt, es fehlt die Umrissrechnung je Typ:

| Dachtyp | Aufbau | offene Frage |
|---|---|---|
| **Walmdach** | 4 Ebenen: 2 Trapeze + 2 Dreiecke | HottCAD führt `type="HippedRoof"` (2 Vorkommen) — vier `Polygonal`-Ebenen oder etwas anderes? |
| Zeltdach | 4 Dreiecke auf einen Punkt | dieselbe |
| Krüppelwalm | Satteldach mit angeschnittenen Giebeln | — |
| Mansarddach | zwei Neigungen übereinander, obere über `-Hoehe1` | — |
| Sheddach | mehrere Pultdächer nebeneinander | — |

**Mechanismus unbekannt:**

| | warum offen |
|---|---|
| Geschossübergreifende Dächer | Häkchen im Dialog; in **keinem** der 53 Dächer je gesetzt — nur durch ein Exemplar messbar |
| Gauben | `BmElementDormer`, **17 Beispiele vorhanden** — aus dem Bestand messbar, nie angesehen |
| Dachfenster | nicht untersucht |
| ~~Schornsteine~~ | **ausgeklammert** am 23.08.2026 — nicht offen, entschieden. Siehe [[schornsteine-ausgeklammert]] |
| `type="Assistant"` | 2 Vorkommen, Bedeutung unklar |

## `type="Saddleback"` — HottCADs eigenes Satteldach (23.08.2026)

Beim Bauen der Projektvorlage aufgetaucht, **einmal im ganzen Bestand**. HottCAD
zeichnet ein Satteldach als **EIN** Objekt:

- `<roof type="Saddleback">` mit **9 Punkten** im Umriss
- **kein** `<plane_definition>`-Block
- daraus entstehen **zwei** `BmElement`-Zeilen (`… Seite 1`, `… Seite 2`), aber
  nur *Seite 1* traegt eine `CADXMLData`-Zeichnung; *Seite 2* ist abgeleitet
  (Thickness steht auf dem Sentinel -987654321,99)

Unser `New-Satteldach.ps1` schreibt stattdessen **zwei** `Polygonal`-Flaechen,
jede mit eigenem `plane_definition`. Beide Darstellungen funktionieren — die
unsrige ist am 23.08. an Test0001 in der Oberflaeche bestaetigt worden. Es gibt
also zwei Wege zum selben Dach, und wir gehen den handgeschriebenen.

**Wichtig fuer Werkzeuge, die eine Vorlage suchen:** `New-Dach.ps1` verbindet
ueber `JOIN BmData … LongDesc=CADXMLData` und schliesst *Seite 2* damit
richtig aus. Wer ohne diesen JOIN sucht, greift die Zeile ohne Zeichnung.

## Bestandsaufnahme (23.08.2026, 61 Dachflaechen in Repo 3)

| `type` | Anzahl | deckt mein Werkzeug ab? |
|---|---|---|
| `Polygonal` | 44 | ja — Sattel, Pult, Einzelflaeche |
| `Flat` | 8 | gerechnet, nie gesehen |
| `Assistant` | 7 | **nein**, Bedeutung unklar |
| `HippedRoof` | 2 | **nein**, Walmdach |

Ecken des Dachumrisses: 4 → 31 (Rechteck), 6 → 18 (L-Form), dazu je einmal 3, 5
und 9. Beide haeufigen Faelle sind abgedeckt.

**Neun Flaechen stehen auf `count="0"`** — ohne Dachumriss, also ohne Flaeche.
Frueher gemessen waren es 3 von 53. Ob echte Projekte darunter sind oder nur
meine eigenen Fehlversuche, ist ungeprueft.

Nebenbefund: `BmElementDormer` 17 Zeilen (Gauben sind messbar),
`BmElementChimney` 0 (nichts zu messen).

## Ein einmal begonnener, nie abgeschlossener Versuch

Ein **Walmdach** habe ich schon geschrieben — zwei Giebelflächen an ein
vorhandenes Satteldach. Der Nutzer hat gelöscht, bevor er etwas dazu sagte, das
Ergebnis ist also unbekannt. Nach heutigem Stand hat es mit ziemlicher Sicherheit
**nicht** funktioniert: geschrieben mit `<points count="0"/>`, also ohne
Dachumriss — genau der Fehler, an dem später das Pultdach scheiterte.

**Why:** Die Trennung „kann ich / kann ich nicht" ist nur haltbar, wenn
„gerechnet" und „in der Software gesehen" auseinandergehalten werden. Beim
Pultdach war die Rechnung richtig und das Ergebnis trotzdem leer.

**How to apply:** Was der Bestand hergibt (Gauben, Dachfenster), aus der
Datenbank messen. Was es dort nicht gibt (geschossübergreifend), muss der Nutzer
einmal in der Oberfläche bauen — sonst gibt es nichts zu messen.
