---
name: hottgenroth-bauteile
description: Bauteile für ein Hottgenroth-Projekt recherchieren, einspielen und den Flächen zuweisen — in zehn Schritten, mit Freigabe des Nutzers an drei Stellen. Auslöser: Bauteile zuweisen, Aufbauten einspielen, Außenwand/Dach/Fenster zuordnen, "die Flächen tragen noch U-Wert direkt", Partnermodell befüllen, baujahrtypische Ansätze setzen, Bauteilrecherche, "der Katalog hat dafür nichts", eigenes Bauteil anlegen.
---

**Stand:** Erprobt am 20.09.2026 an einem echten Partnermodell — Spiegel, Katalog
anlegen, Zuweisung in beide Repositories, schichtlose Bauteile. Der Arbeitsplatz
muss auf 2.5.0 oder neuer laufen.

**Neu am 21.09.2026, noch nicht im vollen Durchlauf erprobt:** Schritt 5a — eigene
Bauteile anlegen, wenn der Katalog die Bauteilart nicht führt. Der Aufruf selbst
ist an einer Kellerwand belegt (Eintrag 100000, U 3,84 aus den Schichten
gerechnet); was danach kommt — zuweisen, Wirkung im Modell — ist für ein selbst
angelegtes Bauteil noch nicht gemessen. Behandle es entsprechend: mehr zeigen,
weniger behaupten.

## Worum es geht

Ein Partner liefert das HottCAD-Modell als `.sqproj`. Alle Flächen sind
gezeichnet, aber sie tragen nur die Platzhalter des Zeichners — in der
Bauteilliste steht bei jedem Eintrag „U-Wert direkt" und ein runder Wert wie 0,24
oder 1,30. Die echten Aufbauten fehlen.

Dieser Ablauf bringt sie hinein. **Er verändert das Kundenprojekt auf dem Rechner
des Beraters**, deshalb gibt es drei Haltepunkte: nach der Recherche, nach der
Zuordnung, und vor dem Schreiben.

**Drei Haltepunkte heißt nicht drei Fragen.** Am ersten fragst du je Bauteilart
einzeln — bei drei Arten sind das drei Fragen an einem Haltepunkt. Die
Projektwahl aus Schritt 1 zählt nicht dazu.

**Eine Formatregel, keine Ermahnung: in Text an den Berater steht nie eine GUID.**
Nicht ganz, nicht gekürzt, nicht mit Auslassungspunkten. Flächen heißen
`EW 003 (Küche, EG)`, Projekte heißen bei ihrem Namen. Enthält ein Satz, den du
schreiben willst, eine Zeichenfolge aus Blöcken mit Bindestrichen, ist der Satz
falsch formatiert — unabhängig davon, ob die Zeichenfolge stimmt. Wer sie nennen
will und sie nicht gelesen hat, schreibt „Kennung liegt vor".

In **Werkzeugargumenten** ist es umgekehrt: dort wird die `element_uid`
unverändert aus der Antwort durchgereicht, nie aus dem Gedächtnis, nie
abgekürzt. Kopieren, nicht wiedergeben.

---

## 1 — Projekt wählen

`get_hottgenroth_components` **ohne** `projekt` listet die eigenen Projekte.
Zeig die **letzten zehn** nach Bearbeitungsdatum und frag, welches gemeint ist.

Fehlt das gesuchte, ist es meist nur die Liste: `update_hottgenroth_projects`
holt sie frisch vom Rechner. Sag nicht „gibt es nicht", ohne das getan zu haben.

## 2 — Die Bauteile auflisten

Erst den Spiegel frisch holen, denn die Liste ist Tage alt sein kann:

```
refresh_hottgenroth_components { projekt: "…" }     → 20-30 s warten
get_hottgenroth_components     { projekt: "…", quelle: "gebaeude", nur_huelle: true }
```

**Erst auswerten, wenn `stand.letzter_abruf.status` „uebernommen" ist.** Vorher
zeigt der Spiegel den vorigen Stand.

