---
name: nebengebaeude
description: Nebengebaeude an eine Wand haengen und als beheizt oder unbeheizt kennzeichnen - der Nachbar einer Doppelhaushaelfte oder Reihenhauszeile. Ausloeser - Nebengebaeude, Haustrennwand, Doppelhaus, Reihenhaus, angrenzendes Gebaeude, beheizter Nachbar, Umgebung.
erprobungsstand: erprobt
---

**Stand:** An *Test0001* von außen geschrieben und **in der Oberfläche
bestätigt** — HottCAD hat den Block angenommen, ohne ihn umzuschreiben.

Die Umriss-Ableitung ist gegen **zwei** von HottCAD selbst gezeichnete
Silhouetten geprüft:

- *Test0001* (Doppelhaushälfte, Satteldach): fünf von sieben Punkten identisch,
  zwei um 5 mm daneben.
- *82131 Gauting, Am Einfang 10 …Fertig (1)* (L-förmig, zwei Dachflächen, vier
  Geschosse): linke Kante, Unterkante und Firstpunkt identisch, Traufhöhe
  1,2 mm daneben. Rechts läuft die Ableitung weiter als HottCADs Umriss — dort
  hat der Mensch früher aufgehört zu zeichnen, das ist kein Unterschied in der
  Rechnung.

Das zweite Projekt hat vier Fehler zutage gefördert, die am ersten unsichtbar
waren; sie stehen unten unter *Fallen*. **In fremde Projekte geschrieben wurde
noch nicht** — nur gerechnet.

**Werkzeuge:** `bauteile/tools/Set-Nebengebaeude.ps1` und
`bauteile/tools/Get-Wandsilhouette.ps1`.

## Was ein Nebengebäude ist — und was es nicht ist

**Es ist kein Bauteil.** Es entsteht keine Zeile in `BmElement`, es bekommt
keine Angrenzung und keine Hüllfläche. Gemessen an Test0001: das Anlegen änderte
zwar 23 `BmElement`-Zeilen, aber ausschließlich `AddInsOutSideUUID` und
Rundungen im Bereich 10⁻¹⁴. `RepositoryType 1` blieb leer.

Es sagt HottCAD nur, **dass dort ein Nachbar steht und ob der beheizt ist**. Die
eigentliche Angrenzung der Trennwand (`BmElement.AdjacentType = 1`) entsteht
weiterhin erst bei der Übernahme ins Rechenmodell. Das eine ersetzt das andere
nicht — es sind zwei Schritte, und der zweite ist von außen noch nicht erprobt.

## Wo es liegt

**Nicht in den `Bm*`-Tabellen, sondern im `BmMedia`-Blob** — einer eigenen
`building3d`-XML neben der Bauteilzeichnung, UTF-8 ohne BOM mit CRLF:

```xml
<attachments count="1">
  <attachment name="NG 001" GUID="…" drawn_in_wallview="True"
              wall_ref="<CAD-GUID der Wand>" wall_side_index="2"
              type="Heated" parent_wall="<dieselbe GUID>">
    <points count="7"> … </points>
```

`type` ist der Knopf aus der Oberfläche: `Heated` / `Unheated`.
`wall_ref` und `parent_wall` zeigen auf die **CAD-GUID aus der Zeichnung**
(Attribut `GUID` am `<wall>`), nicht auf `BmElement.UUID`. Beide tragen
denselben Wert.

## Vorbedingung: das Projekt muss gezeichnet sein

Ein Nebengebäude hängt an `wall_ref` — der CAD-GUID einer **gezeichneten** Wand.
Projekte ohne HottCAD-Zeichnung haben die nicht, und dann gibt es nichts, woran
es hängen könnte. Prüfen:

```sql
SELECT COUNT(*) FROM BmData d JOIN PrProject p ON p.UUID=d.ProjectUUID
WHERE p.LongDesc LIKE '%<Name>%' AND d.LongDesc='CADXMLData'
```

