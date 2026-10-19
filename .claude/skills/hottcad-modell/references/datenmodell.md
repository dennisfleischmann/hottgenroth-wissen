# Datenmodell-Fakten für den Modellaufbau von außen

Gemessen am 14.10.2026 beim Aufbau von *3QHTK_Lennart Krause* (Neubau-DHH) und
der begleitenden Werkzeug-Recherche. Alles hier ist verifiziert, nichts vermutet.
Vertiefung: `bauteile/docs/` (hottcad-grundriss-schreiben.md, hottgenroth-daecher.md,
hottgenroth-raum-zone-sql.md) und die Gedächtnisnotizen.

## Die zwei Repositories

| RepositoryType | Bedeutung | Angrenzung |
|---|---|---|
| 3 (mtyModelRepository) | die **Zeichnung** — Quelle, die HottCAD liest | kennt keine (AdjacentType 0) |
| 1 (mtyModel) | das **gerechnete Gebäude** — entsteht erst durch die Software | trägt AdjacentType, Hüllen-Flag, Fx |

Geometrie von außen schreiben heißt: **nur Repo 3 (CADXMLData) schreiben**, alles
Abgeleitete rechnet die Software beim Öffnen. Repo 1 entsteht **nicht** beim bloßen
HottCAD-Öffnen — erst der **Energieberater-Durchgang** (Gebäudedaten/Bauteilliste
ansehen) materialisiert es, zusammen mit Platten-Verarbeitung und eberater-Container.

Mapping Zeichnung → Modell: `BmElement.RepositoryElementUUID` der Repo-1-Elemente
zeigt auf die UUID der Repo-3-Zeichnungswand. 1:n — Teilung je angrenzendem Raum
(software-gezeichnet, `<segments>`), oder je Geschoss eine eigene Zeichnungswand
(unser Import). Namensmatch immer auf `NULLIF(ShortDesc,'')` **und** `LongDesc`:
software-gezeichnete Projekte füllen nur LongDesc. Nie TOP 1 — immer alle Treffer.

## Ein leeres Projekt (in der Software angelegt, HottCAD nie geöffnet)

hat **kein BmBuilding, keine Geschosse, nichts** — und die Zeichenwerkzeuge
verlangen Vorlagen IM Projekt. Bootstrap = Fremdprojekt-Kopie mit Überschreibung
der projektgebundenen Spalten (`scripts/bootstrap-vorlage.ps1`):
Gebäude (BmBuilding + Data/Dimensioning/EnergyConsulting + 4 BmData-Zeilen, davon
`building_data` frisch mit neuem ActiveFloor), EG (4 Zeilen: BmFloor, BmFloorData,
BmData CADXMLData, BmData is_auto_generated), VORLAGE-Wand und VORLAGEDACH (je
5 Zeilen, ReferenceUUID = BIMUUID = neues Gebäude-BIM). Katalogverweise sind
global und dürfen mitkopiert werden. Dangling GUIDs in building_data
(BasePlatform …) toleriert die Software. Vorlagen nach dem Bau löschen.

**Projektauflösung:** Die Werkzeuge lösen per `LongDesc LIKE '%…%'` auf — ein
Projektname, der Präfix anderer ist (Krause!), ist nie eindeutig. GUID verwenden
(neuere Werkzeuge können das) oder temporär umbenennen und zurück.

## Geschosse, Ringe, Fenster, Dach, Räume

- Geschoss = **vier** Zeilen; `New-Geschoss.ps1` ist idempotent, `Set-Geschoss.ps1`
  stellt Höhenlage/Deckenstärke (oberstes Geschoss unterm Satteldach: Decke 0).
  FloorCount im building_data = Geschosse **über** dem EG.
- Außenring: `New-Aussenring.ps1 -Ecke -Breite -Tiefe -Wandstaerke -VorlageWand VORLAGE`.
  Wandhöhe und z kommen vom Geschoss. Kette läuft gegen den Uhrzeigersinn, Namen
  AW 001 (Süd), AW 002 (Ost), AW 003 (Nord), AW 004 (West) bei Ecke 0,0.
- Fenster/Tür: `New-Fenster.ps1 -Wand -Geschoss -Abstand -Breite -Hoehe -Bruestung -Art -Name`.
  Abstand = vom ERSTEN Wandpunkt entlang der Außenkante (CCW: Süd ab West-Ecke,
  Ost ab Süd-Ecke, Nord ab OST-Ecke!). ≥ 0,5 m Eckabstand, Giebelfenster mittig
  unter den First legen, sonst verschneidet das Dach sie.