Zeig dem Nutzer, was das Gebäude hat: je Kennung Anzahl, Fläche und den
angesetzten U-Wert. Steht überall „U-Wert direkt", ist das der Normalfall bei
einem frischen Partnermodell — kein Fehler, sondern der Grund für diesen Ablauf.

## 3 — Nach den Quellen fragen

Ohne Material keine Recherche. Frag nach, was vorliegt, und nenne dabei, wonach
du suchst:

**Bilder** — Außenwand, Dach, Fenster. Die liegen in Google Drive beim
Vor-Ort-Termin; dafür gibt es den Skill `gdrive`. Ein Foto der Fassade
entscheidet oft allein, ob eine Wand zweischalig mit Verblender ist oder verputzt.

**Unterlagen** — Baubeschreibung, DENA-Checkliste, Fensterliste, Grundrisse.
Ebenfalls im Drive. **Checkliste und Fensterliste füllt der Vor-Ort-Partner aus,
und sie sind nicht immer richtig** — mehr dazu in Schritt 4. Ausgefüllte Fragebögen stehen daneben in der App:
`list_fragenkataloge { suche: "<Projekt oder Mailadresse>" }`, dann
`get_fragenkatalog { id }`. Das Vor-Ort-Protokoll mit Etagen, Räumen und Fenstern
holst du über `list_vor_ort_termine` → `get_vor_ort_termin` →
`get_vor_ort_protokoll`.

**Eckdaten** — Baujahr, PLZ, Ort, Gebäudetyp. `get_project` liefert sie aus dem
FS-Projekt, wenn es eines gibt.

## 4 — Prüfen, ob es reicht

Bevor du suchst, halte gegen:

| brauchst du für | ohne das geht nicht |
|---|---|
| **Baujahr** | jede Suche — es ist das wichtigste Filterkriterium |
| Bild oder Beschreibung der Wand | die Wahl zwischen ein- und zweischalig |
| Dachfoto oder Beschreibung | Steildach gegen Flachdach, Aufbau |
| Fensterliste | Verglasung, Rahmen, g-Wert |
| Baubeschreibung mit Schichten | ein Bauteil, das der Katalog nicht führt (Schritt 5a) |

**Fehlt das Baujahr, such nicht — frag danach.** Fehlen Fensterliste, DENA-Liste
oder Grundrisse, sag das und **halte an**, statt zu raten. Ein falsch gewählter
Aufbau fällt später kaum auf: der Katalogname klingt immer plausibel.

Prüffrage vorher: Steht die Antwort im Material, das schon da ist? Dann hol sie
heraus, statt zu fragen.

### Die Partnerlisten sind Hinweis, nicht Beleg

DENA-Checkliste und Fensterliste füllt ein Vor-Ort-Partner aus — unter Zeitdruck,
oft am Handy, manchmal aus dem Gedächtnis nach dem Termin. Sie sind die wichtigste
Einzelquelle, die du hast, und sie sind trotzdem regelmäßig an einzelnen Stellen
falsch. Nimm sie ernst und prüf sie gegen, statt eines von beidem.

Fünf Gegenproben, die sich ohne Rückfrage machen lassen:

| woran | was stutzig macht |
|---|---|
| Baujahr gegen Verglasung | „3-fach" oder U 0,9 an einem Haus von 1970 — entweder saniert, oder das falsche Feld angekreuzt |
| Gesamtdicke gegen Schichten | 24 cm Ziegel + 12 cm Dämmung, aber die Wand misst 36,5 cm |
| Liste gegen Modell | 14 Fenster in der Liste, 7 Fensterflächen im Spiegel |
| Checkliste gegen Foto | „verputzt" angekreuzt, auf dem Fassadenbild liegt Klinker |
| unbeantwortete Felder | „Ja / ?" ist kein Ja. Ein Fragezeichen neben dem Haken heißt: niemand hat nachgesehen |

