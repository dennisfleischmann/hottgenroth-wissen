---
name: saakd-tchounet-stand
description: "SAAKD Tchounet (WSN § 51, Aufstockung EFH 1954 Niederpleis): Hottgenroth-Projekt existiert aber leer; Bauteilplan recherchiert, wartet auf Freigabe und Zeichnung"
metadata:
  node_type: memory
  type: project
  originSessionId: 1a6696d9-821f-4695-ae5a-8fd830bdb698
  modified: 2026-10-14T10:16:34.223Z
---

Stand 14.10.2026: Für den GEG-§-51-Nachweis Tchounet (CRM `824764000038111163`,
FS-Projekt 14, Hottgenroth „SAAKD_Arnau Tchounet") gilt:

- **Hottgenroth-Projekt ist eine leere Hülle** (angelegt 14.10. ~11:00, keine
  Flächen, kein Projektkatalog). Zuweisen geht erst nach der Zeichnung.
- **Unterlagen** (Drive „🔧 Projektunterlagen Arnau Tchounet"): Bauantragssatz
  Marnach, Stand 09.03.2025. `Materialangaben.JPG` ist Statik (E-Module), keine
  thermischen Aufbauten. Baubeschreibung: Bestand = **Stahlbeton-Skelett mit
  Vollziegel-Ausfachung**, Aufstockung = Holzrahmen. Detailschnitt: WDVS am
  Bestand/Aufmauerung **ohne Stärke**, DG-Drempel 87,5 cm, flaches Satteldach
  (Traufe +8,05, First +8,57), Geschosse KG −2,25 · EG 0,00 · OG 2,75 ·
  DG 5,60. Dämmstärken und Fenster-U-Werte fehlen überall → Nachforderung an
  Entwurfsverfasser Marnach (02428/1413) läuft.
- **Eingespielt am 14.10. ~11:28** (Freigabe Dennis, Vorgang 581, im Spiegel
  belegt): Dach 304585 (U 0,20, DA) · AW neu 301943 (U 0,24, AW) · Fenster neu
  302755 (Uw 1,30, FA) — als Projektkatalog ohne Flächenzuweisung; Software
  braucht Neustart, um sie zu zeigen. Alle vier auch am FS-Projekt 14
  dokumentiert (assignments 16–19).
- **Zweite Runde 14.10. ~11:37** (Anweisung Dennis „Nutze Typologie"): AW
  Bestand 330 (regionaltypisch Bims 1949–57, U 1,5433 aus 3 Schichten, AW) und
  Kellerdecke 304152 (Typologie Niedersachsen 1949–68 freistehendes EFH,
  U 0,975 direkt, BK) eingespielt und belegt — Projektkatalog hält jetzt 5
  Bauteile. **Gelernt:** Die Altbauatlas-Kellerdecke 333 (Schichten) rechnete
  der Import auf 3,31 statt 2,26 hoch (Rse 0,04 statt 0,17 bei „gegen
  unbeheizt") — bei Lagen gegen unbeheizt Typologiewerte (U direkt) nehmen,
  die werden nicht nachgerechnet. Außenwand-Schichten reproduzieren sauber.
- **Bestandsfenster bewusst NICHT gesetzt**: Typologie 1954 hieße
  Einfachglas U ~5,0, widerspricht Energieausweis Klasse E (140,95 kWh/m²a);
  Erneuerungsstand unbekannt → wartet auf Fensterliste/Foto. Bestands-AW war strittig:
  Baubeschreibung sagt Vollziegel, Regionaltypologie sagt Bims (330, U 1,54),
  Foto zeigt Verblender — Entscheidung bei Dennis. Bestandsfenster offen.
- **Überschlag § 51**: DG-Hülle mit 0,20/0,24/1,30 + ΔU_WB pauschal 0,10 →
  H_T' ≈ 0,40 gegen Grenze ≈ 0,45 (1,2× Referenz) — trägt, mit ~10 % Luft.
- Suche lief mit `ranking: strukturiert_ohne_embedding` (semantisches Ranking
  war ausgefallen) — Treffer nur U-sortiert. **Falle:** Typologie-Klasse
  „Neubau" hat kein year_from/to und matcht JEDES Baujahr — bei
  Bestandssuchen mit include_typology_values steht sie fälschlich vorn.

- **Hülle GEZEICHNET 14.10. ~12:20** (zeichne-saakd.ps1, auf ausdrückliche
  Anweisung Dennis ausgeführt; Skripte im Session-Scratchpad
  `…\scratchpad\tchounet\`): Das Projekt war völlig leer (kein BmBuilding) —
  Bootstrap per Steidl-Spenderkopie legte Gebäude + 4 Geschosse + Vorlagen an,
  danach 4 Außenringe, 5 DG-Fenster, flaches Satteldach (2 Flächen, 6,42°,
  Traufe +8,05/First +8,57), Vorlagen wieder gelöscht. Kontrolle: 23 Bauteile
  in Repo 3. Geometrie: Keller 8,87×8,16 (W 0,30) · EG/OG/DG 9,24×8,56
  (W 0,365/0,365/0,455) · Höhen −2,25/0/2,75/5,60. Fassaden: AW 001=SW,
  002=SO, 003=NO, 004=NW; DG-Fenster F 001 (SO), F 002/003 (NO), F 004/005
  (NW), à 1,28×1,26, Brüstung 0,875 (Positionen ±0,5 m Annahme).
  EG/OG-Fenster bewusst nicht gezeichnet (Fensterliste fehlt). SmSite heißt
  „Niederzier" (Ort des Architekten — beim Öffnen korrigieren).
  DB-Sicherung vor dem Eingriff: `HsetuPrjData-20261014_120248.bak`.
  **Nächster Schritt: Projekt einmal in HottCAD öffnen+speichern** (Repo 1,
  Platten, Räume, Container — [[leeres-hottgenroth-projekt-bootstrappen]]),
  erst dann Flächenzuweisung per add_components und Zonen/§-51-Häkchen.
  Der Permission-Filter hatte den ersten Versuch geblockt; mit der
  ausdrücklichen Nutzeranweisung lief derselbe Aufruf durch.

Nachweisweg: [[geg-erweiterungsnachweis-hottgenroth]] (zwei Häkchen, Zone DG
als Erweiterung, Bestandszone fliegt raus). Sommerlicher Wärmeschutz raumweise
nach Zeichnung ([[sommerlicher-waermeschutz-bestaetigen]]).
