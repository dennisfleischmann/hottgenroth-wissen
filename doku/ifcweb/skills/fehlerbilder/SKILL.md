---
name: fehlerbilder
description: Woran diese Arbeit schon gescheitert ist und was verlaesslich funktioniert hat. Denkfehler, Messfehler, Sprachfallen - jeweils mit dem Fall, an dem sie auffielen. Ausloeser - etwas funktioniert nicht wie erwartet, ein Befund widerspricht der Doku, eine Aenderung zeigt keine Wirkung, ein Werkzeug bricht unerklaerlich ab.
erprobungsstand: erprobt
---

**Was hier steht, ist passiert.** Jeder Eintrag hat einen Fall mit Datum. Keine
Vorsichtsmaßnahmen aus Prinzip — nur Fehler, die tatsächlich Zeit oder Daten
gekostet haben, und die Vorgehensweisen, die sich bewährt haben.

Lies das, wenn etwas nicht funktioniert wie erwartet. Die Wahrscheinlichkeit
ist hoch, dass es eines dieser fünf Muster ist.

---

## 1. Die Zeilen stimmen — und das Modell ist trotzdem falsch

**Der Fall.** Ein Pultdach geschrieben. Alle Spalten sauber, der Vergleich
zeigte genau die beabsichtigten fünf Zeilen, kein Widerspruch. In HottCAD kam
die Steigung — aber **keine Fläche**. Ursache: der Dachumriss stand auf
`count="0"`.

**Warum es gefährlich ist.** Jede Selbstprüfung war grün. Ein Datenbestand kann
in sich vollständig stimmig sein und trotzdem nichts Sinnvolles ergeben.

**Was folgt.** Zeilen zu zählen beweist, dass geschrieben wurde — nicht, dass es
wirkt. **Die Wirkungsprobe in der Oberfläche ist nicht optional**, und du kannst
sie nicht selbst durchführen. Sag nach jedem Schreibvorgang konkret, worauf der
Mensch schauen soll: nicht „bitte prüfen", sondern „zwei Dachflächen, First
durchgehend auf +7,00, Giebeldreiecke geschlossen".

---

## 2. Bei laufender Software gemessen

**Der Fall.** Genau der Umriss aus Fall 1 wurde gelesen, **während der
EE-Berater lief**. Was dort stand, war ein Zwischenstand — kein Ergebnis. Aus
einem Messfehler wurde eine falsche Regel, aus der Regel ein kaputtes Dach.

**Was folgt.** Ein Wert, der bei geöffneter Software gelesen wurde, ist keine
Messung. Vor jeder Messung, auf die du eine Regel gründen willst:
`software_pruefen`. Der EE-Berater heißt im Prozess **`EEBerater`**, nicht
`Energie` — wer nur auf `Energie` prüft, übersieht ihn. Das ist zweimal
passiert, einmal mit Datenverlust.

---

## 3. Abgeleitetes selbst liefern wollen — der teuerste Denkfehler

**Der Fall.** Jahrelang stand in vier Dokumenten: *„Räume kann kein Skript
anlegen — ein Raum trägt Verweise auf die ihn begrenzenden Bauteile, und die
rechnet HottCAD aus geometrischer Nachbarschaft."*

Der zweite Halbsatz stimmt. Der Schluss ist **falsch herum**. Am 17.08.2026 um
04:01 wurde *Wohnraum 21 / DG2-R1* von außen geschrieben — nur `BmRoom`,
`BmRoomData` und die Zeichnung. Die vierzehn Verweise ergänzte HottCAD um 11:01
beim nächsten Öffnen **selbst**. Die Grenze hatte nie existiert.

**Die Regel dahinter, und sie gilt überall:**

> Was **nicht in der Zeichnung** steht, rechnet HottCAD. Also liefere es nicht.

Belegt an: Plattenumrissen (folgten einer verschobenen Wand), `GrossArea` und
`Volume`, den Dach-`intersections` (in allen 53 Dächern leer), `segments`,
`side_types`, und eben den Raumverweisen.

**Was folgt.** Wenn dich ein Feld zur Frage bringt „muss ich das ausrechnen?",
prüfe zuerst, ob es in einer von HottCAD geschriebenen Zeichnung überhaupt
vorkommt. Steht es dort nicht, ist es ein Ergebnis und keine Eingabe.

---

## 4. Eine Schlussfolgerung als Messung weitergeben

**Der Fall.** Derselbe wie 3, aber die andere Hälfte des Fehlers: Die Aussage
„geht nicht" war nie geprüft worden. Sie war ein **Schluss**, wurde als
Tatsache notiert und wochenlang zitiert — auch dann noch, als der Befund, auf
dem sie beruhte, längst widerlegt war.

**Was folgt.** Trenne beim Sprechen und beim Aufschreiben:

| | |
|---|---|
| **gemessen** | am Bestand ausgezählt oder in der Software gesehen |
| **gerechnet** | folgt aus einer Regel, nie ausprobiert |
| **geschlossen** | vermutet, weil etwas anderes so war |

Nur das Erste trägt. Das Dritte veraltet still, sobald sich eine Prämisse
ändert — und niemand merkt es, weil es wie eine Tatsache klingt. Wenn du eine
Grenze nennst, sag dazu, ob sie gemessen oder geschlossen ist.

---

## 5. Zu eng geprüft

**Der Fall.** „Energie.exe ist zu, schreiben ist gefahrlos" — zweimal gesagt.
Der EE-Berater lief die ganze Zeit unter anderem Prozessnamen. Ähnlich: eine
Abfrage prüfte `GeoDesc IS NULL` und meldete „gefüllt", obwohl das Feld ein
**leerer String** war.

