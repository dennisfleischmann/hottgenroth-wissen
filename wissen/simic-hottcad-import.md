---
name: simic-hottcad-import
description: "Simic (Kasbachtalstr. 41, Kasbach-Ohlenberg): Hülle am 13.10.2026 importiert — offene Fragen und nächste Schritte hängen in Asana"
metadata:
  node_type: memory
  type: project
  originSessionId: 2ed9860f-2e20-443e-a4ce-98dc560bde95
  modified: 2026-10-13T21:52:20.556Z
---

Hottgenroth-Projekt *Simic* (UUID 1a64ae28-6a10-456d-8a5a-5548f6b71cbf), EFH
Baujahr 1937, Kasbachtalstr. 41, 53547 Kasbach-Ohlenberg. Am 13.10.2026 die
Hülle aus den Drive-Unterlagen (Ordner `1DbwRnCnretl9p_ER4FMAI1m2fI4yv8nr`)
importiert: 4 Geschosse (Keller −2,20 / EG 0,25 / OG 3,20 / DG 6,15),
4 Außenringe (oberirdisch 7,08×9,00 m, 0,32 m; Keller 7,00×9,00 m, 0,58 m
Bruchstein), 13 Fenster + Haustür, Satteldach 45° (First 9,69 m).

- **Quellenlage:** EG-Grundriss fehlt (die „3. OG"-Datei ist ein Duplikat des
  1.-OG-Plans); keine Fensterliste — Höhen/Brüstungen angenommen; Außenfoto
  zeigt Balkon + Balkontür am Nord-Giebel, die in den Plänen fehlen.
  Energieausweis SH-2026-006656315 (EVEBI, Bedarfs) ist die Referenz für
  Kubatur (Af 63,72 m², EG+OG 6,5 m dort pauschal) und „Haustür SW 1×2 m".
- **Nicht importiert:** 5 Dachflächenfenster 0,94×1,60 (Werkzeuggrenze),
  Innenwände, Räume/Zonen, Bauteilzuweisung (Wände tragen Platzhalter
  „Holzspanbetonwand" 1,009 aus der Kopiervorlage Steidl).
- **Keller-Widerspruch:** Erfassungsbogen „teilw. beheizt", Energieausweis
  (Oscar) unbeheizt — bei Zonen klären.
- Fragentabelle (17 Punkte) + Lage-Steckbrief liegen im Drive-Ordner; die zwei
  Subtasks (Fragen; Öffnen/Dachfenster/Zonen) an Dennis hängen am Asana-Task
  1219469748957362 in „FS Hottgenroth". Sicherung vor dem Import:
  `HsetuPrjData-20261013_224514.bak`.

**Stand nach dem ersten Öffnen (13.10. 23:50):** Dennis hat das Projekt geöffnet
— Repo 1, Platten, 3 Räume und der eberater-Container existieren. Danach per
`add_components` zugewiesen (AW Bims 1,2326 · Dach 0,1046 · Fenster 1,30 · Tür
1,80; Spiegel bestätigt) und die **Ist-Anlagentechnik gesetzt** (Variante 2:
Gas-Brennwert Typ 4/0, BJ 2011, 19 kW, ErdgasH, 70/55, Heizkörper Regelung 3,
WW LinkedToHeating + Speicher 2011 ohne Zirkulation; Struktur deckungsgleich
mit Software-Referenz). **Rechenlauf steht aus** (Variante öffnen+speichern),
danach Wirkungsprobe. Vier offene Modellpunkte: Keller nicht übernommen (EG-
Boden „gegen außen", Kellerdecke-Zuweisung lage_passt_nicht), DG als „Dachraum"
unbeheizt gestempelt (Zone Unconditioned — Widerspruch zum Erfassungsbogen),
DG-Giebelfenster von Dachschräge auf 0,21/0,14 m² verschnitten (zu nah an den
Ecken platziert), Dachflächenfenster fehlen noch. Gas-Brennwert heißt intern
`Brennstoff_ErdgasH` (nicht „ErdgasE"), Kombi-WW = bauart `LinkedToHeating`.

**Bauteile (Stand 13.10.):** Katalog + FS-Projekt (project_id 13, CRM
824764000035545335) sind versorgt — AW Bimsvollstein (323, Regionaltreffer 53),
Kellerdecke massiv (329), Fenster-/Dachfenster-/Tür-Typologien (302755/302758/
302383) und zwei **eigene, ungeprüfte** Einträge: Kellerwand Bruchstein 58 cm
(100007, U 2,62 erdberührt) und Steildach saniert 20 ZWD+10 PUR (100008, U 0,10).
Die Hottgenroth-**Flächenzuweisung** und die **Anlagentechnik** sind bis zum
ersten Öffnen gesperrt (siehe [[leeres-hottgenroth-projekt-bootstrappen]]);
Zuordnungsvorlage und Anlagendaten stehen als Kommentar am Asana-Task.

**Anlage (Typenschild-Fotos):** Vitodens 300 wandhängend, Einbau **23.11.2011**
laut Wartungsnachweis/Abgasanlage — Erfassungsbogen/EA sagen 2015 (Widerspruch,
offen). WW über Vitocell 100-W CVA 160 l indirekt (Erfassungsbogen sagt
fälschlich „Kombi"). Keine Zirkulation, Heizkörper, Verteilung im unbeheizten
Bruchsteinkeller.

Gebaut mit [[leeres-hottgenroth-projekt-bootstrappen]]; Zonen-Schritt nach
[[wohngebaeude-einzonenmodell]], Flächenzuweisung per hottgenroth-bauteile-Skill,
Heizung per hottgenroth-heizung-Skill/set_hottgenroth_heizung.
