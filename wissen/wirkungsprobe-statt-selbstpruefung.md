---
name: wirkungsprobe-statt-selbstpruefung
description: "Ein Schreibvorgang gilt erst als erfolgreich, wenn sich die Größe bewegt hat, die er bewegen sollte — nicht wenn er sich zurücklesen lässt"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 49e4b8c1-37be-419d-98a1-aa61b55d2177
  modified: 2026-08-13T11:29:40.707Z
---

**Regel: nach jeder Änderung die WIRKUNG messen, nicht die Rückschreibbarkeit.**
Bei Bauteilen `UA` (`ibp-bauteile.exe`), bei Anlagentechnik die Endenergie. Bewegt
sich die Größe nicht, ist die Änderung nicht angekommen — auch wenn jede andere
Prüfung grün ist.

**Why:** Am 13.08.2026 lief ein kompletter Sanierungsfahrplan durch alle Prüfungen
und war trotzdem falsch. `SANK_ZAHL` in `TableHuellfl` ist der **angezeigte** U-Wert;
gerechnet wird aus `Kernel18599V5` → `Construction.fU` / `Window.fU`, und der Blob
wird beim Anlegen einer Variante unverändert mitkopiert. Die Software gleicht beides
ab — **aber erst beim Öffnen der Variante**. Nicht geöffnete Varianten rechneten mit
Ist-Werten. Die Nutzenergie sank um 6 % statt um ein Drittel.

Alle bestehenden Prüfungen waren **Selbstprüfungen**: byte-identische Rückschreibprobe,
Satzzahl gegen Kopf, Rundlauf lesen→schreiben über 84 Projekte. Sie beantworten
ausschließlich „steht da, was ich geschrieben habe" — nie „erreicht es die Stelle, die
rechnet". Dieselbe Ursache hatten die Vorlauftemperatur, die Wärmepumpen-Senke und
die fehlende Warmwasser-Verteilung ([[ibp-bauart-felder]]).

**Die Anlagentechnik hat ihre eigene Wirkungsprobe:** `zeige-heizung.ps1`
(neu am 26.09.2026, an vier Containern geprüft). `pruefe-variante.ps1` misst `UA`
und sieht eine Wärmepumpe deshalb **nicht** — sie ändert keinen U-Wert. Gemessen
wird die Endenergie aus `TableHeizung`, und **kein Satz heißt nicht gerechnet**:
der Blob wird beim Anlegen einer Variante mitkopiert, jede Variante führt also
meist ein Modell. Erst der Satz belegt, dass die Software darauf gerechnet hat.
Den Blob löst `hole-kernel.ps1` heraus. Ablauf: Skill `hottgenroth-heizung`.

**How to apply:** `werkzeuge/bdexit/pruefe-variante.ps1` prüft Vollständigkeit,
Querprobe (Bauteilliste **gegen** Rechenmodell) und Wirkungsprobe (sinkt `UA` entlang
des Fahrplans monoton). Läuft in `pruefe-werkzeuge.ps1` mit. Die Querprobe findet nur,
was ich schon kenne; die **Wirkungsprobe findet auch Fehler an Stellen, die noch
niemand entdeckt hat** — deshalb ist sie die wichtigere.

Meldet die Wirkungsprobe eine auffällig kleine Wirkung, ist die erste Frage nicht
„was ist am Werkzeug kaputt", sondern **„trägt der Ist-Zustand echte Bauteile?"**
Ein HottCAD-Import mit Platzhaltern (alle Außenwände exakt 0,240) kommt über −19,5 %
nicht hinaus; ein Projekt mit echter Aufnahme erreicht −74 %.

Gehört zu [[funktionen-wiederverwendbar]].

**Und die Probe darf nicht die Annahme des Fehlers teilen.** Am 24.08.2026
habe ich eine Kubatur über SQL geprüft: 16 Wände, 4 Geschosse, Dachpolygon —
alles stimmig. In der Software war das Erdgeschoss leer und kein Dach da. Die
Abfrage verglich `floor=` gegen `BmFloor.UUID`, also gegen genau die falsche
Referenz, aus der der Fehler stammte. `Show-Projekt.ps1` hatte zweimal
„(leer)" gemeldet; ich habe es mit der eigenen Abfrage wegerklärt.

Die Regel daraus: **prüfen, was der Verbraucher liest, nicht was der Erzeuger
geschrieben hat.** Und bei Geometrie heißt Wirkungsprobe: IFC-Export und
hinsehen — nicht Zeilen zählen.
