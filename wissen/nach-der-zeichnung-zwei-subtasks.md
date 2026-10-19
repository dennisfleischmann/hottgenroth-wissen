---
name: nach-der-zeichnung-zwei-subtasks
description: "Steht die HottCAD-Zeichnung, entstehen ohne Nachfrage zwei Subtasks — offene Fragen als Tabelle und der Auftrag für Zonen und Raumstempel"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 362c3451-a7e4-47c0-8bf2-9b304d829d3a
  modified: 2026-08-24T13:02:18.177Z
---

**Sobald die HottCAD-Zeichnung steht** — Geschosse, Außenwände, Dach, Öffnungen,
Nebengebäude, geprüft über einen IFC-Export — entstehen **zwei Subtasks, ohne
dass jemand danach fragt.** Beide gehören
**dennis.fleischmann@fs-energieberater.de**.

### 1. Offene Fragen zur Fertigstellung

Eine `.xlsx` im Plan-Ordner, gebaut wie die Fragentabelle: eine Zeile je Punkt,
Antwort in **einer** gelben Spalte, und zwar als **a/b/c, Ja/Nein oder eine Zahl
in cm** — nie als Freitext. Die Auswahlmöglichkeiten stehen ausformuliert
daneben, Auswahllisten sind hinterlegt. Wo ich einen Vorschlag habe, steht er
dabei; wo eine Zahl fehlen darf, gibt es eine Ausweich-Antwort, damit keine
Zeile liegen bleibt.

Hinein gehört alles, was nach dem Bau noch offen ist: angenommene Werte, die
bestätigt werden müssen, nicht baubare Bauteile, Maße, die keine Unterlage
hergab, und Aufräumarbeiten, die nur in der Oberfläche gehen. Siehe
[[lage-steckbrief-pflicht]] für dieselbe Form.

### 2. Zonen und Raumstempel

Der nächste Arbeitsschritt und der einzige, den die Zeichnung nicht selbst
hergibt. **Räume entstehen erst, wenn das Projekt einmal in HottCAD offen war** —
die Polygone und die Verweise auf die umschließenden Bauteile rechnet die
Software aus der Zeichnung. Vorher greift kein Werkzeug: `Setup-Wohngebaeude.ps1`
bricht ohne Räume ausdrücklich ab, statt etwas Halbes zu bauen.

Die Subtask nennt deshalb die Reihenfolge — erst öffnen, dann Zonen und
Raumstempel — und was schon feststeht: das Nutzungsprofil, welche Räume beheizt
sind, und dass ein Wohngebäude als **Einzonenmodell** gerechnet wird. Siehe
[[wohngebaeude-einzonenmodell]] und [[raum-zone-raumstempel]].

**Beides wird abgehakt, sobald es erledigt ist** — siehe
[[asana-erledigtes-abhaken]]. Die Fragentabelle hakt der ab, der sie ausfüllt.
