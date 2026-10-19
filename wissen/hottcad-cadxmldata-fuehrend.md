---
name: hottcad-cadxmldata-fuehrend
description: "HottCAD liest die Zeichnung aus BmData/CADXMLData zurück — Geometrie von außen trägt; alles Abgeleitete rechnet es selbst nach, Anschlüsse repariert es nicht"
metadata:
  type: project
---

Am 18.08.2026 an *Test0001* gemessen: eine Wand nur über die Spalte
`BmData.ClassValue` (`LongDesc='CADXMLData'`) um 2 m verschoben, Projekt geöffnet,
angesehen, geschlossen, verglichen. Ergebnis:

**HottCAD liest die Zeichnung aus `CADXMLData` und zeichnet sie.** Die Wand stand
an der neuen Stelle. Beim Speichern kam mein `<points>`-Block **zeichengleich**
zurück — nicht überschrieben, nicht normalisiert.

**Alles Abgeleitete rechnet HottCAD selbst nach.** Aus meiner einen Zeile wurden
beim Schließen:

- `Boden` und `Boden EG` in `CADXMLData`: Umriss von **4 auf 6 Punkte**, folgt der
  versetzten Wand
- `building_data` am `BmBuilding` neu geschrieben
- **alle sechs** `BmElement`-Zeilen: `Height` 10,355 → 12,355, `GrossArea`/`NetArea`
  152,187 → 181,581, `Volume`, dazu Fließkommarauschen in `Width`/`Thickness`

Deshalb: **abgeleitete Werte nie von Hand nachziehen.** Nur die Zeichnung
schreiben, den Rest holt sich die Software beim nächsten Öffnen.

**Anschlüsse repariert es nicht.** Die drei Nachbarwände behielten ihre Gehrungen
zur alten Lage, die Ecken blieben offen. Wer Geometrie schreibt, muss Gehrungen
und die `prev`/`next`-Verkettung selbst richtig rechnen.

Zwei Geometriespeicher nicht verwechseln: `CADXMLData` ist die **Zeichnung**
(`RepositoryType 3`), `BmElement.GeoDesc` das **gerechnete Gebäude**
(`RepositoryType 1`, siehe [[hsetu-geometrie-in-geodesc]]). In Test0001 gibt es
nur die Zeichnung — `GeoDesc` ist bei allen sechs Bauteilen 0 Bytes.

Werkzeug: `bauteile/tools/Set-Wandversatz.ps1` (parametriert, `-Probelauf`,
`-Rueckgaengig`).

**Why:** Das entscheidet, ob Zeichnen von außen überhaupt möglich ist — und die
Antwort ist Ja. Ohne diese Messung wäre offen geblieben, ob die XML nur ein
Abbild der parametrischen Zeilen ist; sie ist das Gegenteil, die Quelle.

**How to apply:** Vor dem Schreiben [[energie-exe-verwaiste-instanz]] prüfen,
danach [[messzyklus-snapshot-diff]] gegen einen Vorher-Stand. Die Wirkung erst
glauben, wenn die Software sie zeigt ([[wirkungsprobe-statt-selbstpruefung]]) —
hier war der Beweis, dass die Bodenplatte der Wand gefolgt ist.