- Satteldach: `New-Satteldach.ps1 -Grundriss -Firsthoehe (über Traufe) -Hoehe1
  (Traufe über Geschossebene) -First OW|NS`. Ein Dach trägt zwei Polygone; nur
  eine der Flächen hat eine eigene CADXMLData-Zeile — als Spender die MIT Daten.
- Räume sind von außen anlegbar (BmRoom + BmRoomData + CADXMLData, Muster
  `scripts/anlege-raeume-vorlage.ps1`); HottCAD trägt Begrenzungsverweise nach.
  Danach `Setup-Wohngebaeude.ps1 -Beheizt …` (Zone, Profil 42→UsageType 34,
  Stempel, Zuordnung, 21 Invarianten). Zonenzuordnung immer über die Zonen-UUID.

## Haustrennwand („Wand gegen beheizt") — VIER Felder

| Feld | Außenwand | Trennwand |
|---|---|---|
| `BmElement.AdjacentType` | 3 (btaOutside) | **1 (btaHeated)** |
| `BmElementEnergyConsulting.CladdingSurface` | 1 | **0** |
| `BmElementEnergyConsulting.FxElementType` | 1 (RF01) | **19 (RF19)** |
| `BmElement.MetaDesc` | Property-Cache | zwei Einträge angepasst |

Nur an Repo-1-Zeilen (`ElementType=1 AND RepositoryType=1`). Die Software zieht
fehlende Felder selbst nach, aber **erst beim Öffnen/Schließen-Zyklus** (fx=19 kam
erst mit der Projektschließung; StampEdit verrät diese Nachläufe nicht) — deshalb
alle vier selbst schreiben, sonst warten Spiegel/Rechenlauf/iSFP auf den nächsten
manuellen Zyklus. Werkzeug: `bauteile/tools/Set-Haustrennwand.ps1` (auch
`-MitNebengebaeude`). AdjacentType-Enum: 0 Vorrat, 1 beheizt, 2 unbeheizt,
3 Außenluft, 4 innen, 5 Erdreich, 6 oberste Decke, 7 Kellerdecke.

## Nebengebäude (grafische Darstellung des Anbaus)

Kein Bauteil, keine Angrenzung — ein `<attachment type="Heated">` im
**BmMedia-Blob** (eigene building3d-XML), `wall_ref`/`parent_wall` = CAD-GUID der
Zeichnungswand, Block zwischen `</contour_inner>` und `<surrounding>`. Ein simples
überdeckendes 4-Punkt-Rechteck genügt (so zeichnet es auch die Oberfläche); EIN
Attachment an der EG-Wand deckt alle Geschosse. **Geschrieben wird der Blob erst
beim Schließen des Projekts**, nicht beim Speichern — Diffs vorher zeigen nichts.
Werkzeug: `Set-Nebengebaeude.ps1` (Latin1-Rundlauf, byte-treu).

## Der Spiegel (FS Connector / add_components)

- Der Bauteilspiegel liest **nur Repo 1** — vor dem Energieberater-Durchgang gibt
  es für `add_components` keine Flächen.
- Neues Projekt fehlt in der Liste → `update_hottgenroth_projects`; danach
  `refresh_hottgenroth_components`, 20–30 s warten, und erst auswerten, wenn
  `stand.letzter_abruf.status = "uebernommen"`.
- „U-Wert direkt" + Platzhalterwerte (Spenderwand-Typologie an Wänden,
  `u_value_default_typo` an Fenstern) sind der Normalzustand vor der Zuweisung.
- Zuweisung: `flaechen_einzeln: true` je Kennung → element_uids → `add_components`
  mit `probelauf: true`, U-Werte prüfen, dann echt. Nie zweimal echt (legt doppelt
  an). Erfolg erst glauben, wenn der frische Spiegel die neuen U-Werte zeigt.
- Software zeigt neue Katalogbauteile erst nach einem **Neustart**.

## Sicherheit

Vor jedem Schreibtag: `hottgenroth-agent/tools/Sichere-Projektdatenbank.ps1`
(läuft gefahrlos bei offener Software, COPY_ONLY). Vor jedem Schreiben: Software
zu (`Test-SoftwareLaeuft.ps1` / die Werkzeuge prüfen selbst; der Prozess heißt
auch `EEBerater` oder `Building3D`). Offene Software hält das Projekt im Speicher
und verwirft Fremdänderungen beim Zurückschreiben. Einzelnes Projekt zurückholen:
`Restore-Projekt.ps1` (nie Voll-Restore — setzt alle Projekte zurück).
