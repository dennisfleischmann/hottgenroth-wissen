---
name: hottcad-modell
description: >-
  Baut aus einem Google-Drive-Ordner mit Kundenunterlagen (Eingabeplan/Grundrisse,
  Berechnungen zum Bauantrag, Bauträger-Angebot/Leistungsbeschreibung, Notizen)
  das komplette Hottgenroth/HottCAD-Gebäudemodell auf dem eigenen Arbeitsplatz:
  Geometrie von außen in die Datenbank (Geschosse, Außenringe, Fenster, Satteldach,
  Räume, Einzonenmodell), Bauteile im FS-Katalog anlegen und den Flächen zuweisen,
  Haustrennwand bei Doppel-/Reihenhäusern. Nutze diesen Skill immer, wenn ein
  Drive-Link zusammen mit Hottgenroth/HottCAD fällt oder ein Gebäude-/Neubaumodell
  aus Unterlagen entstehen soll — auch bei Formulierungen wie "erstelle das Modell",
  "setz das Projekt in Hottgenroth um", "wie bei Lennart Krause", "Gebäude
  einspielen", "Geometrie importieren" oder wenn nur der Ordnerlink und ein
  Projektname genannt werden. Nicht für reine Bauteilzuweisung an fertige
  Partnermodelle (dafür hottgenroth-bauteile) und nicht für Anlagentechnik
  (dafür hottgenroth-heizung).
---

**Stand:** Erprobt am 14.10.2026 an *3QHTK_Lennart Krause* (Neubau-DHH, Holzbau,
3 Geschosse, 15 Fenster, Satteldach 25°, Trennwand West) — ein vollständiger
Durchlauf von Drive-Link bis zugewiesener Bauteilliste im Echtbetrieb. Zweiter
Fall steht aus; beim Dazulernen diese Datei fortschreiben.

# HottCAD-Modell aus Drive-Unterlagen

Vier Etappen mit drei festen Haltepunkten. Der Nutzer ist zweimal selbst dran
(Projekt anlegen, Erstöffnung) — das ist Teil des Verfahrens, nicht Verlegenheit.

**Bevor irgendetwas geschrieben wird:** Vollsicherung
(`hottgenroth-agent/tools/Sichere-Projektdatenbank.ps1`, läuft auch bei offener
Software) und Blick in [references/datenmodell.md](references/datenmodell.md) —
dort stehen die Datenbank-Fakten, auf denen alles hier ruht.

## Etappe A — Unterlagen lesen und Plandaten destillieren

1. Drive-Ordner über den Skill `gdrive` holen (Hinweis-Docs zuerst, dann PDFs).
   Text-PDFs mit `pdftotext -layout` (liegt in mingw64), gescannte PDFs und
   Pläne über PyMuPDF rendern und ansehen (`import fitz`, `page.get_pixmap`).
2. Aus den Dokumenten destillieren:
   - **Eingabeplan/Schnitte:** Grundmaße (Außenkontur), Geschosshöhen (±0,00,
     OG-/DG-Kote, Traufe, First), Dachform und -neigung, Anbausituation
     (welche Seite grenzt an den Nachbarn? Ansichten zählen: die fehlende
     Ansicht ist die Trennwand), Fensterpositionen je Fassade.
   - **Flächen-/BRI-Berechnung zum Bauantrag:** Wohnfläche, Raumliste, BRI —
     die Plausibilitätsanker für das Modell.
   - **Bauträger-Angebot/Leistungsbeschreibung:** Wand-/Dach-/Bodenaufbau mit
     Schichten, Fensterqualität (Ug/Uw/g), Haustür — die Quelle für Etappe D.
   - **Fensterliste:** Maße je Element. Gibt es keine, Standardmaße aus Plan-
     Maßketten und Ansichten ableiten — aber nur nach ausdrücklicher Freigabe.
3. **Haltepunkt 1:** Dem Nutzer das Gebäude-Datenblatt vorlegen: Kontur, Höhen,
   Dach, Fensterliste (mit Herkunft je Maß), Trennwandseite, Aufbauten. Fehlende
   Angaben benennen und anhalten statt raten — ein falsches Fenstermaß fällt
   später niemandem mehr auf. Erst nach dem Ja weiter.

## Etappe B — Geometrie in die Datenbank

Voraussetzung: Der Nutzer hat das Projekt in der Software angelegt (Name
notieren!) und die Software ist zu. Ein frisch angelegtes Projekt ist **komplett
leer** (nicht einmal ein Gebäude) — deshalb Bootstrap.

Reihenfolge (alle Werkzeuge liegen in `bauteile/tools`, jedes kann `-Probelauf`
— immer zuerst Probelauf, dann echt):

1. **Bootstrap** nur bei leerem Projekt: Kopie von
   [scripts/bootstrap-vorlage.ps1](scripts/bootstrap-vorlage.ps1) ins Scratchpad,
   die im Kopf markierten Stellen anpassen (Ziel-GUID, Spenderzeilen, Kontur,
   EG-Höhen). Als Spender taugt jedes vollständige Projekt der Maschine.
2. **Projektname eindeutig machen:** Die Werkzeuge lösen per LIKE auf — ist der
   Name Präfix anderer Projekte, GUID verwenden oder temporär umbenennen
   (und am Ende zurück; die Vorlagen-Skripte zeigen beides).
