---
name: varianten-sind-schnappschuesse
description: "Eine Variante ist eine Kopie zum Zeitpunkt des Anlegens; danach fließt nichts mehr — der Varianten-Abgleich deckt nur die Bauteiltabelle ab, nicht die Anlagentechnik"
metadata:
  node_type: memory
  type: project
  originSessionId: 4f0538bd-ca70-49d8-9f49-7c802c435628
  modified: 2026-09-12T13:52:53.451Z
---

Die Software sagt es selbst, der Satz steht in ihren Ressourcen:

> *„Beim Anlegen einer Variante werden die aktuellen Erfassungsdaten des
> Ist-Zustands übernommen. Werden diese Daten nachträglich im Ist-Zustand oder in
> der Variante geändert, so kann es zu (gewollten oder ungewollten) Abweichungen
> kommen."*

**Es fließt danach nichts mehr — in keine Richtung.** Wer den Ist-Zustand
korrigiert, hat fünf Varianten, die weiter mit dem alten Gebäude rechnen. Das
sieht man daran, dass ein Maßnahmenpaket **mehr** Endenergie ausweist als der
Ist-Zustand.

**Die HottCAD-Zeichnung ist dagegen geteilt.** `BmRoom`, `BmFloor`, `BmElement`
(Repository 1) existieren **einmal** je Projekt, nicht je Variante — gemessen:
19 Räume, 4 Geschosse, 153 Elemente bei sechs Varianten. Je Variante eigen sind
nur die **abgeleitete Bauteiltabelle** (35 Zeilen) und das **Anlagenmodell**
(`Kernel18599V5`). Eine Geometrieänderung in HottCAD gilt also sofort für alle;
veraltet ist nur das Abgeleitete.

**Der Varianten-Abgleich heißt nicht umsonst „Bauteiltabelle".** Er überträgt
Bauteile und Volumen, **nicht die Anlagentechnik**. Für die gibt es keine
Variante-zu-Variante-Übernahme; die Ist-Übernahme-Knöpfe im Programm gehören zum
vereinfachten Verfahren nach DIN V 4701-10, nicht zu DIN 18599.

**Why — der teure Teil:** Der Haken „Sanierungen in Zielvariante beibehalten"
rettet Maßnahmen an Bauteilen, **die es weiterhin gibt**. Verschwindet das Bauteil,
geht die Maßnahme mit ihm. Am 12.09.2026 kostete das 14 Zeilen und 23.606 € in
MP5: der Keller wurde auf unbeheizt gesetzt, der Abgleich gefahren — damit fielen
Kellerwände, Kellerboden, Kellerfenster und die Hauseingangstür (sie liegt im
Kellergeschoss) aus den Varianten, und ihre Maßnahmen mit ihnen.

**How to apply:** Vor jedem Abgleich die Richtung festlegen und die Hüllfläche
beider Seiten vergleichen (`A_huelle` in `LookupData` je Variante). Laufen sie
auseinander, ist der Abgleich in dem Moment gelaufen, als eine Seite einen anderen
Zuschnitt hatte. Und vorher eine Projektkopie ziehen.
