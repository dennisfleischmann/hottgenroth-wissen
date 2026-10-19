---
name: krause-3qhtk-neubau
description: "Krause 3QHTK (Neubau DHH Am Raut 7, Antdorf, KFN EH40): Geometrie am 14.10.2026 neu importiert, Bauteile 100009-100012 im FS-Katalog; Stand und nächste Schritte"
metadata:
  node_type: memory
  type: project
  originSessionId: 69b0e1ac-3e3b-4456-bef5-11d083ab08da
  modified: 2026-10-14T12:40:56.303Z
---

Neubau-DHH Lennart Krause, Am Raut 7, 82387 Antdorf (KFN: BzA + BnD). Auftrag vom
14.10.2026: **komplette Neuplanung ohne die alten FS-Nachweise** (die Projekte
`…_260929`, `…_260929 Kopie`, `…_260923_alt` sind nur noch Zeilenspender).

**Hottgenroth-Projekt `3QHTK_Lennart Krause`** (frisch, von Dennis angelegt):
Geometrie am 14.10.2026 von außen importiert — Gebäude per Bootstrap (das
Software-angelegte Projekt hatte NICHT mal ein BmBuilding), EG 0,25 / OG1 3,04 /
DG 5,83 (Decke 0), drei Außenringe 7,27×11,215 / 0,32, 15 Fenster `F 001`-`F 015`
+ Haustür `AT 001` (bestätigte Maße), Satteldach 25° First Ost-West (Traufe 6,51,
First 9,13). Trennwand West = `AW 004` (Nachbar Am Raut 5 beheizt → adiabat,
**Angrenzung nach erstem Öffnen prüfen**). Wandnamen: AW 001 Süd · AW 002 Ost ·
AW 003 Nord · AW 004 West (je Geschoss gleich). Einmalskripte
`bootstrap-krause.ps1` + `krause-import.ps1` (mit Wiederanlauf-Schutz) im
Scratchpad der Session 69b0e1ac; Vollsicherung
`HsetuPrjData-20261014_134213.bak`. [[leeres-hottgenroth-projekt-bootstrappen]]

**Bauteile im FS-Katalog (gemäß Neuner-Angebot PNr-2001/2, alle ungeprüft):**
AW 100009 (CLT 10 + HWF 20/040, U 0,17) · Steildach 100011 (30 HWF auf OSB,
U 0,12 homogen; zwischensparren wäre ~0,15 — Lage beim Bauträger offen) ·
Bodenplatte 100012 (U 0,13) · Fenster 100010 (Uw 0,78 / g 0,50, EGE) · Haustür =
Katalog 300510 (1,1).

**H_T'-Befund (Planung 14.10.):** EH-40-Grenze ≈ 0,216; Angebotsstand 0,234-0,26
→ **verfehlt**. Nötiges Paket: Fenster 0,78/g0,5 + WB-Detailnachweis 0,02 +
Dach 036 + **Wand 24 cm WDVS** (nur WLG-Wechsel = Punktlandung) → ≈ 0,206.
Rollladenkästen OG/DG liegen in der Hülle (Aufbau offen, U ≤ 0,8 fordern).

**Stand 19.10.2026:** Arbeitsprojekt ist jetzt `3QHTK_Lennart Krause_Holzfaser LCA` (UUID 57dbfc3c), die Kopie ohne „LCA" (9fba35ca) ist Vorstufe. EH 40 erreicht (Qp 20,8, H_T' 0,2189 bei Grenze 0,2195), QNG PLUS 23,02. Hebel waren: WW-Leitung in die Zone, Zirkulation, Kat. I, PV 10 kWp, WP-Vorlauf am Erzeuger 35/28, Trennwand-Bauteil ohne WDVS, Zellulose zwischen Sparren, Schichtdichten ([[eco-cad-dichte-steuert-bezugsmenge]]). **Erledigt 19.10.:** Außenwand Holzfaser 035 nach Neuner-Vertrag. **Noch offen:** Aufsparren 8→10 cm, Fenster 0,76→0,78, Nachweisart Neubau statt EnEV-Änderung, Bundesland Bayern statt NRW, Lena Krause, Baujahr 2027; WB-Detailnachweis rechnet Dennis selbst (Ziel 0,02); sommerlicher WS und DIN-1946-6-Lüftungskonzept **warten bewusst**, bis die Fenster final sind — nicht als Lücke melden.

**Stand 14.10. 14:33 — Zuweisung erledigt:** Räume EG-R1/OG1-R1/DG-R1 (je 70,1 m²,
von außen angelegt) + Zone „Wohnung Einfamilienhaus" (Setup-Wohngebaeude, alle
Invarianten grün). Erstes Öffnen nur HottCAD reichte NICHT (nur Platten) — erst
der Energieberater-Durchgang materialisierte Repo 1. add_components (Vorgang 593,
28 Flächen) hat zugewiesen; Spiegel bestätigt: AW 9 Flächen 0,165 · FA 15×0,78 ·
TA 1,10 · DA 0,125 · BE 0,129. **Trennwand AW 004 (3 Flächen, 89,7 m² W):** per SQL auf „gegen beheizt"
gestellt — `BmElement.AdjacentType` 3→1 + `BmElementEnergyConsulting.
CladdingSurface` 0, nur Repo 1 (Muster: Trennwand im 260929-Modell; Zeichnung
kennt keine Angrenzung). Spiegel bestätigt: IW „Wand gegen beheizt",
in_huelle false; AW-Hülle jetzt 9 Flächen / 151,3 m². **PRÜFPUNKT: übersteht
das das nächste Öffnen?** In der Zeichnung bleibt die Wand Teil des Außenrings
(outer_wall=True) — anders als im Altmodell (eigene 20-cm-Wand). Springt
AdjacentType zurück: Angrenzung einmal in der Oberfläche setzen oder W-Wand
als separate Wand zeichnen. **Offen:** 1. dieser Prüfpunkt, 2. Rechenlauf →
H_T'-Wirkungsprobe (Erwartung: EH 40 verfehlt, ~0,23), 3. bauteil_admin-
Freigabe 100009-100012, 4. später Anlagentechnik (WP), PV, Lüftung, Sommer-WS.

**Why:** Drei Sessions arbeiten an diesem Projekt (Planung, Import, Zuweisung) —
ohne den Stand beginnt die nächste bei null oder, schlimmer, im alten 260929.

**How to apply:** Für LocalDB-Schreibläufe braucht die Session die Regel
`"PowerShell"` in `permissions.allow` von `.claude/settings.local.json` — sie
greift erst in einer NEUEN Session zuverlässig; in der laufenden half erst der
vom Nutzer selbst eingetragene Eintrag nach mehreren Anläufen.
