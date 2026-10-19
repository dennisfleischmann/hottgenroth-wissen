# Grundrisse von außen schreiben

Gemessen an *Test0001* am 18./19.08.2026. Zwei Wirkungsproben in der Software
sind bestanden: eine verschobene Wand und eine neu angelegte Innenwand.

## Der Befund, auf dem alles steht

**HottCAD liest die Zeichnung aus `BmData.ClassValue` (`LongDesc='CADXMLData'`)
und behandelt sie als Quelle, nicht als Abbild.** Beim Speichern kommt sie
zeichengleich zurück, und alles Abgeleitete rechnet die Software selbst nach:
Bodenplatten-Umriss, `building_data`, sämtliche Maße in `BmElement`
(`Width`, `Height`, `GrossArea`, `NetArea`, `Volume`).

Zwei Folgerungen:

- **Abgeleitete Werte nie von Hand pflegen.** Platzhalter genügen, sie werden
  beim nächsten Öffnen überschrieben.
- **Anschlüsse repariert HottCAD nicht.** Gehrungen und die `prev`/`next`-Kette
  müssen beim Schreiben stimmen; die Software zieht sie nicht nach.

Nicht verwechseln: `CADXMLData` ist die **Zeichnung** (`RepositoryType 3`),
`BmElement.GeoDesc` das **gerechnete Gebäude** (`RepositoryType 1`).

## Eine Wand besteht aus fünf Zeilen

| Tabelle | Rolle |
|---|---|
| `BmElement` | Kopf: `ElementType 1`, `RepositoryType 3`, `GId = UUID`, `Id = SeqNum = -1`, `GeneratorType 2` |
| `BmElementWall` | Bauart: `WallType 0`, `WallConstructionType 0` |
| `BmElementDimensioning` | Bemaßung |
| `BmElementEnergyConsulting` | `CladdingSurface` — 1 = thermische Hülle, **0 bei Innenwänden** |
| `BmData` | die Zeichnung; Schlüssel ist das Paar (`ReferenceUUID`, `UUID`) |

`BmData.UUID` ist **nicht** der Zeilenschlüssel, sondern die Kennung der
Datenart — alle `CADXMLData`-Zeilen der Datenbank teilen sie sich. Beim Anlegen
bleibt sie stehen, nur `ReferenceUUID` zeigt auf das neue Bauteil.

Die `GUID` im XML ist eine CAD-interne Wandkennung und **nicht** die
`BmElement`-UUID. Der Verweis auf das Bauteil steht in `<repositories><val>`.

Der sichere Weg zu diesen Zeilen ist die **Kopie einer vorhandenen Wand**
desselben Projekts, Spalte für Spalte, mit gezielten Überschreibungen. Dann
stimmen auch die Spalten, die man nicht kennt, und die Sentinels von selbst.

## Außenwand oder Innenwand

An 376 gezeichneten Wänden ausgezählt:

| | Außen | Innen |
|---|---|---|
| `wall_type` | `OuterContour` (291×), `OuterSingle` (1×) | `Inner` (84×) |
| `outer_wall` | `True` | `False` |
| `prev`/`next` | Pflicht — Ring | **fehlt** |
| `u_valueDimGuid` | vorhanden | **optional**, 43 von 84 ohne |
| `CladdingSurface` | 1 | 0 |

Der Marker trägt die Konstruktion auch ohne `u_valueDimGuid`:
`AW_36_5` = Außenwand 36,5 cm, `IW_24_0` = Innenwand 24,0 cm.

## Gehrung im Rechteck

Für einen rechteckigen Außenring ist die Regel denkbar einfach — jede Wand ist
ein Trapez zwischen zwei Rechtecken:

- `p1`,`p2` liegen auf den **Ecken des äußeren** Rechtecks
- `p3`,`p4` liegen auf den **Ecken des inneren** Rechtecks (außen minus Wandstärke)

Damit entsteht an jeder Ecke von selbst der 45°-Schnitt, den
`wallIntersectionType…="Miter"` erwartet.

Die Kette läuft gegen den Uhrzeigersinn, `next` zeigt jeweils auf die
CAD-`GUID` der folgenden Wand: West → Süd → Ost → Nord → West.

Eine **Innenwand** ist dagegen ein schlichtes Rechteck ohne Gehrung:
`p1 = A + m·t/2`, `p2 = B + m·t/2`, `p3 = B − m·t/2`, `p4 = A − m·t/2`
mit der Mittellinie `A→B` und der rechten Normalen `m = (u_y, −u_x)`.

## `direction`

Der Winkel läuft **gegen den Uhrzeigersinn von +y**:

| Laufrichtung | `direction` |
|---|---|
| +y (Nord) | 0 — wird dann **weggelassen** |
| −x (West) | π/2 |
| −y (Süd) | π |
| +x (Ost) | 3π/2 |

Formel: `direction = atan2(-dx, dy) mod 2π`. Das Attribut ist optional; eine
Wand ohne `direction` ist gültig (AW 003 in Test0001 führt keines, alle
schlanken Innenwände auch nicht).

## Werkzeuge

| Skript | Zweck |
|---|---|
| `Set-Wandversatz.ps1` | eine Wand parallel verschieben — das Messwerkzeug, mit dem der Befund entstand |
| `New-Innenwand.ps1` | Innenwand über Mittellinie, Dicke, U-Wert anlegen |

Vor jedem Schreiben `Assert-SoftwareZu`, danach `Snapshot-Projekt.ps1` +
`Diff-Snapshot.ps1`. Die eigentliche Prüfung ist aber immer das Öffnen in
HottCAD — Zeilen in der Datenbank beweisen nur, dass geschrieben wurde.

## Offen

- **Räume.** Ob `BmRoom` samt Begrenzungsverweisen von außen schreibbar ist,
  ist nicht geprüft. Bisher galt: das rechnet HottCAD aus der Zeichnung.
- **Platten.** `<platform>` ist ein eigenes Element mit eigenen Attributen
  (`against_soil`, `border`, `is_auto_generated`); nur gelesen, nie geschrieben.
- **Fenster und Türen.** Nicht untersucht.
