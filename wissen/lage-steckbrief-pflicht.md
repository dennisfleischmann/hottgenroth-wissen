---
name: lage-steckbrief-pflicht
description: "Zu jeder Kubatur-Extraktion gehört die Lage-Datei; fehlen Angaben, wird angehalten statt geraten — offene Punkte als Subtask an Dennis"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 362c3451-a7e4-47c0-8bf2-9b304d829d3a
  modified: 2026-08-23T21:37:28.421Z
---

**Die Lage-Datei wird immer zusätzlich erstellt**, zu jeder Kubatur-Extraktion,
ohne Nachfrage. Fünf Spalten, `.xlsx`, in den Plan-Ordner des Auftrags:

| Spalte | |
|---|---|
| Gebäude | Referenz und Adresse **mit Hausnummer**; eine Zeile je Gebäude |
| Haustürfassade zeigt nach | Himmelsrichtung |
| Haustrennwände zeigen nach | leer = freistehend, eine = DHH/REH, zwei = Reihenmitte |
| Im Plan ist unsere Einheit | wenn das Blatt mehrere zeigt |
| Erkennungsmerkmal | die Gegenprobe von außen |

Erzeugt von `sanierungsfahrplan-agent/referenz/lage-steckbrief.php`, hochgeladen
mit `gdrive.sh hochladen`. Siehe [[gdrive-token-ueber-produktion]].

**Reichen die Angaben nicht, wird angehalten.** Nicht geraten, nicht mit einer
Annahme weitergebaut, nicht „vorläufig" ins Modell. Der Lauf endet, und es geht
erst weiter, wenn die offenen Punkte beantwortet sind.

**Die offenen Punkte gehen als Subtask an dennis.fleischmann@fs-energieberater.de.**
Der Modellauftrag selbst — Aufgabe und Subtask — gehört
**hottgenroth-expert@fs-energieberater.de**.

**Warum:** bei angebauter Bebauung ist aus einem Grundriss nicht entscheidbar,
welche Einheit er zeigt und welche Wand adiabat ist. Ein Doppelhausplan bildet
oft beide Hälften ab, gespiegelt. Rät man falsch, spiegelt sich jedes Fenster
oder eine ganze Giebelwand wird ins Freie gerechnet statt adiabat — und **keine
Längen- oder Flächenprobe schlägt dabei an**. Der Fehler fällt erst im
Ergebnis auf, wenn die Arbeit schon gemacht ist. Deshalb hier anhalten und
nicht dort.

Siehe [[projekt-aus-vorlage-importieren]] für den Schritt davor.
