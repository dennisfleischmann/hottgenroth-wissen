---
name: geodesc-leer-nach-aussenbau
description: "Von außen gebaute Projekte haben leeres GeoDesc und keine Repo-1-Elemente — alle Export- und Ansichtswerkzeuge liefern 0 Bauteile, bis HottCAD das Projekt einmal geöffnet und gespeichert hat"
metadata:
  type: project
  stand: gemessen
---

Ein Projekt, dessen Bauteile von außen über die Werkzeuge (aussenring_anlegen, geschosswaende_kopieren, satteldach_anlegen) entstanden sind und das HottCAD seitdem nicht geöffnet hat, ist für JEDES Export- und Ansichtswerkzeug leer.

Grund: Diese Werkzeuge (Export-Ifc.ps1, Export-Grundriss.ps1, Render-Modell.ps1) lesen die Geometrie aus BmElement.GeoDesc, nicht aus der Zeichnung. Die Werkzeuge schreiben aber nur die Zeichnung (BmData.ClassValue, LongDesc='CADXMLData') plus die BmElement-Stammzeile — GeoDesc bleibt leerer String, und die Elemente stehen in RepositoryType 3 (Vorrat), nicht in 1 (gerechnetes Modell). Das ist konsequent: GeoDesc ist Abgeleitetes, und Abgeleitetes liefert man nicht selbst (siehe hottcad-cadxmldata-fuehrend).

Vorbedingungsabfrage vor jedem Export-/Ansichtsauftrag, eine Zeile:

SELECT RepositoryType, COUNT(*) AS n, SUM(CASE WHEN DATALENGTH(GeoDesc)>0 THEN 1 ELSE 0 END) AS mitGeo
FROM BmElement WHERE ProjectUUID='<guid>' GROUP BY RepositoryType;

Kommt keine Zeile mit RepositoryType 1 und mitGeo>0 zurück, ist nichts zu exportieren — dann erst den Menschen bitten, das Projekt einmal in HottCAD zu öffnen und zu speichern.

Erkennungszeichen im Fehlerbild: die gemeldete Ausdehnung von Export-Ifc.ps1 lautet '179769313486232...e308' — das sind die uninitialisierten Min/Max-Startwerte und heißt immer 'keine einzige Koordinate gelesen', nicht 'kaputte Geometrie'.

WICHTIG beim Nachzählen: GeoDesc ist LEERER STRING, nicht NULL. Eine Prüfung auf 'GeoDesc IS NULL' meldet fälschlich 'gefüllt'. Immer DATALENGTH(GeoDesc)=0 nehmen.

**Beleg:** 21.08.2026, Projekt Test0001 (GUID 2c5ac804-0dcc-4560-88a7-7b8827ff69f8), Wände von außen über aussenring_anlegen/geschosswaende_kopieren erzeugt. Abfrage: SELECT RepositoryType, COUNT(*), SUM(CASE WHEN DATALENGTH(GeoDesc)=0 ...) FROM BmElement -> 8 Elemente, ALLE RepositoryType 3, ALLE DATALENGTH(GeoDesc)=0 (leerer String, nicht NULL). Gleichzeitig BmData LongDesc='CADXMLData' vorhanden mit 11 Sätzen, 512-2514 Bytes; projekt_lesen zeigt die 8 Wände samt Außenkontur korrekt. Folge: ifc_exportieren meldete '0 Bauteile ... 0 Bauteile mit Geometrie' und eine Ausdehnung von +/-1.797e308 (uninitialisierte Min/Max-Sentinels), grundriss_exportieren 'Schnitt bei 1,20 m: 0 Waende. Nichts zu zeichnen.', modell_rendern '0 Flaechen geladen'.

**Nicht gemessen:** Gemessen ist NUR der Zustand: Zeichnung voll, GeoDesc leer, alles Repo 3, drei Werkzeuge liefern null. NICHT gemessen ist die Behebung — dass ein Öffnen und Speichern in HottCAD GeoDesc füllt und die Repo-1-Elemente erzeugt, ist aus hottcad-cadxmldata-fuehrend (HottCAD rechnet Abgeleitetes aus der Zeichnung nach) und raeume-sind-anlegbar (dort ergänzte HottCAD die Bauteilverweise beim nächsten Öffnen selbst) GESCHLOSSEN, nicht nachgeprüft. Ebenfalls offen: ob HottCAD das auch ohne Änderung allein durch Öffnen+Speichern tut, und ob der Repo-1-Bestand dabei mit AdjacentType != 0 entsteht.

**Why:** Ohne diese Vorbedingung deutet man einen leeren Export als Werkzeugfehler und sucht in Export-Ifc.ps1 nach einem Bug, der nicht existiert. Der Fehlkauf kostete hier drei Werkzeugläufe. Umgekehrt gefährlicher: wer den leeren IFC ausliefert, liefert eine formal gültige Datei ohne ein einziges Bauteil — sie öffnet sich im Betrachter ohne Fehlermeldung und zeigt nichts.

**How to apply:** Vor jedem IFC-, Grundriss- oder Renderauftrag die obige Zählabfrage absetzen. Bei 0 Treffern in Repo 1 gar nicht erst exportieren, sondern den Nutzer bitten, das Projekt einmal in HottCAD zu öffnen und zu speichern, und danach neu ansetzen. Nach jedem Export ohnehin ifc_pruefen laufen lassen — die Flächenprobe hätte den leeren Export ebenfalls aufgedeckt.