Steht dort 0, ist das Gebäude über die Bauteilerfassung erfasst worden, nicht
gezeichnet — die Geometrie liegt dann nur als DIN-Bezugsflächen in
`BmElement.GeoDesc`. Gemessen an sechs der sieben Gauting-Varianten.

## Was du vorher brauchst

Zwei Angaben. Fehlt eine, frag nach statt zu raten: **Projekt** und **die Wand**,
an der der Nachbar steht — als CAD-GUID aus der Zeichnung.

Optional: `beheizt`/`unbeheizt` (Vorgabe beheizt), `-AbGeschoss` (Vorgabe: ab
Kellersohle), `-Seite` (Vorgabe 2).

Die Wand-GUID findest du in der Zeichnung des Bauteils:

```powershell
.\Show-Projekt.ps1 -Projekt "<Name>" -MitKoordinaten     # welche Wand ist es?
# dann die GUID aus BmData/CADXMLData der betreffenden Wand holen
```

## Der Regelfall

Ein Aufruf. Den Umriss rechnet das Werkzeug selbst:

```powershell
cd C:\Projekte_Dev\energieberatung\bauteile\tools
.\Set-Nebengebaeude.ps1 -Projekt "Test0001" `
    -Wand "4e5877c2-9a11-49c7-8ccc-0e05a356db7a" -Art beheizt -Probelauf
.\Set-Nebengebaeude.ps1 -Projekt "Test0001" `
    -Wand "4e5877c2-9a11-49c7-8ccc-0e05a356db7a" -Art beheizt
```

Ergebnis an Test0001 — die Doppelhaushälfte von der Kellersohle bis zum First:

```
10.01;6.09;-2.375      Straßenseite, Kellersohle
10.01;16.28;-2.375     Gartenseite   (KG und EG sind 10,19 m tief)
10.01;16.28;3          hoch auf EG-Oberkante
10.01;15.38;3          Sprung 0,90 m zurück (OG springt zurück)
10.01;15.38;5.75       OG-Oberkante
10.01;10.735;8.65      First
10.01;6.09;5.75
```

Weitere Aufrufe: `-Zeigen` listet, was drinsteht (rein lesend, läuft auch bei
offener Software). `-Entfernen` nimmt den Block wieder heraus.

Nur die Silhouette, ohne zu schreiben:

```powershell
.\Get-Wandsilhouette.ps1 -Projekt "Test0001" -Wand "4e5877c2-…" -Ausfuehrlich
```

## Fallen

- **Die Software muss ZU sein, und zwar wirklich.** HottCAD schreibt die
  Umgebung erst beim `DBL:UNLOAD`, also beim Schließen des Projekts — nicht beim
  Speichern. Wer bei laufendem Programm einen Vergleichsstand zieht, sieht die
  Änderung des Menschen nicht und hält sie fälschlich für nicht angekommen.
  Genau das ist mir passiert.
- **Geschrieben wird auf Byte-Ebene**, Latin1-Rundlauf. Der Blob enthält
  Umlaute und hat kein BOM; wer ihn dekodiert und neu kodiert, ändert womöglich
  still Stellen, die niemand angefasst hat.
- **`<surrounding>` ist das Gelände, nicht das Nebengebäude.** Dort habe ich
  zuerst gesucht — vergeblich. Der `<attachments>`-Block sitzt davor, direkt
  nach `</contour_inner>`.
- **`MediaSize` nicht anfassen.** Die Spalte steht auf 0 und ist im ganzen
  Bestand nur in 45 von 277 Zeilen gepflegt; HottCAD führt sie selbst nicht nach.
- **Die zusätzlichen `<layer>` und `<layer_set>`, die beim Zeichnen in der
  Oberfläche entstehen, gehören nicht dazu.** Es ist je ein Satz pro Reiter,
  angelegt beim ersten Anklicken. Die GUID des Nebengebäudes kommt im ganzen
  Blob genau einmal vor — im `<attachment>` selbst.