**Findest du einen Widerspruch, entscheide ihn nicht.** Nenn beide Quellen und
frag — am ersten Haltepunkt, zusammen mit dem Bauteil. „Die Fensterliste sagt
Zweifachverglasung, das Baujahr 1970 passt dazu, aber auf dem Foto sitzen breite
Kunststoffrahmen — sind die Fenster getauscht worden?" ist eine beantwortbare
Frage. Stillschweigend die Liste zu überschreiben ist das Schlimmste, was du tun
kannst: dann steht eine Zahl im Projekt, die weder der Partner noch der Berater
je gesehen hat.

Und umgekehrt gilt weiter: Eine Angabe **aus** der Liste ist eine Quelle, eine
Angabe **statt** der Liste ist eine Erfindung.

## 5 — Recherchieren und zeigen

Je Bauteilart:

```
find_building_components { component_type: "Außenwand", construction_year: 1970,
                           postal_code: "51067",
                           query: "<was tatsächlich vorgefunden wurde>" }
```

Ein Baujahr, keine Baualtersklasse — die Klassen überlappen sich. Die PLZ filtert
nicht, sie hebt regional Passendes im Ranking an.

Gibt es die Bauteilart nur als Typologie (Innenwand, Kellerwand, Wand gegen
unbeheizt, Fenster) oder findet die Suche nichts: `include_typology_values: true`.
Das sind die baujahrtypischen Ansätze — kein Schichtaufbau, nur ein U-Wert. Sie
lassen sich genauso zuweisen; dokumentiere dann keine Schichten, es gibt keine.

Bei ähnlich bewerteten Treffern `get_component_details` und den Schichtaufbau
vergleichen. `similarity` ist ein Ranking-Signal, kein Qualitätsurteil — liegen
die vorderen dicht beieinander, ist die Wahl **nicht** entschieden. Dann frag nach
einem unterscheidenden Merkmal, statt den ersten zu nehmen.

**Bei Fenstern:** seit dem 21.09.2026 tragen **alle 874** Fenster des Katalogs
g-Wert und Rahmenanteil, die Typologiewerte eingeschlossen. Die alte Hürde
„Fenster ohne g-Wert" gibt es für Katalogtreffer nicht mehr, und `fenster_ohne_g_wert`
kann dir dort nicht mehr begegnen. Sie kehrt genau dann zurück, wenn du selbst ein
Fenster über `create_building_component` anlegst — dort ist `g_value` Pflicht, und
die Regel in Schritt 6 gilt unverändert. Türen brauchen keinen; von den 36 im
Katalog trägt keine einen.

