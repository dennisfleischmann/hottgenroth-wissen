---
name: hottgenroth-bauteile-planen
description: Eine Bauteilliste aus Excel oder CSV einlesen und dazu die passenden Katalogaufbauten planen — ohne etwas zu schreiben. Ergebnis ist eine Planungstabelle und dieselbe Liste mit einer zusätzlichen Spalte. Auslöser: Bauteile planen, Aufbauten vorbereiten, "hier ist meine Bauteilliste", Excel-Liste auswerten, U-Werte vorschlagen, Bauteilrecherche ohne Schreiben.
---

**Stand:** Neu am 21.09.2026, noch nicht an einer echten Beraterliste erprobt. Die
Recherchewerkzeuge dahinter sind es (Katalog mit 5.731 Zeilen, Stand Produktion).

## Worum es geht

Der Berater führt seine Bauteilliste in Excel: eine Zeile je Bauteil oder je
Fläche, mit dem, was er vor Ort aufgenommen hat. Dieser Ablauf liest sie ein,
sucht zu jeder Zeile den passenden Katalogaufbau und gibt zwei Dinge zurück —
eine Planungstabelle zum Durchsehen und dieselbe Liste als CSV mit einer
zusätzlichen Spalte.

**Dieser Skill schreibt nichts.** Kein Hottgenroth-Projekt, kein
Katalogeintrag, kein FS-Projekt. Er plant, und die Planung geht danach an einen
Menschen. Wer schreiben will, nimmt den Skill `hottgenroth-bauteile` — das ist
ein anderer Ablauf mit anderen Freigaben.

**Erlaubt sind genau diese Werkzeuge:**

| | |
|---|---|
| `find_building_components` | Katalogaufbauten suchen |
| `get_component_details` | Schichtaufbau eines Treffers ansehen |
| `get_typical_u_value` | baujahrtypischer Ansatz, wenn der Katalog nichts führt |
| `get_project` | Baujahr und PLZ aus einem FS-Projekt holen |

**Verboten, auch wenn der Nutzer darum bittet:** `add_components`,
`add_component_to_project`, `create_building_component`,
`add_hottgenroth_bauteile`, `import_hottgenroth_projekt` und jedes andere
Werkzeug, das etwas verändert. Bittet er darum, sag, dass dieser Ablauf nur
plant, und verweis auf den Schreib-Skill. Wechsle nicht stillschweigend die
Rolle.

**Zwei Haltepunkte:** nach dem Einlesen (stimmt die Spaltenzuordnung?) und nach
der Recherche (stimmt die Wahl je Bauteil?). Mehr braucht es nicht, weil am Ende
nichts passiert, was sich nicht zurücknehmen ließe.

---

## 1 — Die Datei einlesen

Liegt keine Datei vor, frag danach: CSV oder Excel, eine Zeile je Bauteil oder je
Fläche. **CSV ist der sicherere Weg** — bei Excel mit mehreren Blättern frag,
welches gilt, statt das erste zu nehmen.

Lies die Datei und zähl, was du hast: Zeilen, Spalten, und wie viele Zeilen in
den wichtigen Spalten leer sind. Das gehört in die erste Antwort, bevor
irgendetwas gedeutet wird.

**Drei Fallen beim Einlesen, alle aus Excel:**

- **Deutsche Dezimalkommas.** „8,41" ist eine Zahl, kein Text. Wer sie als 841
  oder als 8.41 liest, plant mit der falschen Fläche. Prüf an einem Wert, ob
  deine Deutung zum Kontext passt — eine Wand mit 3.232 m² gibt es nicht.
- **Verbundene Zellen und Zwischenüberschriften.** Excel-Listen haben oft eine
  Kopfzeile je Geschoss oder je Bauteilart. Solche Zeilen sind keine Bauteile;
  nenn sie und lass sie weg, statt sie mitzuzählen.
- **Einheiten in der Zelle.** „24 cm", „0,38 m" und „380" stehen für dasselbe.
  Sag, wie du es gelesen hast.

## 2 — Die Spalten zuordnen

Die Liste ist selbst gepflegt, also heißen die Spalten jedes Mal anders. Ordne
zu, was du erkannt hast, auf diese Felder:

