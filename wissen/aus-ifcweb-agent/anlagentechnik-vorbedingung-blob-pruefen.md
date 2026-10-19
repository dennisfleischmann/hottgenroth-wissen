---
name: anlagentechnik-vorbedingung-blob-pruefen
description: "Vor jedem Anlagentechnik-Auftrag zuerst prüfen, ob das Projekt überhaupt einen Kernel18599V5/eberater-Container führt — eine Abfrage, spart einen ganzen Fehllauf"
metadata:
  type: project
  stand: geschlossen
---

Nicht jedes Projekt in HsetuPrjData hat ein DIN-18599-Anlagenmodell. Fehlt der Container, existiert auch keine Variante und kein `TableZusatz.Kernel18599V5`, in das ein Wärmeerzeuger geschrieben werden könnte (die Quelle ist der Variantensatz, nicht der PrMedia-Anhang — siehe din18599-anlagentechnik-ibp-blob).

Die Prüfung darf **nicht** auf „hat das Projekt irgendeine PrMedia-Zeile" lauten. PrMedia nimmt auch Fotos und andere Anhänge auf; ein Projekt ohne Anlagenmodell, aber mit einem Foto, rutscht durch eine ungefilterte Abfrage durch. Deshalb auf die beiden Containernamen filtern:

```sql
SELECT m.MediaName, DATALENGTH(m.Media) AS Bytes
FROM PrMedia m
WHERE m.ProjectUUID = '<Projekt-UUID>'
  AND m.MediaName IN ('eberater.zip', 'Kernel18599V5.bin')
```

Keine Zeile → abbrechen und melden. Der Container entsteht nur, wenn ein Mensch im Energieberater einmal eine Variante mit Heizungserfassung DIN 18599 anlegt und speichert; von außen ist er nicht sinnvoll zu erzeugen.

Ein fehlender Container sagt nichts über Größe oder Ernsthaftigkeit des Projekts: `ifx_test1` führt 985 Bauteile und `IFC 2` führt 1231 Bauteile — beide ohne Container. Also nicht anhand des Bauteilbestands raten, sondern die Abfrage fahren.

**Beleg:** 21.08.2026, Projekt Test0001 (UUID 2c5ac804-0dcc-4560-88a7-7b8827ff69f8): `SELECT MediaName, DATALENGTH(Media) FROM PrMedia WHERE ProjectUUID='…'` liefert NULL Zeilen, während dieselbe Abfrage ohne Projektfilter 50+ Zeilen mit je `eberater.zip` und `Kernel18599V5.bin` zeigt. Test0001 führt zudem 0 Räume und 8 Bauteile. Nachgezählt am Bestand: 85 von 85 Projekten mit Container haben genau **eine** `eberater.zip` — keines mehrere. Gegenbeispiele ohne Container: `ifx_test1` (985 Bauteile), `IFC 2` (1231 Bauteile).

**Nicht gemessen:** Der Satz „von außen ist der Container nicht sinnvoll zu erzeugen" ist geschlossen, nicht geprüft — es wurde kein Versuch unternommen, `eberater.zip`/`Kernel18599V5.bin` von außen anzulegen. Ebenso geschlossen ist, dass PrMedia neben den beiden Containernamen nur Anhänge ohne Anlagenbezug führt; ausgezählt wurde lediglich, dass Zeilen mit anderen `MediaName`-Werten vorkommen. Ausgezählt sind: 85/85 genau eine `eberater.zip`, die beiden Bauteilzahlen und der Nullbefund für Test0001. Ein früherer Stand dieses Eintrags behauptete, mehrere `eberater.zip` je Projekt seien möglich und das jüngste `StampEdit` gewinne — das war aus einem Geschwistereintrag übernommen und ist an 85 von 85 Projekten widerlegt.

**Why:** Ohne diese Prüfung baut man Feldwerte, Vorgabesätze und Aufrufe für ein Ziel, das es nicht gibt, und merkt es erst beim Schreiben. Schlimmer: wer ersatzweise in die Pm*-Tabellen schreibt, erzeugt Zeilen, die der Energieberater nie liest — ein stiller Fehlschlag, der wie Erfolg aussieht. Und wer ungefiltert auf „irgendeine PrMedia-Zeile" prüft, hält ein Projekt mit einem Foto für ein Projekt mit Anlagenmodell und läuft in genau diesen Fehlschlag hinein.

**How to apply:** Bei jedem Auftrag zur Anlagentechnik (Wärmeerzeuger, Heizkreis, Warmwasser, Lüftung) die gefilterte Abfrage als ersten Schritt fahren, noch vor jeder Feldüberlegung. Genau eine Zeile je Containername erwarten; kommen mehrere, ist die Annahme dieses Eintrags verletzt und der Fall zuerst zu klären, nicht per Zeitstempel aufzulösen. Fehlt der Container, den Nutzer bitten, die Variante einmal in der Software anzulegen.
