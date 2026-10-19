# Dächer in HottCAD von außen anlegen

Gemessen an *Test0001*, *Pohlstraße 133*, *Werner Grotz* und *Jan Malte
Strackerjan*, ausgezählt über alle **53 gezeichneten Dachflächen** der Datenbank.
Zwei Wirkungsproben in der Software sind bestanden: ein L-Pultdach und ein
L-Satteldach aus vier Flächen.

Grundlage ist der Befund aus [`hottcad-grundriss-schreiben.md`](hottcad-grundriss-schreiben.md):
**HottCAD liest die Zeichnung aus `BmData.ClassValue` und behandelt sie als
Quelle.** Für Dächer gilt das genauso.

---

## 1. Ein Dach trägt zwei verschiedene Polygone

Das ist der Kern, und das Übersehen dieser Unterscheidung war der einzige
echte Fehlschlag: HottCAD zeichnete die Steigung, aber **keine Fläche**.

| | was es ist | Dimension |
|---|---|---|
| `<roof><points>` | **Der Dachumriss** — die eigentliche Dachfläche | 3D, jeder Punkt mit eigenem z |
| `<plane_definition><points>` | Das Markierungsrechteck an der Traufe | 2D, immer auf `z = 0` |

Das Markierungsrechteck legt nur fest, **wo** die Ebene beginnt und **wohin**
sie steigt. Es begrenzt die Dachfläche nicht — beim gemessenen Beispiel war es
5,3 × 2,0 m, während die Dachfläche 87,99 m² betrug.

Der Dachumriss dagegen ist Pflicht. Ausgezählt:

| Punkte im Umriss | Dächer | bedeutet |
|---|---|---|
| 4 | 18 | Rechteckfläche |
| **6** | **17** | L-Form oder abgeknickte Fläche |
| 0 | 3 | Zwischenstand bei geöffneter Software |
| 3 / 5 | je 1 | Dreieck, Fünfeck |

---

## 2. Die Höhenformel

```
z = ElevationOfRefHeight(Geschoss) + Höhe1 + tan(Neigung) · Abstand von der Traufkante
```

Nachgerechnet an *Dach 001* von Strackerjan: Traufe bei y = 12,6086 auf
z = 3,6 (Geschoss 3,1 + Höhe1 0,5). Der Punkt 2,068 m bergauf steht auf
3,6 + 2,068 · tan 50° = **6,064** — exakt der Wert in der Datei.

> **Achtung:** Der Dachumriss steht in **absoluten** z-Werten, das
> Markierungsrechteck dagegen immer auf `z = 0`. Wer beide gleich behandelt,
> bekommt ein Dach im Boden.

---

## 3. Das Element

```xml
<roof name="Dach 001" GUID="…" floor="…"
      u_value="0.51" u_valueDimGuid="…" u_valueDimName="Sparrendach 10 cm Dämmung"
      u_value_marker="AD_25_0"
      type="Polygonal" thickness="0.25" partitial="False"
      gable_mode="Automatic" gable_mode2="Automatic">
  <points count="4"> … Dachumriss, 3D … </points>
  <repositories count="1"><val>BmElement-UUID</val></repositories>
  <intersections count="0" />
  <plane_definition type="Height1AndSlope" visible="True">
    <values count="2"><val>Höhe1</val><val>Neigung im Bogenmaß</val></values>
    <points count="4"> … Markierungsrechteck, z=0 … </points>
  </plane_definition>
</roof>
```

Die Neigung steht im **Bogenmaß**: 0,785398 = 45°, 0,872665 = 50°.
Die `GUID` ist eine CAD-interne Kennung, **nicht** die `BmElement`-UUID.

Vorkommende Werte, ausgezählt:

| Merkmal | Werte |
|---|---|
| `type` | `Polygonal` (40), `Flat` (8), `HippedRoof` (2), `Assistant` (2) |
| `partitial` | `False` — in allen 52 Fällen |
| `gable_mode` | `Automatic` (37), `OrthogonalToPlane` (15) |
| `plane_definition type` | `Height1AndSlope` |

---

## 4. Fünf Zeilen, wie bei einer Wand

| Tabelle | Besonderheit |
|---|---|
| `BmElement` | **`ElementType 5`** (Wand ist 1), `RepositoryType 3`, `Slope` in **Grad** |
| `BmElementRoof` | nur `RoofSlope` trägt einen Wert |
| `BmElementDimensioning` | — |
| `BmElementEnergyConsulting` | — |
| `BmData` | die Zeichnung; Schlüssel ist (`ReferenceUUID`, `UUID`) |

`RoofType` steht bei **allen 450** Zeilen auf 0. `RidgeHeight`, `RoofArea`,
`H1`, `H2`, `S1`, `S2` und `Overhang` stehen auch bei einem in der Oberfläche
gezeichneten Dach auf dem Sentinel `-987654321,99` — die Software rechnet sie.

---

## 5. Was HottCAD selbst rechnet

**Nicht mitschreiben.** Es wird beim Öffnen überschrieben:

- `<intersections>` — **in allen 53 Fällen leer**, auch bei fertigen
  Satteldächern. First, Kehle und Grat findet die Software dort, wo sich die
  Ebenen schneiden.
- `<segments>` (47 von 52) und `<side_types>` (37 von 52) — Verweise auf Räume
  und je ein Eintrag pro Umrisskante.
- `GrossArea`, `Volume` und die `BmElementRoof`-Kennwerte.
- Boden- und Deckenplatten, sofern `AutoGenerateCeilings="True"`.