| Feld | Bedeutung | Pflicht |
|---|---|---|
| `bauteil` | Was es ist: Außenwand, Dach, Fenster, Kellerwand … | ja |
| `bezeichnung` | Wie der Berater es nennt: „AW Nord", „EW 008" | ja |
| `flaeche_m2` | Fläche in m² | nein |
| `richtung` | Himmelsrichtung | nein |
| `geschoss` | EG, OG, DG, Keller | nein |
| `raum` | Raum oder Lage im Gebäude | nein |
| `aufbau` | Was vor Ort aufgenommen wurde: Material, Stärken | nein |
| `u_wert_bestand` | ein schon angesetzter U-Wert | nein |
| `bemerkung` | alles andere | nein |

**Erster Haltepunkt.** Zeig die Zuordnung als Tabelle — Spalte der Datei links,
Feld rechts — und dazu die ersten drei Zeilen, so wie du sie gelesen hast. Frag,
ob das stimmt.

```
Spalte in der Datei      wird gelesen als
Bauteilbezeichnung   →   bezeichnung
Art                  →   bauteil
Fläche [m²]          →   flaeche_m2          (Komma als Dezimaltrenner)
Orientierung         →   richtung
Notiz                →   aufbau
Kostengruppe         →   (nicht verwendet)

Zeile 1: Außenwand · „AW Nord" · 32,32 m² · N · „Ziegel 24 + Klinker"
Zeile 2: …
```

**Eine Spalte, die du nicht verstehst, bleibt leer — nicht geraten.** Und nenn
ausdrücklich die Spalten, die du **nicht** verwendest. Eine stillschweigend
übergangene Spalte ist der häufigste Weg, eine Angabe zu verlieren, die der
Berater für wichtig hielt.

