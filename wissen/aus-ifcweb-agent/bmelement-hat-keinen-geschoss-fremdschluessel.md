---
name: bmelement-hat-keinen-geschoss-fremdschluessel
description: "BmElement hat keine FloorUUID; die Geschosszuordnung eines Bauteils steht NUR im CAD-XML-Attribut floor= — StartingStoreyUUID ist projektweit Sentinel oder NULL"
metadata:
  type: project
  stand: gemessen
---

Wer die Bauteile eines Geschosses per SQL sucht, findet in BmElement keinen Fremdschluessel dafuer. Es gibt kein FloorUUID. Die naheliegenden Kandidaten StartingStoreyUUID und FinalStoreyUUID sind ueber den gesamten Bestand ungenutzt (Sentinel oder NULL, kein einziger echter Verweis).

Die Geschosszuordnung eines Bauteils steht ausschliesslich in der Zeichnung, im Attribut `floor=` des jeweiligen Elements in BmData.ClassValue (LongDesc='CADXMLData'). Das ist derselbe Grundsatz wie ueberall hier: die Zeichnung ist die Quelle, nicht die Tabelle.

Praktische Folge: fuer "welche Bauteile hat Geschoss X" nimmt man projekt_lesen — das macht die Gruppierung bereits — statt sich einen JOIN zu bauen, den es nicht gibt.

**Beleg:** 21.08.2026, HsetuPrjData. (1) `SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='BmElement'` — 157 Spalten, KEINE namens FloorUUID. Ein JOIN `BmElement.FloorUUID = BmFloor.UUID` scheitert mit "Invalid column name 'FloorUUID'". BmRoom hat eine FloorUUID, BmElement nicht — daher die Verwechslungsgefahr. (2) GROUP BY ueber StartingStoreyUUID ueber ALLE Projekte: 37328 Elemente in 88 Projekten auf dem Sentinel aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa, 3522 in 30 Projekten NULL, **null Elemente mit einer echten GUID**. Die Spalte traegt also nirgends einen Geschossverweis.

**Nicht gemessen:** Gemessen ist nur das Negative: dass BmElement keine Geschossspalte fuehrt und StartingStoreyUUID leer bleibt. Dass die Zuordnung stattdessen ueber das Attribut `floor=` im CADXMLData laeuft, ist aus der vorhandenen Doku uebernommen (dort als `<wall ... floor="67710EBF…">` zitiert) und dadurch gestuetzt, dass projekt_lesen die Bauteile korrekt nach Geschoss gruppiert, obwohl es in der Tabelle keinen Schluessel dafuer gibt — selbst nachgelesen im XML habe ich es in dieser Sitzung NICHT. Wofuer StartingStoreyUUID/FinalStoreyUUID sonst gedacht sind (geschossuebergreifende Bauteile?), ist offen und ungemessen.

**Why:** Der geratene JOIN kostet einen Fehlschlag und verleitet danach zum zweiten Rateversuch auf StartingStoreyUUID, der stumm ein leeres oder falsches Ergebnis liefert statt eines Fehlers — die gefaehrlichere Variante. Mir ist genau das in dieser Sitzung passiert: erst "Invalid column name 'FloorUUID'", dann acht Zeilen Sentinel, die wie eine Antwort aussehen.

**How to apply:** Bauteile nach Geschoss nie ueber einen Spalten-JOIN suchen. projekt_lesen benutzen, oder das Attribut floor= aus dem CADXMLData lesen. Und generell: Spaltennamen in BmElement vorher mit INFORMATION_SCHEMA.COLUMNS nachschlagen — die Tabelle hat 157 Spalten und viele heissen fast so, wie man vermutet.
