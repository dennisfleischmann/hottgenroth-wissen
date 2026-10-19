---
name: daecher
description: Daecher in HottCAD von aussen anlegen - Satteldach ueber Rechteck oder L-Form, Pultdach, einzelne Dachflaechen. Ausloeser - Dach zeichnen, Satteldach, Pultdach, Dachneigung, First, Giebel, Kehle, Dachgeschoss aufbauen.
erprobungsstand: geschrieben-und-gegengeprueft
---

**Stand:** An *Test0001* geschrieben und in der Oberfläche bestätigt — ein
L-Pultdach und ein L-Satteldach aus vier Flächen. Die Rechnung von
`New-Satteldach.ps1` ist gegen das bestätigte L-Dach geprüft und liefert exakt
dieselben sechzehn Punkte. **Der Rechteckfall ist gerechnet, aber noch nicht in
der Software gesehen.** In fremde Projekte wurde noch nicht geschrieben.

**Datenmodell:** `bauteile/docs/hottgenroth-daecher.md`.
**Grundlage:** `bauteile/docs/hottcad-grundriss-schreiben.md` — HottCAD liest die
Zeichnung aus `BmData` und rechnet alles Abgeleitete selbst nach.

## Was du vorher brauchst

Vier Angaben. Fehlt eine, frag nach statt zu raten: **Projekt** ·
**Dachgeschoss** (muss existieren) · **Grundriss** als Eckenliste ·
**Dachform** (Sattel, Pult, einzelne Fläche).

Optional, sonst mit Vorgabe: Firsthöhe über der Traufe (automatisch = halbe
Breite des schmaleren Schenkels, also 45° dort), Traufhöhe über der
Geschossebene (`-Hoehe1`, Vorgabe 0), Dachdicke (0,25 m).

## Der Regelfall

```powershell
cd C:\Projekte_Dev\energieberatung\bauteile\tools
.\New-Satteldach.ps1 -Projekt "<Name>" -Geschoss DG -Grundriss "x1,y1;x2,y2;..." -Probelauf
.\New-Satteldach.ps1 -Projekt "<Name>" -Geschoss DG -Grundriss "x1,y1;x2,y2;..."
```

Vier Ecken → 2 Flächen, sechs Ecken → 4 Flächen. Alles andere geht Fläche für
Fläche über `New-Dach.ps1`.

**Vorher gehören Wände ins Dachgeschoss** (`Copy-Geschosswaende.ps1`), sonst
schwebt das Dach über einem offenen Geschoss und es entstehen keine
Giebeldreiecke. Das ist mir schon passiert.

## Fallen

- **Ein Dach hat ZWEI Polygone, und sie sind nicht dasselbe.** `<roof><points>`
  ist der **Dachumriss in 3D** — ohne ihn zeichnet HottCAD die Steigung, aber
  keine Fläche. `<plane_definition><points>` ist nur das Markierungsrechteck an
  der Traufe, flach auf `z = 0`. Genau daran ist mein erster Versuch gescheitert.
- **Der Umriss steht in absoluten z-Werten**, das Markierungsrechteck immer auf
  0. Wer beide gleich behandelt, bekommt ein Dach im Boden.
- **Die Neigung steht im XML im Bogenmaß**, in `BmElement.Slope` dagegen in
  **Grad**. 45° = 0,785398163397448.
- **Bei einer L-Form dürfen die Neigungen nicht gleich sein.** Sonst liegen die
  Firste verschieden hoch. Eine Firstüberhöhung für beide Schenkel festlegen,
  Neigung daraus rechnen: `atan(Überhöhung / halbe Schenkelbreite)`. Das
  Werkzeug macht das.
- **`intersections` leer lassen.** First, Kehle und Grat rechnet HottCAD selbst
  — in allen 53 gemessenen Dächern ist der Block leer, auch bei fertigen
  Satteldächern. Dasselbe gilt für `segments`, `side_types` und alle Flächen-
  und Volumenwerte.
- **`ElementType` ist 5, nicht 1.** Eine Wand ist 1, ein Dach 5.
- **Ein Probelauf braucht keine geschlossene Software** — er schreibt nichts.
  Für den echten Lauf gilt `Assert-SoftwareZu`, und der EE-Berater läuft als
  `EEBerater`, nicht als `Energie`.

## Wenn im Projekt noch kein Dach steht

Die Werkzeuge kopieren ihre Zeilen aus einer vorhandenen Dachfläche desselben
Projekts — so stimmen auch die Spalten, die niemand kennt. Gibt es keine,
**ruf zuerst `vorlagen_zeigen` auf.** Es sagt dir, welche Seitendatenbanken auf
der Maschine liegen und welche Bauteilarten jede führt; danach setzt du
`-VorlageDatenbank` auf eine davon. Den Namen zu raten ist der falsche Weg —
und einfach nichts zu tun auch, solange diese Auskunft einen Aufruf entfernt ist.

Nimm eine Datenbank, die ein Projekt **gleichen Namens** mit der gesuchten
Bauteilart führt. Ein Muster aus einem **fremden** Projekt ist der falsche Weg:
dort hängen Katalogverweise dran, die nicht passen.

## Grenzen

Nicht untersucht: **geschossübergreifende Dächer** (das Häkchen im Dialog — in
der ganzen Datenbank hat es nie jemand gesetzt, es lässt sich also nicht
messen), **Walmdächer**, **Gauben**, **Dachfenster**. Bei
Bedarf: einmal in der Oberfläche bauen lassen, dann messen — so ist alles
andere hier auch entstanden.