- **`wall floor="…"` zeigt NICHT auf `BmFloor.UUID`,** sondern auf die GUID der
  Geschosszeichnung (`<floor GUID="…">`, über `ReferenceUUID` am Geschoss).
  Nur in Projekten, die unsere Skripte gebaut haben, sind beide gleich —
  `New-Geschoss.ps1` schreibt dieselbe UUID in beide. In jedem von HottCAD selbst
  angelegten Projekt sind sie verschieden. Wer gegen `BmFloor.UUID` auflöst,
  findet dort **kein einziges** Bauteil und hält das Projekt für kaputt.
- **Nur `RepositoryType = 3` lesen.** Repo 1 ist das gerechnete Modell und hält
  dieselben Bauteile ein zweites Mal, an anderer Stelle. Gauting: 4 Dachflächen
  in Repo 1 gegen 2 in Repo 3.
- **Ein Bauteil hat mehrere `<points>`-Blöcke — nimm nur den ersten.** Eine Wand
  führt neben dem Trapez `<bottom_planes>`, ein Dach neben dem Umriss das
  Traufrechteck in `<plane_definition>`, flach auf z = 0 und in x/y ganz
  woanders. Wer alle `<p>` als ein Polygon liest, erzeugt Kanten zwischen beiden;
  die kreuzen die Wandebene und liefern Punkte, die es nicht gibt.
- **Die Bodenplattenstärke steht in `building_data.LowestPlatformHeight`,** nicht
  in der `CeilingThickness` des untersten Geschosses. Test0001 hat beide auf
  0,25 und verrät den Unterschied nicht; Gauting 0,10 gegen 0,16.
- **Ein Projekt kann mehrere `BmMedia`-Zeilen führen.** Gauting hält neben der
  Zeichnung ein 3-MB-PNG des eingescannten Kellerplans. Die richtige erkennt man
  am Inhalt (`application="building3d"`), nicht an einer Nummer.
- **Die Breite bestimmen die Wände, nicht das Dach.** Ein Dachüberstand ragt über
  die Flucht hinaus, das Nachbargebäude nicht.
- **Der Keller ist nicht selbstverständlich dabei.** Zeichnet ein Mensch das
  Nebengebäude an eine EG-Wand, beginnt HottCADs Umriss bei der EG-Ebene und
  lässt das Untergeschoss weg. Bei einem Doppelhaus ist die Kellertrennwand
  normalerweise mitgeteilt. Dieses Werkzeug nimmt sie standardmäßig mit;
  `-AbGeschoss EG` stellt das alte Verhalten her.

## Wie du prüfst

**Nicht über den IFC-Export** — ein Nebengebäude ist kein Bauteil und taucht
dort nicht auf. Die Wirkungsprobe geht nur über die Oberfläche:

1. Projekt öffnen, Reiter *Umgebung → Nebengebäude*.
2. Steht der Eintrag in der Liste, mit *beheizt* markiert?
3. Ist die Trennwandseite im 3D rot, und reicht die Fläche bis zur Kellersohle?
4. Meldet die Statusleiste neue Fehler?

Danach Projekt schließen und einen Vergleichsstand ziehen: schreibt HottCAD den
Block um, steht im Vergleich genau, was es geändert hat.

## Grenzen

- **Nur achsparallele Wände.** `Get-Wandsilhouette.ps1` wirft bei schrägen
  Wänden. Die Projektion auf die Wandrichtung ist nicht gebaut — nicht
  gebraucht, damit auch nicht prüfbar.
- **Ein Nebengebäude je Projekt.** Der Block wird als Ganzes geschrieben; ein
  zweites käme mit `count="2"` dazu, das ist nicht gemessen. Bei einem
  Reihenmittelhaus mit zwei Nachbarn also erst in der Oberfläche bauen lassen
  und messen.
- **Nicht untersucht:** `wall_side_index` (Vorgabe 2 stammt aus dem einzigen
  gemessenen Fall), `drawn_in_wallview="False"`, Nebengebäude ohne Bezugswand.
