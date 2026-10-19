---
name: export-und-ansicht
description: Modell sichtbar machen - IFC schreiben, Geschossgrundrisse als DXF und PNG, Diagnosebild des Baukoerpers, Flaechenprobe gegen die Datenbank. Ausloeser - IFC, Grundriss, DXF, exportieren, anschauen, wie sieht das Modell aus, ist die Huelle geschlossen, Bildpruefung.
erprobungsstand: erprobt-lesend
---

**Stand:** Erprobt und **rein lesend**. Diese Werkzeuge fassen die Datenbank nicht
an — kein Freigabetor, keine Sicherung, kein Probelauf nötig. Sie sind die einzige
Klasse, die du ohne Rückfrage aufrufen darfst.

**Werkzeuge:** `hottgenroth-agent/tools/` — `Export-Ifc.ps1`,
`Export-Grundriss.ps1`, `Render-Modell.ps1`, `Test-Ifc.ps1`, `Export-Projekt.ps1`
(orchestriert alles und schreibt `manifest.json`).

## Wozu du sie benutzt

**Nicht nur zum Ausliefern — zum Nachsehen.** Eine SQL-Abfrage sagt dir, dass 42
Hüllflächen existieren; sie sagt dir nicht, ob die Hülle *geschlossen* ist. Dafür
rendere das Modell und sieh dir das Bild an. Wenn eine Frage geometrisch ist,
erzeuge ein Bild und schau hin, statt länger nachzudenken.

Typische Anlässe: nach einer Dachplanung prüfen, ob oben etwas offen blieb · vor
einer Zonenzuordnung sehen, welche Geschosse überhaupt bebaut sind · einem
Befund aus dem Vergleich ein Bild zur Seite stellen.

## Zwei Wege zum IFC — sie sind nicht austauschbar

- **`Export-Ifc.ps1`** liest `BmElement.GeoDesc` und schreibt selbst. Läuft
  **ohne die Software**, also auch wenn sie offen ist oder gar nicht startet.
  Genommen wird der Schleifensatz `DIN18599_2011`, dessen Summe die gemeldete
  Bruttofläche trifft.
- **HottCADs eigener Exporter**, ferngesteuert über die Brücke. Braucht die
  Software. Andere Fassung als über die Oberfläche.

Welcher wofür der bessere ist, ist **nicht abschließend geprüft**. Wenn es darauf
ankommt, erzeuge beide und vergleiche, statt einen zu wählen und zu hoffen.

## Flächenprobe

`Test-Ifc.ps1` ist das geometrische Gegenstück zu `pruefe_wohngebaeude`: es liest
die geschriebene Datei **zurück**, rechnet aus den Polygonen die Fläche neu und
hält sie gegen die Datenbank. Zählungen allein hätten die erste, unbrauchbare
Fassung durchgewinkt — deshalb ist die Flächenprobe die Prüfung, auf die es
ankommt. Führ sie nach jedem Export aus und nenn das Ergebnis.

## Grenzen

- **Der Export zeigt den gespeicherten Stand.** Läuft die Software mit
  ungespeicherten Änderungen, exportierst du den Stand davor. Das ist kein Fehler,
  aber sag es dazu.
- **`ifc-web/` ist kein Agentenwerkzeug**, sondern ein Entscheidungsprojekt: vier
  Betrachter im Vergleich, mit Lizenzfolgen (xeokit AGPL-3.0, Autodesk
  kostenpflichtig und in der Cloud). Die Wahl trifft der Mensch. Danach ist der
  Betrachter der Ort, an dem er die Wirkungsprobe macht — biete den Pfad zur Datei
  an, such ihm keinen Betrachter aus.