3. **Geschosse** (`New-Geschoss.ps1`, dann `Set-Geschoss.ps1` für Höhenlagen;
   oberstes Geschoss unterm Dach: Deckenstärke 0), **Außenringe**
   (`New-Aussenring.ps1 … -VorlageWand VORLAGE`), **Fenster und Haustür**
   (`New-Fenster.ps1`, Abstandskonvention und Eckabstände siehe Referenz),
   **Satteldach** (`New-Satteldach.ps1`), Vorlagen löschen, zurückbenennen —
   das alles orchestriert nach dem Muster
   [scripts/import-vorlage.ps1](scripts/import-vorlage.ps1) (wiederanlauf-sicher,
   Protokoll in Logdatei).
4. **Räume + Einzonenmodell:** je Geschoss ein Raum
   ([scripts/anlege-raeume-vorlage.ps1](scripts/anlege-raeume-vorlage.ps1)),
   dann `Setup-Wohngebaeude.ps1 -Beheizt <Geschosse>` — erwartbar bleibt genau
   EIN Invarianten-Fehler offen: „Repo 1 fehlt". Den behebt Etappe C.
5. Kontrolle: `Show-Projekt.ps1` — Geschosse, 4 Wände je Geschoss, alle Fenster,
   2 Dachflächen. Flächensumme gegen die Bauantragsberechnung halten.

## Etappe C — Erstöffnung durch den Nutzer (Haltepunkt 2)

Den Nutzer bitten, das Projekt **einmal zu öffnen und wieder zu schließen** —
und zwar nicht nur HottCAD: **erst der Energieberater-Durchgang** (Gebäudedaten/
Bauteilliste ansehen, bis die Flächen erscheinen) erzeugt das gerechnete Gebäude
(Repo 1), die Platten, die Raumübernahme und den eberater-Container. Nur HottCAD
öffnen erzeugt bloß Zeichnungs-Platten — der Bauteilspiegel bliebe leer.
Gute Gelegenheit für den Nutzer, das 3D zu prüfen (Giebel, Fensterbild,
Trennwandseite ohne Öffnungen). Danach verifizieren: Repo-1-Elemente vorhanden,
PrMedia frisch, Räume übernommen.

## Etappe D — Bauteile, Zuweisung, Trennwand

1. **FS-Katalog:** je Bauteilart erst `find_building_components` (Neubau:
   `include_target_constructions: true`), nur bei Lücke `create_building_component`
   mit den Schichten aus der Leistungsbeschreibung — Quellen und Annahmen in
   `sources`/`notes`, Ergebnis ist ungeprüft und das wird gesagt. Fenster brauchen
   Uw UND g (nur belegte Werte, nie Vorschläge). Ablauf und Haltepunkte im Detail:
   Skill `hottgenroth-bauteile`.
2. **Spiegel:** `update_hottgenroth_projects` (neues Projekt!), dann
   `refresh_hottgenroth_components` → warten → Status „uebernommen". Platzhalter
   („U-Wert direkt", Fenster ohne Wert) sind der Normalzustand, kein Fehler.
3. **Zuweisung:** `flaechen_einzeln: true` je Kennung, Zuordnungsvorlage bauen
   (Trennwandflächen AUSLASSEN), **Haltepunkt 3:** Vorlage zeigen und Freigabe
   holen. Dann `add_components` mit `probelauf: true`, U-Werte ausgeben, echt
   schreiben, frischer Spiegel als Beleg (neue U-Werte an den Flächen).
4. **Haustrennwand** (DHH/Reihenhaus): `Set-Haustrennwand.ps1 -Projekt <GUID>
   -Wand '<AW ...>' [-MitNebengebaeude]` — stellt alle vier Felder (siehe
   Referenz) und hängt auf Wunsch das Nebengebäude als Grafik an. Danach im
   Spiegel prüfen: Flächen laufen als „Wand gegen beheizt" außerhalb der Hülle.
5. **Wirkungsprobe statt Selbstprüfung:** Beim nächsten Öffnen rechnen lassen
   und H_T'/Hüllfläche gegen die eigene Vorrechnung halten. Rückschreibbarkeit
   beweist nichts — erst die Zahl aus der Software zählt.

## Die Fallen (jede hat schon einen Lauf gekostet)

- **Offene Software verwirft Fremdänderungen still.** Vor jedem Schreiben prüfen
  (Prozesse heißen auch `EEBerater`, `Building3D`); `-Probelauf` darf laufen.
- **Die Umgebung (Nebengebäude) schreibt HottCAD erst beim Schließen des
  Projekts** — Diffs und Prüfungen vorher zeigen den alten Stand.
- **Spiegel nie vor Status „uebernommen" auswerten** — sonst liest man den Stand
  von vor dem eigenen Schreiben und meldet Phantomfehler.
- **`add_components` nie zweimal echt** — legt alles doppelt an; nach Abbruch
  erst `get_vorgang` (geschrieben: false/ungewiss/true) und Flächen einzeln zählen.
- **Fenster nie näher als 0,5 m an Ecken, Giebelfenster mittig** — das Dach
  verschneidet sie sonst kommentarlos.
- **PowerShell 5.1:** keine `&&`, kein Ternary, Operator nie ans Zeilenende,
  `$PSScriptRoot` nie in param-Defaults.
- **Beträge, Maße, U-Werte nur aus Quellen.** Jede Annahme (Standardmaß,
  Brüstungshöhe, Rahmenanteil) wird benannt und am Haltepunkt vorgelegt.

## Verwandte Skills und Werkzeuge

`gdrive` (Unterlagen holen) · `hottgenroth-bauteile` (Katalog + Zuweisung im
Detail) · `hottgenroth-heizung` (Anlagentechnik danach) · `bauteile/tools/*`
(Zeichen- und Prüfwerkzeuge, `Show-Projekt.ps1`, `Snapshot-/Diff-Snapshot.ps1`) ·
`bauteile/docs/` (Datenmodell-Handbücher).
