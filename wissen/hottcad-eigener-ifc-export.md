---
name: hottcad-eigener-ifc-export
description: "HottCADs eigener IFC-Export laeuft ferngesteuert - gebaut, geprueft, im Agenten verdrahtet"
metadata:
  node_type: memory
  type: project
  originSessionId: da0215b4-d437-4ebb-9c3d-60a23ed95a70
  modified: 2026-10-13T21:00:27.170Z
---

**Erledigt am 16.08.2026.** HottCAD schreibt IFC selbst, und der Agent ruft das
jetzt fern auf. Der Schrittsatz steht in
`app/Services/HottgenrothHottCadIfc.php`, eingehaengt in
`HottgenrothProjektExport`; die Datei kommt als Art `ifc-hottcad` ins Manifest.

**Warum das wichtig war:** der selbstgebaute Exporter
(`hottgenroth-agent/tools/Export-Ifc.ps1`) rekonstruiert Koerper aus den
DIN-Bezugsflaechen. Die stimmen fuer die Bilanz auf 0,0000 m2, sind aber kein
Baumodell — Ecken, Anschluesse, Laibungen und Gauben muessen geraten werden.
Daran ist eine ganze Runde gescheitert. HottCADs Export kommt aus dem
CAD-Modell und muss nichts raten. Er bleibt als zweite Ausgabe bestehen.

Baugruppen in `C:\Program Files\Common Files\HSETU\HottCAD3D` — **nicht** im
Energieberater-Ordner, worauf die Bruecke standardmaessig zeigt:

- `Hsetu.Cad.IfcXbimExport.XbimFassade.dll` —
  `src.io.SaveModelToIfc.SaveAll(TModelProject, datei, IFCVersionType, 32,
  IEnumerable<ContainerType>, false, false)`
- `Hsetu.Cad.IFC.dll` — `IFCExportManager.WriteToFile(...)` (nicht gebraucht)

Der Ordner enthaelt auch `Hsetu.FW.ModelHelper*.dll`, also **beides** —
`{"install": "…\\Common Files\\HSETU\\HottCAD3D"}` genuegt.

**Der Ladeweg steht in [[hsetu-projekt-headless-laden]]** — ohne
`TFWProjectEnvironment` laedt der Export die ganze Datenbank und stirbt an
doppelten Schluesseln. Die Behaelterliste muss typisiert sein: ``new
System.Collections.Generic.List`1[[Hsetu.Cad.Core.ContainerType,
Hsetu.Cad.Core]]``, ein JSON-Array wirft.

**Gemessenes Ergebnis** (Pohlstrasse 133, 199 Bauteile): 2.182 KB, 23.967
Entitaeten — gegen den Export aus der Oberflaeche identisch in Waenden (55),
Fenstern (24), Tueren (17), Decken (6), Daechern (10), Raeumen (22), Geschossen
(4). Einziger Unterschied: 2 `IFCMATERIALLAYERSET` fehlen. Zweites Projekt
(Gauting, 76 Bauteile) laeuft ohne jede Anpassung.

**Rein lesend, anders als ueber die Oberflaeche.** Der Export im Programm fuehrt
vorher „Bauteilzerlegung neu berechnen" aus und aendert dabei Projektdaten (legte
`AW 010` an, hob die Huellflaeche von 437,67 auf 440,27 m2). Der ferngesteuerte
Weg tut das nicht — nachgemessen unveraendert.

**Grenze (13.10.2026, Simic):** ein Projekt, das nur als **Zeichnung** existiert
(CADXMLData geschrieben, nie in HottCAD geöffnet), exportiert leer — der
Übersetzer meldet je Element „skipped, cause it has no geometry", und
`TModelBIM.Elements.Count` ist 0. Die Wirkungsprobe per IFC geht also erst,
nachdem HottCAD das Projekt einmal geöffnet und das Modell materialisiert hat.
Vorher ist das kein Fehler des Imports.

**Diagnose fehlender Bauteile:** IFC-Koerper vermessen und gegen
`BmElement.NetArea` halten. Beim Aufsummieren der Punkte den
`IFCGEOMETRICREPRESENTATIONCONTEXT` ueberspringen — sonst zieht dessen Nullpunkt
jedes Bauteil auf die Groesse des Weltkoordinatensystems (Gebaeude liegen bei
x ~ 650 m). Damit gefunden: die oberste Geschossdecke der Pohlstrasse hat in
Hottgenroths **eigener** Datenbank `NetArea = 0` am Elternbauteil (`Boden DG`,
`Boden DG 002`, RepositoryType 3); nur die abgeleiteten Teilflaechen
`… [3]-1..8` tragen 68,13 m2. Kein Exportfehler, sondern eine Luecke im
CAD-Modell dieses Projekts — im zweiten Projekt ist dieselbe Decke da (89,8 m2).
