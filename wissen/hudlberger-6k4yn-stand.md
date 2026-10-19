---
name: hudlberger-6k4yn-stand
description: "iSFP 6K4YN Ramona Hudlberger (Aschau am Inn): Entscheidungen, was im Hottgenroth-Projekt fehlt, und der vereinbarte Weg (Anbau rechnen, Altbau grob zuschlagen)"
metadata:
  node_type: memory
  type: project
  originSessionId: e2af98d5-8739-4c3e-bae5-2312d3ea7332
  modified: 2026-10-17T22:29:48.585Z
---

Stand 18.10.2026. Dennis will den **kompletten iSFP** für 6K4YN (MFH, Nehuberweg 1,
84544 Aschau am Inn-Wiesengrund, Drive-Ordner `1BPkYqvxlQuunUEu4iGaFiWa4lYDzlIia`).

**Entscheidungen von Dennis:**
- Baujahr: **ca. 1850 Altbau, 1975/76 Anbau** (DENA-Checkliste + Bauakte 1581/75); der
  CRM-Wert „1950" ist ein Platzhalter. Fehlendes „anhand der Bilder schätzen", nicht nachfragen.
- Hottgenroth **zuerst fertig rechnen**, dann Fahrplan (nicht Entwurf mit Annahmen).
- Das Hottgenroth-Projekt `6K4YN_Ramona Hudlberger_051026` (GUID ea4aa101-…0057) enthält
  **nur den Anbau** (14 Räume, EG+OG1, DG leer) – der Altbau mit den meisten Wohnräumen ist
  nicht gezeichnet, Grundrisse dafür fehlen. Vereinbart: **Anbau rechnen, Altbau grob aus
  den 240 m² Wohnfläche zuschlagen**, als Näherung gekennzeichnet.

**Stand 18.10. abends:** Zone „Wohnen" (MFH-Profil, InfoDesc `P0Zone_1[511B16A6]` aus dem Rechenlauf von 01:06) und Stempel sind gesetzt (EG-R1 = Diele, EG-R2 = Heizraum, EG-R7 = Wasch-/Trockenraum, OG1-R1 Wohnen – meine erste Zuordnung war im EG vertauscht). **Altbau hat Wände nur in der Zeichnung (Repo 3 CAD-XML), keine Räume** → HottCAD erzeugt dort keine Modellbauteile. `New-Raum.ps1` (bauteile/tools) + Treiber `scratchpad/raeume-anlegen.ps1 -Echt` legen 10 Räume an (5 EG, 3 OG1 Wohnraum; OG1 + DG Dachraum); Probelauf grün, Echtlauf vom Auto-Mode-Filter geblockt. HottCAD setzt `RoomType` beim Speichern aus `PdProfileReference` zurück – Kellerraum-Profil hängt noch an OG1-R1/EG-R2/EG-R7 (DELETE geblockt, kosmetisch für Einzonen-18599).

**Was im Projekt noch fehlt (Reihenfolge):**
1. Raumstempel + Zone: alle 14 Räume tragen Standard-Stempel („Kellerraum" OG1-R1 ist das
   Wohnzimmer, 15 °C; Dachräume „beheizt"), **0 DIN-18599-Zonen**. Dafür wurde
   `set_hottgenroth_raeume` gebaut; Plan im Probelauf erprobt (OG1-R1 → Wohnraum 20 °C;
   OG1-R4/5/6 Dachraum, EG-R1 Heizraum (24), EG-R2 Wasch-/Speicher (34), EG-R5/6 Garage →
   unbeheizt, aus der Zone; Profil `mfh`). Noch **nicht geschrieben** – Werkzeug muss erst deployt sein.
2. Bauteile: Planungstabelle steht (AW 301941, DA 304446, WK 100001 ungeprüft, BE **303184**
   statt 300078 (Schichtfehler → U 1,51 statt 1,20), FA 302610 Holz ~1975, TA 302382);
   Probelauf grün, echter `add_components`-Lauf wurde vom Berechtigungsfilter gestoppt.
3. Anlagentechnik Ist-Zustand: zwei Gaskessel (Junkers Therme; Viessmann Eurola 1998, 19 kW),
   Speicher Ritter Aqua Expresso III 800 R (816 l); kein `eberater.zip` → Projekt nie im
   Energieberater geöffnet/gerechnet. Zonenkennung für `BmZone.InfoDesc` gibt es deshalb noch
   nicht; ein zweiter Raeume-Lauf trägt sie nach.

**Why:** Die Kette brach an jeder Stufe an etwas, das in keinem Werkzeug sichtbar war
(Platzhalter-U-Werte 0,24 überall, generische Raumstempel, fehlende Zone). Wer hier
weitermacht, soll nicht erneut von vorn ermitteln.

**How to apply:** Erst `get_hottgenroth_raeume`, dann `set_hottgenroth_raeume` mit obigem
Plan (Probelauf → echt), dann Bauteile, dann Heizung, dann Projekt einmal in der Software
öffnen/speichern. Vor Wirkungsprobe nichts „fertig" nennen ([[wirkungsprobe-statt-selbstpruefung]]).
Siehe [[raum-zone-raumstempel]], [[neues-projekt-zone-raeume]].