---

## 6. Satteldach über einer L-Form

Die Regel, an der es sonst scheitert: **die Schenkel sind verschieden breit.**
Mit derselben Neigung lägen die beiden Firste verschieden hoch. Damit sie sich
treffen, wird **eine** Firstüberhöhung für beide festgelegt:

```
Neigung(Schenkel) = atan( Firstüberhöhung / halbe Schenkelbreite )
```

Erprobtes Beispiel — Riegel 14 × 6 m, Flügel 8 × 10 m, Einbuchtung im Nordosten:

| | Halbspanne | Neigung | Traufe | First |
|---|---|---|---|---|
| Riegel (First Ost-West) | 3,0 m | 45,00° | +5,80 | +8,80 |
| Flügel (First Nord-Süd) | 4,0 m | 36,87° | +5,80 | +8,80 |

Die beiden Firste treffen sich im **Firstknoten**. Von dort laufen zwei Linien,
die man nicht angeben muss — sie entstehen dadurch, dass die vier Umrisse
aneinanderstoßen:

- die **Kehle** zur einspringenden Ecke,
- der **Grat** zur gegenüberliegenden Außenecke.

Beide liegen auf derselben Geraden `Δy = (tan_Flügel / tan_Riegel) · Δx`.

Die **Giebel** liegen an den beiden Schenkelenden. Die Giebeldreiecke der Wände
entstehen von selbst, indem HottCAD die Wände am Dach schneidet.

---

## 7. Werkzeuge

| Skript | Zweck |
|---|---|
| `New-Satteldach.ps1` | **Regelfall.** Ganzes Satteldach aus dem Grundriss — Rechteck (2 Flächen) oder L-Form (4 Flächen) |
| `New-Dach.ps1` | Eine einzelne Fläche: Traufkante, Neigung, Umriss. Für Pult-, Flach- und Sonderfälle |
| `Remove-Bauteile.ps1` | Dächer wieder wegnehmen (`-NamePraefix Dach`) |

```powershell
cd C:\Projekte_Dev\energieberatung\bauteile\tools

# L-Satteldach, Firsthöhe automatisch (45 Grad am schmaleren Schenkel)
.\New-Satteldach.ps1 -Projekt "Test0001" -Geschoss DG -Grundriss `
  "3.36,6.09;17.36,6.09;17.36,12.09;11.36,12.09;11.36,16.09;3.36,16.09" -Probelauf

# Pultdach: eine Fläche, Traufe an einer Seite, Umriss komplett
.\New-Dach.ps1 -Projekt "Test0001" -Geschoss DG -Neigung 15 `
  -Traufe "3.36,6.09,17.36,6.09" -Umriss "…" -Probelauf
```

Die Anstiegsrichtung wird nicht abgefragt: sie ergibt sich senkrecht zur
Traufkante, zum Schwerpunkt der Außenwände hin. Hat das Dachgeschoss keine
Wände, nimmt das Werkzeug das nächste Geschoss darunter und sagt das auch.

**Ein Probelauf verlangt keine geschlossene Software** — er schreibt nichts.
Für den echten Lauf gilt wie überall: `Assert-SoftwareZu` zuerst, danach
`Snapshot-Projekt.ps1` und `Diff-Snapshot.ps1`, und die Wirkungsprobe in HottCAD.

---

## 8. Reihenfolge im Projekt

1. **Geschoss** für das Dach anlegen (`New-Geschoss.ps1`, `-Typ DG`).
2. **Wände** in dieses Geschoss (`Copy-Geschosswaende.ps1`) — ohne sie schwebt
   das Dach über einem offenen Geschoss, und es gibt keine Giebeldreiecke.
3. **Dach** schreiben.
4. Öffnen, ansehen, schließen. Erst danach ist das Modell gerechnet.

---

## 9. Erprobungsstand

| Was | Stand |
|---|---|
| Einzelne Fläche mit Umriss | **in der Software bestätigt** |
| L-Satteldach, 4 Flächen | **in der Software bestätigt** („sieht perfekt aus") |
| Pultdach über L-Form | bestätigt, nachdem der Umriss ergänzt war |
| Rechteck-Satteldach | gerechnet, **noch nicht in der Software gesehen** |

Der Rechteckfall folgt derselben Formel mit einem Schenkel; die Rechnung des
Werkzeugs ist gegen das bestätigte L-Dach geprüft und liefert dort exakt
dieselben sechzehn Punkte.

## 10. Offen

- **`geschossübergreifend`** — das Häkchen im Dialog. Drei Kandidaten geprüft
  und ausgeschlossen: `partitial` ist überall `False`, `RoofType` überall 0,
  kein Attribut nennt „cross", „multi" oder „span". In dieser Datenbank hat es
  offenbar nie jemand gesetzt. **Zum Messen muss einmal eines gebaut werden.**
- **Walmdach** (`HippedRoof`, 2 Vorkommen) und **Assistant** — nicht untersucht.
- **Flachdach**: `type="Flat"` bei 8 Dächern. Ob die Software den Typ selbst
  setzt, wenn man mit Neigung 0 schreibt, ist ungeprüft.
- **Gauben** (`BmElementDormer`, 17 Stück) und **Dachfenster** — nicht untersucht.
- Grundrisse jenseits von Rechteck und L — dort müssen die Flächen einzeln
  über `New-Dach.ps1` gesetzt werden.