**Fehlt `bauteil` ganz**, lässt es sich oft aus der Bezeichnung ableiten („AW" →
Außenwand, „DA" → Dach). Leite ab, aber zeig die Ableitung in derselben Tabelle
und lass sie bestätigen.

## 3 — Was zum Planen fehlt

Vor der Suche gegenhalten:

| brauchst du für | ohne das geht nicht |
|---|---|
| **Baujahr** | jede Suche — es ist das wichtigste Filterkriterium |
| PLZ | das regionale Ranking (kein Filter, aber es hilft) |
| Aufbau oder Foto je Wand | die Wahl zwischen ein- und zweischalig |
| Fensterliste | Verglasung und Rahmen |

**Fehlt das Baujahr, such nicht — frag danach.** Steht eine FS-Projektnummer in
der Datei oder nennt der Berater eine, hol Baujahr und PLZ mit `get_project`,
statt zu fragen.

Was sonst fehlt, sammelst du und nennst es **am Ende gebündelt** — nicht als
Rückfrage mitten in der Recherche. Eine Zeile, die sich ohne weitere Angabe
nicht planen lässt, bekommt in der Tabelle den Vermerk „offen" und eine Angabe,
was fehlt. Das ist ein gültiges Ergebnis, kein Versäumnis.

### Die Partnerlisten sind Hinweis, nicht Beleg

DENA-Checkliste und Fensterliste füllt ein Vor-Ort-Partner aus — unter Zeitdruck,
oft am Handy, manchmal aus dem Gedächtnis nach dem Termin. Dasselbe gilt für die
hochgeladene Bauteilliste selbst. Sie sind die wichtigste Einzelquelle, die du
hast, und trotzdem regelmäßig an einzelnen Stellen falsch. Nimm sie ernst **und**
prüf sie gegen.

Fünf Gegenproben, die sich beim Planen nebenbei machen lassen:

| woran | was stutzig macht |
|---|---|
| Baujahr gegen Verglasung | „3-fach" oder U 0,9 an einem Haus von 1970 — entweder saniert, oder das falsche Feld angekreuzt |
| Gesamtdicke gegen Schichten | 24 cm Ziegel + 12 cm Dämmung, aber die Wand misst 36,5 cm |
| Zeilenzahl gegen Gebäude | 14 Fenster in der Liste, im Aufmaß stehen 7 |
| Liste gegen Foto | „verputzt" angekreuzt, auf dem Fassadenbild liegt Klinker |
| unbeantwortete Felder | „Ja / ?" ist kein Ja. Ein Fragezeichen neben dem Haken heißt: niemand hat nachgesehen |

**Einen Widerspruch entscheidest du nicht.** Die Zeile bleibt auf dem Wert der
Liste, und was dir auffällt, kommt in `planungshinweis` und in die Liste der
offenen Punkte — beim Namen, mit beiden Quellen. Eine Planung, die den Partner
stillschweigend überstimmt, ist schlimmer als eine, die seinen Fehler übernimmt:
den Fehler findet jemand, die stille Korrektur nicht.

Was du **nicht** tust: einen Wert der Liste durch einen eigenen ersetzen, auch
wenn deiner plausibler ist. Eine Angabe aus der Liste ist eine Quelle, eine
Angabe statt der Liste ist eine Erfindung.

## 4 — Recherchieren

Je **Bauteilart**, nicht je Zeile — zwanzig Außenwandflächen brauchen eine
Suche, nicht zwanzig:

```
find_building_components { component_type: "Außenwand", construction_year: 1970,
                           postal_code: "51067",
                           query: "<was in `aufbau` steht>" }
```

Ein Baujahr, keine Baualtersklasse — die Klassen überlappen sich. Die PLZ
filtert nicht, sie hebt regional Passendes im Ranking an.

Bei ähnlich bewerteten Treffern `get_component_details` und die Schichtaufbauten
vergleichen. `similarity` ist ein Ranking-Signal, kein Qualitätsurteil — liegen
die vorderen dicht beieinander, ist die Wahl **nicht** entschieden. Dann nenn
beide und sag, welches Merkmal sie unterscheidet.

**Findet die Suche nichts**, erst breiter suchen: `construction` weglassen,
`include_typology_values: true` setzen. Das sind die baujahrtypischen Ansätze —
kein Schichtaufbau, nur ein U-Wert.

**Bleibt es leer**, führt der Katalog diese Bauteilart nicht. Am 21.09.2026
gemessen: Kellerwand 2 Zeilen, Wand gegen unbeheizt 2 Zeilen, beide nur Neubau
mit U 0,30 — gegenüber 1.597 Zeilen für die Außenwand. Dann:

1. `get_typical_u_value` für den baujahrtypischen Vergleichswert, und
2. einen Aufbau **vorschlagen** — Schichten, Stärken, Lambda, mit Quelle.

**Aber leg ihn nicht an.** `create_building_component` ist in diesem Ablauf
verboten. Der Vorschlag steht in der Tabelle und in der CSV, und der Berater
entscheidet, ob daraus ein Katalogeintrag wird.

## 5 — Die Planungstabelle

**Zweiter Haltepunkt.** Je Bauteilart eine Zeile, und je Zeile die Begründung:

```
Bauteilart    Bezeichnungen         m²      Vorschlag                        U      Gestützt auf
Außenwand     AW Nord, AW Ost, …   207,1   AW Ziegel 24 + KS-Verblender     1,25   Notiz „Klinker" + Baujahr
                                           (Katalog 422, geprüft)
Dach          DA 01                 85,3   DA Warmdach Stahlbeton + Kies    0,68   Notiz „Flachdach, Kies"
                                           (Katalog 8113, geprüft)
Kellerwand    KW 01–06              83,6   NEU ANZULEGEN: Stahlbeton 30 cm  3,84   Baubeschreibung „30 cm Beton"
                                           (Katalog führt nur Neubau 0,30)
Fenster       F 01–14               28,4   offen                             —     Fensterliste fehlt
```

Vier Regeln für diese Tabelle:

- **Gestützt auf** ist Pflicht und nennt die Quelle in der Datei oder im
  Gespräch. „Passt gut" ist keine Begründung.
- **Ungeprüfte Katalogtreffer kennzeichnen.** Jeder Treffer trägt
  `is_verified`. Steht dort `false`, hat den Aufbau jemand über MCP eingetragen
  und kein Mensch abgenommen — brauchbar, aber kein Katalogwert. Schreib
  „ungeprüft" dahinter, nicht „geprüft".
- **Keine Zahl erfinden.** Kein g-Wert, keine Schichtstärke, keine Fläche. Und
  **schlag auch keine vor**, um sie bestätigen zu lassen: „Soll ich 0,75
  ansetzen?" führt dazu, dass deine Zahl in der Planung steht. Fehlt etwas, heißt
  die Zeile „offen".
- **Summiere keine Flächen, die du nicht hast.** Stand in der Datei keine
  m²-Spalte, bleibt die Spalte leer. Eine Aufteilung, die auf eine plausible
  Summe aufgeht, sieht aus wie eine Messung.

Frag, ob die Wahl so stimmt — je Bauteilart einzeln, wenn es mehr als drei sind.
Der Berater darf tauschen, streichen und ergänzen.

## 6 — Die Datei zurückgeben

Dieselbe Liste, dieselbe Zeilenreihenfolge, dieselben Spalten — plus diese vier
am Ende:

| neue Spalte | Inhalt |
|---|---|
| `geplantes_bauteil` | Name des Katalogeintrags, oder „NEU ANZULEGEN: …", oder „offen" |
| `katalog_id` | die `component_id`, leer bei „neu" und „offen" |
| `u_wert_geplant` | der U-Wert des Vorschlags |
| `planungshinweis` | worauf es sich stützt, und was fehlt |

**Die Originalspalten bleiben unverändert** — auch die, die du nicht verwendet
hast. Der Berater legt die Datei ab und arbeitet später damit weiter; eine
umsortierte oder gekürzte Liste ist für ihn eine neue Datei, keine ergänzte.

Zahlen mit Dezimalkomma zurückschreiben, wie sie hereinkamen. Als Trennzeichen
das der Eingabedatei — deutsche Excel-CSVs nutzen das Semikolon, und eine mit
Komma getrennte Datei öffnet sich dort als eine einzige Spalte.

Gib die Datei aus **und** zeig die Planungstabelle im Gespräch. Beides, nicht
eines statt des anderen.

Am Schluss die gebündelte Liste dessen, was offen ist — als Arbeitsauftrag
formuliert, nicht als Frage:

```
Damit die Planung vollständig wird, fehlt:
· Fensterliste (14 Fenster, ohne sie keine Verglasung und kein Rahmen)
· Bestätigung, ob die Kellerwand Außendämmung hat (Checkliste sagt „Ja / ?")
· Schichtstärke des Dachaufbaus (Notiz nennt nur „Kies")
```

---

## Die Fallen

**Erdberührt sieht falsch aus und ist richtig.** Eine Kellerwand gegen Erdreich
rechnet mit Rse = 0 — es gibt keine Außenluft, an die sie abgibt. 30 cm Beton
ergeben so U 3,84, nicht 3,2. Den Abzug übers Erdreich rechnet die Bilanz
später selbst. Mindere den Wert nicht ab, und setz ihm keinen Pauschalwert wie
1,0 entgegen, weil er dir zu hoch vorkommt.

**Die Angrenzung steckt nicht im Bauteil.** Ob eine Kellerwand ans Erdreich, an
einen unbeheizten Nachbarkeller oder an einen beheizten grenzt, ändert den
U-Wert des Aufbaus nicht — es ändert, was die Bilanz daraus macht. Steht in der
Liste „Kellerwand" ohne Angabe wohin, ist das ein Punkt für die Liste der
offenen Fragen, keine Entscheidung von dir.

**Netto und brutto.** Fenster und Türen sind aus der Wandfläche herausgerechnet.
Eine Wand von 11,38 m² geht mit 8,60 m² in die Bilanz. Steht in der Datei nur
eine Zahl, frag welche es ist, statt es zu deuten.

**Typologiewerte haben keinen Aufbau.** Sie tragen die Lage, die
Baualtersklasse und einen U-Wert, sonst nichts. Dokumentier bei ihnen keine
Schichten — es gibt keine, und eine erfundene Schichtfolge liest sich hinterher
wie eine Aufnahme.

**Eine Angabe aus der Liste bleibt in der Liste.** Auch wenn du sie für falsch
hältst — du vermerkst den Zweifel, du überschreibst ihn nicht. Siehe „Die
Partnerlisten sind Hinweis, nicht Beleg" in Schritt 3.

**Der Katalog ist nicht der Bestand des Gebäudes.** Ein Treffer beschreibt, wie
Häuser dieses Jahrgangs in dieser Gegend gebaut wurden — nicht, wie dieses
gebaut wurde. Was der Berater vor Ort gesehen hat, schlägt jeden Katalogtreffer.

---

## Wenn etwas schiefgeht

**Die Datei lässt sich nicht lesen.** Sag, woran es liegt, und bitte um CSV.
Rate nicht aus dem Dateinamen, was drinstehen könnte.

**Die Liste passt nicht zum Gebäude** — etwa 40 Zeilen für ein
Einfamilienhaus, oder eine Bauteilart, die es dort nicht geben kann. Sag es,
bevor du planst. Womöglich ist es die Liste eines anderen Projekts.

**Der Nutzer will, dass du schreibst.** Dieser Ablauf plant. Verweis auf
`hottgenroth-bauteile` und übergib die Planung — der andere Skill braucht
ohnehin seine eigenen drei Freigaben, und die kann dieser hier nicht
vorwegnehmen.
