---
name: hottgenroth-treppen
description: "Treppen von außen setzen: ElementType 10, 5-Zeilen-Muster mit parametrischem assistant_data — New-Treppe.ps1 (Kopiermuster); Deckenöffnungs-Frage offen"
metadata:
  node_type: memory
  type: project
  originSessionId: 69b0e1ac-3e3b-4456-bef5-11d083ab08da
  modified: 2026-10-17T19:23:03.347Z
---

Treppe = `BmElement.ElementType` **10** (Podest 9; Enum `TTechDataBuildingElementType`
in `Hsetu.Model.Xim.cs`: 4=Storey, 11=BaseSlap, 13=Opening — erklärt die alten
Zählungen). Eine gezeichnete Treppe ist das 5-Zeilen-Muster: BmElement +
**BmElementStair** (Fachdaten: NumberOfRiser, RiserHeight, TreadCoveringType =
Stufenbelag!) + Dimensioning + EnergyConsulting + BmData CADXMLData. Das XML
trägt `<stair>` mit floor-GUID, EINEM Einfügepunkt, `rotation` im **Bogenmaß**
und `<assistant_data>` — ein komplettes escaped-UTF-16-Treppenassistenten-Modell
(ShapeType, Width, Height/ClearHeight/FloorHeight, NumberSteps, StepHeight …).
Energetisch ist die Treppe nie Hüllfläche (Angrenzung „innen"); in der Ökobilanz
läuft sie unter „weitere Bauwerksteile" und braucht dort ihre EPD (ECO-CAD).

**Werkzeug:** `bauteile/tools/New-Treppe.ps1` — Kopiermuster (freier Aufbau hieße
den Assistenten nachbauen): `-Projekt -Geschoss -Punkt 'x,y' -DrehungGrad
[-Hoehe 0=Geschosshöhe] [-Stufen] [-Vorlage] [-VorlageProjekt] -Probelauf`.
Passt Höhe/Steigung konsistent in XML (auch im escaped assistant_data) und
BmElementStair an; warnt bei Steigung außerhalb 0,14–0,20.

**Why:** Der Geometrie-Import (hottcad-modell-Skill) konnte bisher keine Treppen
— Dennis zeichnete sie von Hand. Mit einer je Maschine vorhandenen Vorlage
(Krause MiWo hat zwei) setzt das Werkzeug sie jetzt in jedes Projekt.

**How to apply:** Immer erst `-Probelauf` (läuft bei offener Software mit
Warnung). **Offener Prüfpunkt:** `<OpeningGuidKeys>` (Verweise auf die
Deckendurchbrüche des Quellprojekts) wird beim Kopieren geleert — Hypothese:
HottCAD erzeugt den Durchbruch beim Öffnen neu (OpeningRemoveWellHole=true).
Beim ersten Echtlauf in der Oberfläche prüfen, ob die Decke über der Treppe
öffnet; PS-5.1-Falle dabei gelernt: `-replace` kennt kein Zähl-Argument.
Echtlauf steht aus. [[krause-3qhtk-neubau]] [[haustrennwand-werkzeug]]
