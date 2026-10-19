---
name: bmelement-katalogzuweisung-catalogbasisuuid
description: "Die Zuweisung Bauteilaufbau -> verbaute Wand laeuft ueber BmElement.CatalogBasisUUID -> TcBasis.UId; Elemente ohne Katalogbezug tragen den Sentinel aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
metadata:
  type: project
  stand: gemessen
---

bauteile/docs/hottgenroth-bauteil-sql.md fuehrt in Abschnitt 13 "Zuweisung an das Gebaeude" als offen ("TcElementReference und die BmElement*-Tabellen ... noch nicht analysiert"). Fuer den Katalogbezug ist das jetzt beantwortet:

**Die Verbindung ist BmElement.CatalogBasisUUID -> TcBasis.UId.** Daneben existiert BmElement.CatalogDimUUID (auf TcBuildingElementDimension). Achtung auf die Schreibweise: BmElement benutzt durchgaengig *UUID* (CatalogBasisUUID, ProjectUUID), die Tc*-Tabellen dagegen *UId*. Wer aus der Bauteil-Doku ProjectUId oder ConstructionUId uebernimmt, bekommt "Invalid column name" -- mir genau so passiert.

Wo der Verweis gesetzt ist, ist BmElement.UValue exakt die Kopie von TcBuildingElementDimension.UValue (2767 von 2767 Waenden). Der U-Wert steht also redundant an beiden Stellen -- typisch fuer dieses Datenmodell. Wer nur eine Seite aendert, hinterlaesst ein Gebaeude, das sich selbst widerspricht.

**Es gibt zwei Betriebsarten.** 3502 der 6334 Waende in Repo 1 haben keinen Katalogbezug und tragen den U-Wert nur in BmElement. Und zwar steht dort **nicht NULL und nicht die Null-GUID**, sondern der Sentinel `aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa`. Wer mit `CatalogBasisUUID IS NULL` sucht, bekommt 0 Zeilen und schliesst faelschlich, es gebe die zweite Betriebsart nicht. Ein fehlender Katalogverweis ist kein Defekt.

**Nebenbefund: schichtlose Katalogbauteile sind normal.** In Test0001 haben alle 29 Katalogeintraege 0 Schichten, Thickness 0, RValue auf dem Sentinel -987654321.99, ElementMeta leer -- und tragen trotzdem einen U-Wert. Die Namen ("Massive Konstruktion - Zweischalige Wandaufbauten mit Daemmschicht", "Holzfenster, einfach verglast (bis 1978)") zeigen: das ist die Typisierung nach Baualtersklassen, wie sie die iSFP-Aufnahme benutzt, nicht ein kaputter Schichtaufbau. Solche Bauteile nicht "reparieren".

**Beleg:** Zwei getrennte Abfragen, nicht vermischen.

(1) Verteilung ueber **alle** Projekte in HsetuPrjData, gefiltert auf `RepositoryType = 1 AND ElementType = 1` (Wand im gerechneten Gebaeude), 6334 Zeilen:

```sql
SELECT CASE WHEN CatalogBasisUUID = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
              THEN 'Sentinel' ELSE 'mit Verweis' END AS Art,
       COUNT(*)
FROM BmElement
WHERE RepositoryType = 1 AND ElementType = 1
GROUP BY CASE WHEN CatalogBasisUUID = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
              THEN 'Sentinel' ELSE 'mit Verweis' END;
-- Sentinel      3502
-- mit Verweis   2832
```

Von den 2832 Verweisen loesen 2767 per LEFT JOIN auf TcBasis (CatalogBasisUUID = TcBasis.UId) auf, 65 laufen ins Leere. Die 2767 haben durchweg `ABS(BmElement.UValue - TcBuildingElementDimension.UValue) < 0.001` (Dimension ueber BasisUId), also 100 %. Gegenprobe: dieselbe Abfrage mit `CatalogBasisUUID IS NULL` liefert 0.

(2) Das Auffuehrungsbeispiel Test0001 (UUID 2c5ac804-0dcc-4560-88a7-7b8827ff69f8) belegt **nur** die erste Betriebsart: seine 8 Aussenwaende zeigen alle auf TcBasis 54730c14-6ac2-4cd8-928c-eef97f63b09e. Fuer die 3502 Sentinel-Zeilen taugt Test0001 nicht -- dort ergibt Abfrage (1) auf der Sentinel-Seite null Zeilen.

**Nicht gemessen:** Aus dem Bestand ausgezaehlt sind allein die Zahlen 6334 / 3502 / 2832 / 2767 / 65 und die U-Wert-Gleichheit (nachgeprueft am 2026-08-21). Geschlossen, nicht gemessen, sind: die Deutung der schichtlosen Katalogbauteile als Baualtersklassen-Typisierung (aus den Namen gelesen, nicht gegen die iSFP-Aufnahme geprueft); die Aussage, ein Sentinel sei kein Defekt (aus der Haeufigkeit gefolgert, nicht an einer Rechnung geprueft); und die gesamte **How to apply** -- sie ist aus der Leseseite abgeleitet, ein Schreibversuch mit anschliessender Wirkungsprobe (UA, Endenergie) steht aus. Ob CatalogDimUUID denselben Sentinel benutzt, ist nicht ausgezaehlt.

**Why:** Ohne diese Spalte kann man einen neu angelegten Bauteilaufbau zwar in den Katalog schreiben, aber nicht an die Wand haengen -- das Bauteil bleibt wirkungslos, und weil es im Katalog sichtbar ist, sieht es nach Erfolg aus. Der Sentinel kostet zusaetzlich Zeit in beide Richtungen: eine `IS NULL`-Suche findet die katalogfreien Waende nicht, und ein naiver JOIN zaehlt sie als "Verweis vorhanden". Und wer schichtlose Typisierungsbauteile fuer Platzhalter haelt, baut Schichten ein, die dort nicht hingehoeren.

**How to apply:** Beim Zuweisen eines Aufbaus an eine verbaute Wand BmElement.CatalogBasisUUID (und CatalogDimUUID) setzen UND BmElement.UValue auf denselben Wert wie die Dimension ziehen; danach die Wirkung messen, nicht nur zurueckgelesen. Beim Suchen nach katalogfreien Elementen auf `CatalogBasisUUID = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'` vergleichen, nicht auf `IS NULL`; umgekehrt beim Suchen nach echten Verweisen den Sentinel ausschliessen. Spaltennamen in BmElement immer mit UUID schreiben, in Tc* mit UId. Vor dem Urteil "Aufbau fehlt" pruefen, ob es sich um ein Typisierungsbauteil handelt (0 Schichten + gesetzter UValue = gewollt).
