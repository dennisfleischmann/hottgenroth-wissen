---
name: geschoss-anlegen-erbt-clearheight-und-infodesc
description: "New-Geschoss.ps1 kopiert ClearHeight und BmData.InfoDesc aus dem Vorlagengeschoss und zieht sie nie nach; Set-Geschoss.ps1 setzt ClearHeight ebenfalls nicht — ein per Werkzeug angelegtes Geschoss traegt danach die lichte Hoehe und den Geschossnamen der Vorlage"
metadata:
  type: project
  stand: gemessen
---

Beide Geschoss-Werkzeuge hinterlassen stille Reste der Vorlage. Nach jedem geschoss_anlegen/geschoss_aendern pruefen: SELECT LongDesc, Height, ClearHeight, Area FROM BmFloor und die InfoDesc der zugehoerigen BmData-CADXMLData-Zeile. Erwartung im Regelfall: ClearHeight = Height, InfoDesc = Geschossname. Beheben laesst es sich derzeit von aussen NICHT — datenbank_fragen ist lesend, und kein Werkzeug schreibt diese beiden Spalten. Vorschlag: Set-Geschoss.ps1 im UPDATE BmFloor um ClearHeight=@h erweitern, New-Geschoss.ps1 in der $gem-Hashtable InfoDesc auf den Geschossnamen setzen.

**Beleg:** 22.08.2026, Test0001 (2c5ac804-0dcc-4560-88a7-7b8827ff69f8). Keller per geschoss_anlegen (Vorlage EG) angelegt, dann geschoss_aendern -LichteHoehe 2.4 -Hoehenlage -2.4. Danach in BmFloor: Height=2.4, aber ClearHeight=2.6 (Wert des EG); in BmData 'CADXMLData' des Kellers steht InfoDesc='EG'. Auszaehlung ueber den Gesamtbestand: ABS(Height-ClearHeight)<0.0001 bei 360 von 387 Geschossen, die 27 Abweichungen sind ausschliesslich Dachgeschosse mit Abweichung in der 7. Nachkommastelle (z.B. Am Einfang 10: 1.56126432 vs 1.56126286) plus zwei echte DG-Faelle. InfoDesc = eigener Geschossname bei 87 von 89 CADXMLData-Geschosszeilen; die beiden Ausreisser sind DG und Keller in Test0001, beide von New-Geschoss.ps1 erzeugt, beide mit InfoDesc='EG'. Quelltext bestaetigt es: New-Geschoss.ps1 uebergibt in der Hashtable $gem nur UUID/GId/ShortDesc/LongDesc/Stamp*, Set-Geschoss.ps1 schreibt im UPDATE nur ElevationOfRefHeight, Height, CeilingThickness, FloorHeight, StampEdit.

**Nicht gemessen:** NICHT gemessen ist die Auswirkung: ob HottCAD ClearHeight beim Oeffnen aus Height nachrechnet (wie es Flaechen und Volumen tut) oder ob es die 2.6 anzeigt bzw. weiterrechnet, wurde nicht geprueft — das Projekt wurde nach der Aenderung nicht geoeffnet. Ebenso ungeprueft, ob InfoDesc ueberhaupt ausgewertet wird oder blosse Beschriftung ist. Dass ClearHeight ueberhaupt 'lichte Hoehe' bedeutet, ist aus der Gleichheit mit Height bei 360 Geschossen geschlossen, nicht aus dem Quelltext belegt. Auch Area (116 vom EG geerbt, obwohl der Keller keine Waende hat) und BasePlateThickness werden mitkopiert; Area gilt als abgeleitet und wurde absichtlich nicht angefasst.

**Why:** Ein Geschoss mit Height 2.4 und ClearHeight 2.6 widerspricht sich selbst. Genau die Sorte Fehler, die dieses Datenmodell gefaehrlich macht: die Oberflaeche zeigt womoeglich die eine Zahl und gerechnet wird die andere, und niemand bemerkt es, weil kein Werkzeug Alarm schlaegt. Der Diff meldet die Zeile als korrekt angelegt.

**How to apply:** Nach dem Anlegen eines Geschosses die beiden Felder auszaehlen und die Abweichung dem Nutzer melden, statt sie im gruenen Diff untergehen zu lassen. Solange die Werkzeuge nicht ergaenzt sind, gehoert der Hinweis in jeden Abschlussbericht.