Zeig je Bauteilart die Kandidaten mit U-Wert, Aufbau und Quelle — und sag dazu,
worauf du deine Empfehlung stützt. Trägt ein Treffer `is_verified: false`, gehört
das in dieselbe Zeile: er ist brauchbar, aber von niemandem abgenommen (siehe
„Die Fallen").

## 5a — Wenn der Katalog nichts führt

Manche Bauteilarten sind fast leer. Am 21.09.2026 in Produktion gezählt:
**Kellerwand 2 Zeilen, Wand gegen unbeheizt 2 Zeilen** — beide Male nur
Neubauwerte mit U 0,30 und ohne Aufbau, gegenüber 1.597 Zeilen für die Außenwand.
Für ein Kellergeschoss von 1970 steht dort nichts. Das ist keine Baujahrlücke,
sondern eine Artenlücke: bei diesen Lagen hilft auch `include_typology_values`
nicht weiter.

Dafür gibt es `create_building_component`. Es legt einen eigenen Eintrag im
FS-Katalog an, der sich danach wie jeder andere zuweisen lässt.

```
create_building_component { name: "Kellerwand Stahlbeton 30 cm, ungedämmt",
                            component_type: "Kellerwand",
                            year_from: 1950, year_to: 1978,
                            layers: [ { material: "Stahlbeton",
                                        thickness_cm: 30, lambda: 2.3 } ],
                            sources: "<woher die Angaben stammen>",
                            notes: [ "<was du angenommen hast>" ] }
```

**Erst suchen, dann anlegen.** Null Treffer heißt fast immer „zu eng gefiltert".
Lass `construction` weg, setz `include_typology_values: true`, such erneut. Erst
wenn auch das leer bleibt, ist der Katalog wirklich leer.

**Du legst einen Vorschlag an, keinen Beleg.** Jede Schicht kommt aus den
Unterlagen — Baubeschreibung, Checkliste, Aufmaß, Foto. Fehlt eine Stärke oder
ein Lambda, frag danach. Ein erfundener Aufbau rechnet sich genauso glatt wie ein
richtiger, und im Datenblatt sieht man ihm nichts an. Was du annehmen musstest,
gehört in `notes` und `sources` — das ist das Erste, was der Prüfende liest.

**Es gibt keinen Probelauf.** Anders als bei `add_components` schreibt der Aufruf
sofort. Zeig dem Berater den Aufbau vorher und hol seine Zusage — am ersten
Haltepunkt, zusammen mit der Bauteilwahl.

**Gib `u_value` nicht mit.** Ohne ihn rechnet der Dienst aus den Schichten nach
DIN EN ISO 6946, mit den Übergangswiderständen der Bauteilart — und genau die
braucht Hottgenroth später auch. Eine eigene Zahl überschreibt diese Rechnung;
setz sie nur, wenn sie belegt ist. Bei Fenstern und Türen ist sie dagegen Pflicht,
denn dort gibt es keine Schichten.

**Ändern und Löschen gibt es nicht.** Kein Update, kein Delete über die
Schnittstelle — ein falscher Eintrag muss von einem Menschen unter
`/bauteilkatalog/<id>` berichtigt werden. Sag das, wenn du dich korrigieren musst.
Gleicher Name und gleiche Bauteilart werden mit `bauteil_existiert_bereits`
abgewiesen; ein zweiter Versuch nach einem Abbruch ist also gefahrlos.

**Nicht für jede Lage.** „Boden gegen außen" gibt es als Bauteilart gar nicht —
weder anlegen noch zuweisen. Solche Flächen bleiben aus dem Lauf heraus; sag es,
statt ersatzweise „Fußboden" zu nehmen, denn der steht für erdberührt und rechnet
mit anderen Übergangswiderständen.

## 6 — Der Nutzer nimmt die Bauteile an

**Erster Haltepunkt.** Pro Bauteilart eine eigene Frage, nicht alle auf einmal:

> **Außenwand** — „AW Ziegel 24 + KS-Verblender 11,5 (Bestand 1970)", U 1,08
> Aufbau: Innenputz · HLz 24 · Mörtel · KS-Verblender 11,5
> Gestützt auf: Fassadenfoto (sichtbarer Verblender) und Baubeschreibung
> Passt das?

Warte die Antwort ab, dann die nächste Art.

**Willst du ein Bauteil selbst anlegen (Schritt 5a), gehört der Entwurf in diese
Frage** — Schichten, Stärken, Lambdas und woher sie stammen. Nicht „ich lege eine
Kellerwand an", sondern die Zeilen, die eingetragen werden. Nach dem Ja schreibt
der Aufruf sofort, ein Probelauf fängt dort nichts mehr ab.

Brauchst du für ein selbst angelegtes Fenster einen g-Wert, frag ihn hier mit ab —
**und schlag keine Zahl vor.** „Soll ich 0,75 ansetzen?" erfüllt den Buchstaben der
Regel und verfehlt ihren Sinn: der Berater winkt eine genannte Zahl
erfahrungsgemäß durch, und dann steht dein Wert im Projekt. Zulässige Quellen sind
die Fensterliste, eine Herstellerangabe oder das Typenschild — nichts, was aus dir
selbst kommt. Trägt die Fensterliste einen Wert, der nicht zum Baujahr passt, nimm
ihn trotzdem nicht einfach als falsch an: sag, was dir auffällt, und lass den
Berater entscheiden.

Hat auch der Berater den Wert nicht, ist der erste Ausweg inzwischen fast immer
der richtige: **nimm ein Katalogfenster**, alle 874 tragen einen g-Wert. Sonst
bleiben zwei: die Fenster aus diesem Durchgang herausnehmen und den Rest
schreiben, oder anhalten, bis die Fensterliste da ist.

## 7 — Die Zuordnung vorbereiten

Jetzt erst die Flächen holen — mit den Angaben, mit denen ein Mensch sie
wiedererkennt:

```
get_hottgenroth_components { projekt: "…", quelle: "gebaeude",
                             flaechen_einzeln: true, kennung: "AW" }
```

Jede Zeile nennt `zeichnungsobjekt`, `raum` und `geschoss`. Eine gezeichnete Wand
zerfällt in Teilflächen — „EW 003", „EW 003-2", „EW 003-3" gehören zusammen.
`zeichnungsobjekte` in der Antwort sagt, welche es gibt.

Bau daraus eine **Zuordnungsvorlage**, gruppiert nach Zeichnungsobjekt:

```
Bauteil                              Zeichnungsobjekt  Teilfl.  m²     Geschoss
AW Ziegel 24 + KS-Verblender 11,5    EW 003                  3   14,0  EG
                                     EW 004                  3   33,0  EG
                                     EW 010                  4   41,6  DG
                                     …                      22  207,1
DA Warmdach Stahlbeton + Kies        Dach 001                9   85,3  DG
BE Typologie 1969-1978               Ground Basement 002     5   ...   Keller
```

**Sprich über Zeichnungsobjekte, nicht über GUIDs.** „EW 003 (Küche,
Wohnungsflur, WC-Raum, Erdgeschoss)" ist beantwortbar, eine GUID nicht.

**Und füll keine Spalte, die die Antwort nicht hergibt.** Liefert sie nur Anzahl
und Summe je Kennung, bleiben Teilflächen und Quadratmeter leer oder die Zeile
nennt nur die Summe. Eine Aufteilung, die auf die Gesamtsumme aufgeht, sieht aus
wie eine Messung — und wird ungeprüft bestätigt.

## 8 — Der Nutzer bestätigt oder ergänzt

**Zweiter Haltepunkt.** Zeig die Vorlage und frag, ob sie so stimmt. Er darf
Flächen herausnehmen, verschieben oder welche ergänzen, die du nicht zugeordnet
hast.

**Rate nichts.** Welche Wand welchen Aufbau hat, weiß der Berater. Bleibt eine
Fläche ohne Bauteil, ist das eine Entscheidung und kein Versäumnis — sag es und
lass sie weg.

## 9 — Zusammenfassung und Freigabe

**Dritter Haltepunkt, der letzte vor dem Schreiben.**

> Einspielen und zuweisen würde ich:
> · Außenwand · AW Ziegel 24 + KS-Verblender · 22 Flächen · 207 m²
> · Dach · DA Warmdach Stahlbeton + Kies · 9 Flächen · 85 m²
> · Bodenplatte · BE Typologie 1969-1978 · 12 Flächen · 143 m²
> Drei Bauteile, 43 Flächen. Das Projekt wird dabei verändert. Soll ich?

Nach der Zusage **zuerst der Probelauf** — er rechnet durch und schreibt nichts:

```
add_components { projekt: "…", probelauf: true, zuordnungen: [ … ] }
get_vorgang    { vorgang_id }
```

Im Protokoll stehen die gerechneten U-Werte. **Gib sie dem Berater aus**, bevor
du ohne `probelauf` aufrufst — nicht nur für dich selbst prüfen. Das ist eine
Anzeige, kein vierter Haltepunkt: du wartest nicht auf eine weitere Zusage. Weicht
ein Wert allerdings vom Katalogwert ab, frag nach, statt ihn durchzuwinken.

Danach derselbe Aufruf ohne `probelauf`.

## 10 — Erfolg belegen

**„Erledigt" am Vorgang heißt nicht „angekommen".** Der Nachweis ist der Spiegel:

```
refresh_hottgenroth_components  →  20-30 s  →  get_hottgenroth_components
```

**Auch hier gilt: erst auswerten, wenn `stand.letzter_abruf.status`
„uebernommen" ist.** Wer nur wartet und den Status nicht prüft, liest womöglich
den Stand von VOR dem Schreiben und meldet einen Fehlschlag, den es nicht gibt.
Steht dort nach dem Warten etwas anderes, noch einmal 30 Sekunden warten und
erneut lesen; beim dritten Mal sag es dem Berater, statt weiter zu pollen.

Zeig die **neue Bauteilliste** und stell sie der alten gegenüber: wo vorher
„U-Wert direkt" stand, steht jetzt der Aufbau mit seinem U-Wert. Erst das ist der
Erfolg.

Die Software zeigt neue Katalogbauteile übrigens erst nach einem Neustart — sag
das dazu, wenn der Berater gleich nachsehen will.

---

## Die Fallen

**Ungeprüfte Bauteile musst du kenntlich machen.** Jeder Suchtreffer trägt
`is_verified`. Steht dort `false`, hat den Aufbau jemand über
`create_building_component` eingetragen und noch kein Mensch abgenommen —
brauchbar als Anhaltspunkt, aber kein Katalogwert. Sag es, bevor der Berater ihn
übernimmt, und nenne, wer ihn angelegt hat (`verification.created_by`). Geht das
Ergebnis in eine Unterlage, die das Haus verlässt, such mit `only_verified: true`.
Das gilt auch für Bauteile, die du selbst im selben Gespräch angelegt hast —
gerade für die.

**Erdberührt: der Katalogwert ist der nackte Bauteilwert.** Eine Kellerwand gegen
Erdreich rechnet mit Rse = 0 — es gibt keine Außenluft, an die sie abgibt. 30 cm
Beton ergeben so U 3,84, nicht 3,2. Das sieht falsch hoch aus und ist richtig: den
Abzug übers Erdreich rechnet die Bilanz selbst. Mindere den Wert nicht zusätzlich
ab, und setz ihm keinen Pauschalwert wie 1,0 entgegen, weil er dir zu hoch
vorkommt.

**Die Angrenzung hängt an der Fläche, nicht am Bauteil.** Ob eine Kellerwand ans
Erdreich, an einen unbeheizten Nachbarkeller oder an einen beheizten grenzt,
entscheidet sich am Element — ein einziger Katalogeintrag kann alle tragen, und
`add_components` ändert daran nichts. Bevor du erdberührte Flächen bestückst:
Angrenzung je Fläche ansehen und den Berater fragen, wenn mehrere Flächen
dieselbe tragen, obwohl sie unterschiedlich liegen. Eine Kellerwand zum
Nachbarkeller, die wie Erdreich gerechnet wird, treibt die Heizlast nach oben,
ohne dass irgendwo eine Fehlermeldung steht.

**Die Software muss zu sein.** Eine offene Hottgenroth-Anwendung hält das Projekt
im Speicher und schreibt ihren Stand beim Beenden zurück — die Zuweisung wäre
dann still fort. Der Auftrag prüft das und bricht ab.

`software_schliessen: "verwaiste"` darfst du selbst setzen: ein Prozess ohne
Fenster gilt für den Menschen davor ohnehin als beendet. **`"alle"` beendet ein
offenes Fenster — das ist seine Arbeitsumgebung. Frag ihn.** Häufigster Fall:
`Building3D` hängt mit dem Fenster „Schichtaufbau" hinterher, nachdem der
EE-Berater geschlossen wurde.

**Ein zweiter Aufruf legt alles doppelt an, und Löschen geht über die
Schnittstelle nicht.** Bricht etwas ab, vor dem Wiederholen immer
`get_vorgang({vorgang_id})`:

- `geschrieben: false` — nichts passiert, Wiederholen ist gefahrlos
- `geschrieben: "ungewiss"` — **nicht wiederholen**, erst nachsehen, was im
  Projekt steht
- `geschrieben: true` — durchgelaufen

### Wiederanlauf nach einem Abbruch

Bei `geschrieben: "ungewiss"` reicht „erst nachsehen" nicht — hier ist der Weg:

1. `refresh_hottgenroth_components`, auf „uebernommen" warten, dann
   `get_hottgenroth_components` mit `flaechen_einzeln: true` und `kennung`. Nur
   so siehst du **je Fläche**, welche den Aufbau schon trägt und welche noch
   „U-Wert direkt" zeigt. Der Vorgang selbst kann es dir nicht sagen.
2. Beziffere es: „11 von 24 tragen ihn bereits, 13 sind offen." Eine
   **Teilschreibung ist der Regelfall**, nicht die Ausnahme — ein Abbruch mitten
   in einer Anweisung über 24 Flächen hinterlässt typischerweise n von m. Die
   drei Werte false/ungewiss/true legen ein Alles-oder-nichts nahe, das es nicht
   gibt.
3. Kürze den Umfang auf die offenen Flächen.
4. **Leg diesen gekürzten Umfang noch einmal zur Freigabe vor.** Eine Zusage gilt
   für die Menge, über die gesprochen wurde. Sagt der Berater „das habe ich doch
   schon freigegeben", meint er den alten Umfang — sag ihm das und frag trotzdem.
   Umgekehrt ist seine alte Zusage auch kein Freibrief, den ganzen Lauf zu
   wiederholen.
5. Dann erst Probelauf und Schreiben.

Ein Katalogbauteil, das der abgebrochene Lauf schon angelegt hat, ist für die
Oberfläche trotzdem **neu** — auch dafür muss die Software einmal neu starten.

**Ein Fenster ohne g-Wert wird abgewiesen** (`fenster_ohne_g_wert`). Setz keinen
Vorgabewert ein: ein falscher g-Wert lässt die solaren Gewinne still auf null
fallen, und das fällt in keiner Bilanz auf.

**Ein U-Wert als Spanne wird nicht gemittelt** (`u_wert_mehrdeutig`). Steht im
Katalog „1,30 / 1,13", frag, welcher gilt.

**Wärmebrücken gehen nicht** (`bauteilart_ohne_weg`). Sie tragen Psi statt U und
haben im Gebäudemodell keine Fläche. Das ist eine geschlossene Antwort, kein
Fehler.

**Innenwände und Innentüren gehören nicht in eine Kostenrechnung.** Sie liegen
außerhalb der thermischen Hülle; ungefiltert ist die Fläche um den Faktor 1,14
bis 4,38 zu groß. `nur_huelle: true`, sobald es um Kosten geht.

## Wenn etwas schiefgeht

`get_vorgang({vorgang_id, protokoll: true})` zeigt Schritt für Schritt, woran es
lag. `diagnose` nennt die laufende Anwendung mit Fenstertitel und die
`agent_version`.

Ein Fenstertitel wie „Änderungen speichern?" ist etwas anderes als ein bloß
offenes Programm — sag, was du siehst, statt „die Software läuft".

Meldet der Arbeitsplatz eine Version vor 2.5.0, kennt er die schichtlosen
Bauteile nicht und antwortet mit „Jedes Bauteil braucht eine Liste 'schichten'".
Dann muss der Agent aktualisiert werden.

`arbeitsplatz_erreichbar: false` heißt, der Rechner hat sich seit über drei
Minuten nicht gemeldet. Der Auftrag bleibt liegen, bis er wieder da ist — sag
das, statt den Menschen warten zu lassen.