**Was folgt.** Zähle aus, statt anzunehmen. Enumerationswerte, Prozessnamen,
Attributnamen: `GROUP BY` über den ganzen Bestand liefert die Wahrheit in
Sekunden. So sind alle belastbaren Regeln hier entstanden — `wall_type` hat
drei Werte, `u_valueDimGuid` fehlt bei 43 von 84 Innenwänden, `FloorCount`
zählt nur OG und DG.

---

## 6. Ein Werkzeug mit blindem Fleck sagt „gibt es nicht" statt „weiß ich nicht"

**Der Fall.** Die Korpussuche durchsuchte nur die *eigenen* Register und für den
Volltext nur `eigen/`. `fremd/` war als „556 MB DevExpress" abgetan. Dort liegt
aber `DIN18599DataModel` — das IBP-Modell, also das wichtigste Fremdmodul dieser
Arbeit.

Eine Suche nach `NewGeneratorBoiler` lieferte **null Treffer**. Der Schluss
daraus: „die Methode existiert nicht". Tatsächlich steht sie da, mit genau der
Signatur, die im Gedächtnis beschrieben ist:
`public P58HeatGeneratorBoilerComponent NewGeneratorBoiler(string pID, string pName)`.

**Was folgt.** Ein Werkzeug, das an der falschen Stelle sucht, meldet nicht
„weiß ich nicht", sondern „gibt es nicht" — und das ist die gefährlichere
Antwort, weil sie nach einem Ergebnis klingt. **Bevor du aus einem leeren
Suchergebnis etwas schließt, prüfe, wo überhaupt gesucht wurde.**

---

## 7. Nach der Überschrift geurteilt

**Der Fall.** Derselbe. Auf die leere Suche hin wurde ein Gedächtniseintrag
angezweifelt — von jemandem, der nur dessen **Indexzeile** gelesen hatte. Der
Eintrag selbst nennt Daten (09.08., 12.08.), Messwerte (Restabweichung 0,07 %,
78.854 statt 50.836 kWh), Werkzeuge und Quellen. Er war von Anfang an belegt.

Im Systemprompt steht wörtlich: *„Eine Kurzzeile ist ein Hinweis, keine
Auskunft."* Der Satz stammt von demselben, der ihn dann übergangen hat.

**Was folgt.** Bevor du eine bestehende Aussage anzweifelst, **lies sie ganz**.
`wissen_lesen` kostet einen Aufruf. Ein zu Unrecht angezweifelter Eintrag kostet
das Vertrauen in den ganzen Bestand — und im schlimmsten Fall wird er
„berichtigt", also kaputtgemacht.

---

## Was verlässlich funktioniert hat

**Zeilen kopieren statt zusammensetzen.** Ein neues Bauteil entsteht als
Spalte-für-Spalte-Kopie eines vorhandenen **desselben Projekts**. Dann stimmen
auch die Spalten, die niemand namentlich kennt, und die Sentinels von selbst.
Ein Muster aus einem fremden Projekt zieht Katalogverweise mit, die nicht
passen — das ist kein Formalismus, sondern der Grund, warum `vorlagen_zeigen`
existiert.

**Probelauf, Vergleich, Wirkungsprobe — in dieser Reihenfolge.** Der Probelauf
hat mehr Fehler gefunden als jede andere Maßnahme: eine Namensverwechslung, ein
Geschoss, das auf einem bestehenden gelandet wäre, eine Formel, die rundete
statt abzuschneiden.

**Anhalten statt raten.** Beim ersten Dachversuch fehlte eine Vorlage. Statt
einen Datenbanknamen zu erfinden, wurde angehalten und gefragt. Das war
richtig — und es hat eine echte Lücke sichtbar gemacht, statt sie zu
überdecken. Eine geschätzte Zahl sieht im Modell aus wie eine gemessene.

**Negative Befunde festhalten.** „HottCAD ist nativ, im dekompilierten Bestand
gibt es dazu nichts" hat mehr Zeit gespart als mancher positive Fund. Wenn eine
Suche ergebnislos bleibt, ist das ein Ergebnis — schreib es auf.

---

## Sprachfallen in PowerShell

Alle vier haben je einen halben Arbeitsgang gekostet:

| Falle | Wirkung |
|---|---|
| **Das Komma bindet stärker als das Plus.** `@($x + $b, $y)` liest die Sprache als `$x + ($b, $y)` | Fehlermeldung über eine fehlende Methode `op_Addition`, die auf die falsche Stelle zeigt |
| **`@( … )` über mehrere Zeilen flacht verschachtelte Arrays ab.** Eine einzelne Kommaliste nicht | aus vier Punkten werden acht Zahlen |
| **`.ps1` ohne BOM wird als ANSI gelesen** | Umlaute zerlegen die Syntax, der Parser zeigt auf eine harmlose Zeile |
| **Groß- und Kleinschreibung ist egal:** `$SW` und `$sw` sind dieselbe Variable | stille Überschreibung |
| **Bei offener Transaktion braucht JEDER Befehl sie** | `ExecuteReader` wirft, obwohl die Abfrage stimmt |

---

## Wenn dir selbst etwas passiert

Trag es hier ein: **was du geglaubt hast, was tatsächlich war, woran es
aufgefallen ist.** Der Denkfehler ist wertvoller als die Einzelheit — die steht
schon im Datenmodell. Und wenn du eine Aussage aus einer dieser Dateien
widerlegst, **streich sie überall**, nicht nur an der Stelle, an der es
auffiel. Die Raum-Behauptung stand an fünf Orten.
