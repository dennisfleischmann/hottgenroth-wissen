# Konzept: Hottgenroth-Bauteile in die FS-Bauteilliste aufnehmen

Die FS-App führt unter [`/bauteilkatalog`](../../routes/web.php) eine Bauteilliste:
856 Datenblätter aus dem Altbauatlas, regionaltypische Bestandsaufbauten mit
Schichten, Materialien und U-Werten. Die Hottgenroth-Installation bringt
8.427 Katalogbauteile mit. Dieses Papier beschreibt, welche davon in die Liste
gehören, welche nicht, und was dafür zu bauen ist.

> **Stand 11.09.2026.** Alle Zahlen sind ausgezählt, nicht geschätzt — die
> Hottgenroth-Seite aus `(localdb)\HSETU` (Modul 6.6.0), die FS-Seite aus
> `database/data/altbauatlas/datenblaetter.ndjson`. Der vollständige
> Hottgenroth-Bestand liegt als Arbeitsgrundlage in `Hottgenroth-Bauteile.xlsx`
> (erzeugt von [`bauteile/tools/Export-Bauteile.ps1`](../../bauteile/tools/Export-Bauteile.ps1)).

## Gebaut am 12.09.2026

Der Migrationspfad ist umgesetzt. Was in der App steht:

| | Zeilen | Wo |
|---|---:|---|
| Bestandsaufbauten | 143 | `altbauatlas_bauteile`, `rolle = bestand` |
| Zielaufbauten | 364 | dieselbe Tabelle, `rolle = ziel`, nur auf Anforderung sichtbar |
| Vergleichsband | 4.324 | `hottgenroth_typologie_uwerte` |
| Wärmebrücken | 467 | `waermebruecken` (354 mit Psi-Wert) |
| Bilder, entdoppelt | 1.437 | `altbauatlas_bilder`, 36,5 MB unter `database/data/hottgenroth/images/` |

Bedienbar unter `/bauteilkatalog` (mit Häkchen für Zielaufbauten),
`/waermebruecken` und `/vergleichsband`. Über MCP: `find_building_components`
mit `include_target_constructions` und `source`, der Typ `Wärmebrücke`, und das
neue Werkzeug `get_typical_u_value`.

Erzeugt wird der Datenstand von
[`bauteile/tools/Export-Katalog.ps1`](../../bauteile/tools/Export-Katalog.ps1),
eingelesen von `php artisan hottgenroth:import` (mit `--trocken` als
Trockenlauf). Die abgeleiteten Größen stehen in
[`KatalogDeutung`](../../app/Services/Hottgenroth/KatalogDeutung.php), die
Zusicherungen in `tests/Feature/Fs/HottgenrothKatalogTest.php` und
`HottgenrothImportTest.php`.

**Drei Dinge sind beim Bauen anders entschieden worden als geplant:**

*Das Vergleichsband erbt die sechs Bauteilarten nicht.* Geplant waren 3.060
Werte für die fünf abbildbaren Lagen; es sind 4.840 geworden, weil das Band
gerade die Lagen beantworten soll, die der Katalog nicht halten kann — 743
Fenster, 736 Innenwände, 59 Wände gegen unbeheizt, 51 Kellerwände.

*Der Teilkatalog `BauteileTypologie` ist draußen* — 516 Zeilen weniger im Band, 4.324 statt 4.840. Seine vier Sammlungen trugen Namen, die wie Dubletten der großen aussahen („EnEV 2015 - Typologie" neben „Deutschland -EnEV 2015-"), waren aber ein anderer Schnitt: **alle 516 ohne Gebäudetyp** und damit außerhalb des Rasters, das das Band ausmacht (Lage × Baualter × Gebäudetyp × Region); 112 auch ohne Jahresangabe. Wo sich vergleichen ließ, deckten sich rund 52 % der Werte mit der großen Sammlung. Entschieden am 12.09.2026.

*Der Titel wird nur bei 19 Bauteilen ergänzt, nicht bei 68.* Die Regel prüft
jetzt, ob der Name die Dachform schon nennt. „Holzkonstruktion" braucht den
Zusatz, „Sparrendach, geneigt, OD SpD 0,14" aus dem Neubaukatalog nicht.

---

## Entschieden am 11.09.2026

Die vier offenen Punkte aus Abschnitt 7 sind beantwortet. Sie stehen hier oben,
weil sie den Zuschnitt festlegen — der Rest des Papiers ist darauf gerechnet.

| | Entscheidung |
|---|---|
| **Nutzungsrecht** | **Ja.** Die Übernahme in die FS-Bauteilliste ist freigegeben. Damit ist Stufe 1 nicht mehr blockiert. |
| **Österreich** | **Ignorieren.** Kostet nichts: Die 715 abbildbaren österreichischen Bauteile sind ausnahmslos U-Wert-Zeilen ohne Aufbau. |
| **Steildach / Flachdach** | **Fest hinterlegt**, nicht abgeleitet — 16 Bauteile, alle eindeutig über die äußerste Schicht. Siehe 4./Stufe 1. |
| **Der Schnitt** | **Deutscher Bestand.** 143 Aufbauten in die Liste (Stufe 1), 3.060 U-Werte ins Vergleichsband (Stufe 2). |

---

## 1. Die beiden Seiten

### Die FS-Bauteilliste heute

| | |
|---|---|
| Tabellen | `altbauatlas_bauteile` + `_schichten`, `_u_werte`, `_plz`, `_bemerkungen`, `_bilder`, `_embeddings` |
| Primärschlüssel | die Original-ID der Quelle, **kein** Auto-Increment |
| `herkunft` | `altbauatlas` (Seeder-Besitz, wird bei jedem Crawl ersetzt) · `eigen` (von Hand, IDs ab 100000) |
| Bauteilarten | genau sechs: Steildach, Flachdach, Decke, Kellerdecke, Fußboden, Außenwand |
| Suche | zweistufig — SQL filtert (Bauteilart, Baujahr überlappend, Konstruktion), das Embedding rankt |
| Verbraucher | die Seite `/bauteilkatalog`, die MCP-Werkzeuge `find_building_components` / `get_component_details` / `add_component_to_project`, und `fs_projekt_bauteile` |

Zwei Eigenschaften dieses Aufbaus sind für alles Weitere entscheidend:

**Jedes der 856 Datenblätter hat einen Schichtaufbau.** Ohne Ausnahme. Das
Formular für eigene Bauteile erzwingt es ebenfalls (`schichten` → `required|min:1`).
Der Aufbau ist nicht Beiwerk, er ist der Inhalt: Der
[`EmbeddingTextBuilder`](../../app/Services/Altbauatlas/EmbeddingTextBuilder.php)
lässt Bauteilart, Konstruktion und Baualter bewusst **aus** dem Vektor heraus —
die stehen schon im SQL-Filter. Übrig bleibt als unterscheidende Substanz fast
nur die Schichtfolge. Genau daran hängt der Mehrwert gegenüber einer
LIKE-Suche: „Verblendmauerwerk" in der Anfrage findet auch „Klinker".

**`fs_projekt_bauteile` ist schon quellenoffen gebaut.** Die Spalte
`katalog_quelle` trägt heute `altbauatlas`, und im Migrationskommentar steht
wörtlich *„spaeter z.B. 'hottgenroth' als getrennte Retrieval-Quelle"*. Die
Architektur ist also vorgedacht; es fehlt der Inhalt und die Zuleitung.

### Was Hottgenroth mitbringt

| Bestand | Menge | Wo |
|---|---|---|
| ausgelieferter Bauteilkatalog | 8.427 | `HsetuAppTimData`, Arbeitsplatz |
| „Meine Bauteile" | 12 | `HsetuUsrData`, Arbeitsplatz |
| Bauteile in Projekten | 9.333 | `HsetuPrjData` — **schon gespiegelt** in `hottgenroth_bauteile` |

Die dritte Zeile ist leicht zu übersehen und die wichtigste: Der Weg vom
Arbeitsplatz an den Server existiert bereits. `bauteile.export` holt den
Bauteilbestand eines Projekts über vier lesende `sql.query`-Schritte ab, ohne
dass am Agenten etwas zu ändern wäre (siehe
[`HottgenrothBauteilSync`](../../app/Services/HottgenrothBauteilSync.php)).

---

## 2. Der Befund, der den Zuschnitt bestimmt

Die sechs Bauteilarten der FS-Liste sind ein harter Filter. Hottgenroth
beschreibt ein Bauteil dagegen über zwei Zahlen — `GroupType` (Wand, Dach,
Decke …) und `UsageType` (die Angrenzung). Beide sind im ausgelieferten Katalog
gefüllt, die Abbildung ist also möglich. Sie ist aber nicht vollständig:

| FS-Bauteilart | Altbauatlas heute | Hottgenroth abbildbar | davon **mit** Schichtaufbau |
|---|---:|---:|---:|
| Außenwand | 340 | 1.851 | 610 |
| Steildach + Flachdach | 161 | 925 &nbsp;*(nicht getrennt)* | 133 |
| Decke | 157 | 768 | 36 |
| Kellerdecke | 172 | 928 | 56 |
| Fußboden | 26 | 199 | 60 |
| **Summe** | **856** | **4.671** | **895** |

Und was gar nicht abbildbar ist — 3.756 Bauteile:

| | Menge | warum nicht |
|---|---:|---|
| Fenster und Verglasungen | 2.175 | die FS-Liste kennt keine Bauteilart dafür |
| Wärmebrücken | 467 | dito, und fachlich etwas anderes |
| Innenwände | 755 | keine Hüllfläche |
| Kellerwände (gegen Erdreich) | 101 | in den sechs Arten nicht vorgesehen |
| Wand gegen unbeheizt | 79 | dito |
| Türen | 55 | dito |
| Außenluftdurchlässe, Rollladenkästen, Nischen | 70 | Produkte, keine Aufbauten |
| Boden/Decke in Sonderlagen (4/1, 4/2) | 54 | dito |

**Drei Sätze fassen zusammen, worauf das hinausläuft:**

1. Nur **4.671 der 8.427** passen überhaupt auf die sechs Bauteilarten.
2. Von diesen 4.671 haben nur **895 einen Schichtaufbau** — im Altbauatlas
   haben **alle 856** einen. 81 % der Zugänge wären Zeilen ohne Aufbau.
3. Ein ungefilterter Import **versechsfacht** die Liste mit Material, das
   überwiegend von anderer Art ist als das, was drinsteht.

### Warum ein ungefilterter Import die Suche beschädigen würde

Das ist keine Geschmacksfrage, sondern folgt aus dem Code:

**Der Kandidatendeckel greift still.** `BauteilSucheService::kandidaten()`
begrenzt mit `->orderBy('id')->limit(400)` (`fs_projekt.suche.kandidaten_max`).
Heute ist das folgenlos — eine typische Anfrage (Außenwand, Baujahr 1974,
„massiv, zweischalig") ergibt 14 Kandidaten. Nach dem Import stünden allein
unter Außenwand 2.191 Zeilen; der Deckel würde regelmäßig greifen. Und weil
`candidate_count` **nach** dem Limit gezählt wird, sieht weder die KI noch der
Berater, dass abgeschnitten wurde. Schlimmer: `orderBy('id')` schneidet nach
ID-Band ab, also systematisch eine der beiden Quellen weg.

**Der Vektor wäre leer.** Für ein Bauteil ohne Schichten schrumpft der
Embedding-Text auf zwei Zeilen: `Bezeichnung: Innenwand` / `U-Wert: 3`. Solche
Zeilen ranken nicht schlecht — sie ranken *beliebig*, und sie verwässern die
Spreizung, aus der das Ranking seine Trennschärfe zieht.

**Bauteile ohne Baualtersklasse passen auf jede Anfrage.** Der Baujahrfilter
ist überlappend: `whereNull('baujahr_von')->orWhere(...)`. Ein Bauteil ohne
Jahresgrenzen matcht deshalb jede Suche. Die Typologie-Ordner tragen die Klasse
im Namen („TYPOLOGIE Bremen | 1919-1948 | Ein-/Zweifamilien-Reihenhaus"), die
Hersteller- und Neubaukataloge nicht.

**Die Quellenangabe stimmt dann nicht mehr.** `attribution()` liefert einen
einzigen Satz aus `config('altbauatlas.quelle')` für jedes Ergebnis. Sobald
Treffer aus zwei Quellen nebeneinander stehen, ist die Angabe je Zeile fällig.

---

## 3. Drei Arten von Inhalt, drei Behandlungen

Der Hottgenroth-Bestand ist nicht *ein* Ding, das man ganz oder gar nicht
übernimmt. Er zerfällt in drei, und jede will etwas anderes:

| | Was es ist | Menge | Vorschlag |
|---|---|---:|---|
| **A — Aufbauten** | echte Schichtkonstruktionen, gleicher Art wie ein Altbauatlas-Datenblatt | **143** | als reguläre Zeilen in die Liste |
| **B — Typologiewerte** | normative U-Werte je Baualtersklasse, Region und Gebäudetyp, ohne Aufbau | **3.060** | **nicht** als Katalogzeilen, sondern als Vergleichsband |
| **C — Übriges** | Fenster, Türen, Wärmebrücken, Produkte, Innenbauteile, Österreich, Neubau | 5.224 | vorerst draußen (siehe Stufe 4) |

Der Unterschied zwischen A und B ist der Kern des Konzepts. Ein
Altbauatlas-Datenblatt beantwortet: *„So ist diese Wand aufgebaut."* Ein
Typologiewert beantwortet: *„So viel verliert eine Wand dieses Jahrgangs
üblicherweise."* Das Erste wählt man aus, das Zweite schlägt man nach. In
dieselbe Tabelle geworfen, macht das Zweite das Erste unauffindbar.

---

## 4. Der Vorschlag

### Stufe 1 — Aufbauten mit Schichten in die Bauteilliste

**Was:** Hottgenroth-Bauteile mit Schichtaufbau, die auf eine der sechs
Bauteilarten passen, werden als reguläre Zeilen mit `herkunft = 'hottgenroth'`
aufgenommen.

**Das sind 143 Zeilen** — der deutsche Bestandsschnitt, entschieden am
11.09.2026. Wie er zustande kommt, ausgehend von den 4.671 abbildbaren:

| | Zeilen | |
|---|---:|---|
| deutsche Typologien, **mit Aufbau** | **143** | → Stufe 1 |
| deutsche Typologien und BauteileTypologie, nur U-Wert | 3.060 | → Stufe 2 |
| Österreich (Typologien + JoanneumResearch) | 715 | entfällt |
| Japan, UK Standard | 387 | entfällt |
| Neubau, Hersteller, Passivhaus | 364 | entfällt — Produkte, kein Bestand |
| ohne Katalogzuordnung | 2 | entfällt |

Bemerkenswert daran: **Österreich zu streichen kostet keinen einzigen Aufbau.**
Die 715 österreichischen Bauteile im abbildbaren Bereich sind ausnahmslos
U-Wert-Zeilen; alle 143 Aufbauten sind deutsch. Ebenso die Neubau- und
Herstellerkataloge — sie haben zwar 364 Aufbauten, aber keine
Baualtersklasse, und die ist Bedingung (siehe Auswahlregel).

Die 143 sind **19 Konstruktionen × ihre Baualtersklassen** — dasselbe Muster
wie im Altbauatlas, wo dieselbe Wand je Jahrgang einen eigenen U-Wert
bekommt. Nach Bauteilart: 63 Außenwand, 24 Fußboden, 24 Kellerdecke,
16 Decke, 16 Dach.

**Warum das ohne Umbau funktioniert:** Sie sind von derselben Art wie das, was
schon drinsteht. Schichten, U-Wert, Baualter, Bauteilart — alle Felder finden
ihr Gegenstück. Der Embedding-Text trägt Substanz, weil der Aufbau da ist. Und
`AltbauatlasController::nurEigene()` verbietet das Bearbeiten von allem, was
nicht `herkunft = 'eigen'` ist: importierte Zeilen sind damit **automatisch
schreibgeschützt**, ohne eine Zeile Code. Das ist das richtige Verhalten — sie
sind Beleg, nicht Entwurf.

**Auswahlregel** (ausformuliert, damit der Import reproduzierbar bleibt):

```
GroupType/UsageType ∈ { 1/2 → Außenwand,  5/2 → Dach,
                        4/7 → Decke,      4/8 → Kellerdecke,
                        4/4 → Fußboden }
UND  hat mindestens eine Schicht
UND  hat eine Baualtersklasse aus dem Ordnernamen
UND  stammt aus einem Bestands-Teilkatalog (nicht Hersteller/Neubau/Produkt)
```

Als Bestands-Teilkatalog gelten nach der Entscheidung vom 11.09.2026 genau
zwei: `Typologien` und `BauteileTypologie`, jeweils ohne die österreichischen
Ordner. Alles andere ist Produkt, Neubau oder Ausland.

#### Steildach oder Flachdach — fest hinterlegt, nicht abgeleitet

Hottgenroth kennt nur „Dach gegen außen" (5/2), die FS-Liste trennt steil und
flach. Betroffen sind **16 Bauteile** — zwei Konstruktionen in je acht
Baualtersklassen. Bei der Größe wird nicht klassifiziert, sondern nachgesehen;
alle 16 sind über ihre **äußerste Schicht** eindeutig:

| Bezeichnung in der Quelle | äußerste Schicht | FS-Bauteilart | Anzahl |
|---|---|---|---:|
| Holzkonstruktion | Dachziegelsteine aus Ton | **Steildach** | 7 |
| Holzkonstruktion | belüftete Luftschicht (unausgebaut) | **Steildach** | 1 |
| Massive Konstruktion | Bitumendachbahn über Beton | **Flachdach** | 8 |

Die Zuordnung gehört als Tabelle von 16 GUIDs ins Importkommando, einmal
geprüft und eingecheckt — nicht als Regel, die zur Laufzeit rät.

**Warum keine Heuristik:** Ein Stichwortabgleich über den ganzen Schichtstapel
stuft drei der acht Flachdächer als Steildach ein, weil „Vollziegel" im
Mauerwerk steht. Der Marker muss auf der Deckschicht sitzen, und ob eine Regel
die richtig trifft, ist bei 16 Zeilen teurer zu prüfen als die 16 Zeilen selbst.

**Warum das nicht die Rechnung berührt:** `UWertRechner::UEBERGANG` setzt für
Steildach und Flachdach dieselben Übergangswiderstände (Rsi 0,10 / Rse 0,04).
Eine falsche Etikette kostet einen verpassten Suchtreffer, keine falsche Zahl.

**Der Einwand, der dazugehört: die Holzkonstruktion ist nicht nur Dach.** Die
Quelle sagt es selbst — `InfoDesc` lautet vollständig *„Dach (auch Wände
zwischen beheiztem und unbeheiztem Dachgeschoss) – Holzkonstruktion"*. Gemeint
sind Drempel, Abseitenwand, Gaubenwange. Wer eine Gaube aufnimmt, greift genau
hierauf zurück.

Trotzdem bleiben diese acht Zeilen **Steildach**, und zwar aus einem Grund, der
in den Daten steht und nicht in der Abwägung: Ihre äußerste Schicht ist
Dachziegel. Das ist ein Dachaufbau. Eine Drempelwand hat keine Ziegeldeckung —
die Typologie überträgt den **U-Wert** auf diese Lage, nicht den Schichtaufbau.
Beides zu vermengen hieße, einen Wandaufbau zu behaupten, den die Quelle nicht
hergibt.

Die Lage-Angabe geht dabei nicht verloren, sie wandert an die richtige Stelle:
Das Vergleichsband aus Stufe 2 führt sie als eigenes Merkmal, weil dort genau
die Frage beantwortet wird, die hier gestellt ist — *„was ist für eine
Abseitenwand dieses Jahrgangs üblich?"* Und verloren geht auch das Bauteil
nicht: Eine Suche mit `component_type: 'Dach'` oder `'Steildach'` findet die
acht Holzkonstruktionen weiterhin. Was fehlt, ist ausschließlich der Weg über
eine **Wand**-Suche — und das ist kein Mangel dieses Imports, sondern die Lücke
aus Stufe 4.

#### Titel: nur dort nachbessern, wo er nicht unterscheidet

Die 16 Dächer heißen in der Quelle ausschließlich „Holzkonstruktion" oder
„Massive Konstruktion". Als `titel` im Trefferbild sagt das einem Berater
nichts — daneben stehen Altbauatlas-Titel wie „30cm Porensteinmauerwerk, innen
und außen verputzt". Für diese 16 wird der Titel beim Import um die Deckung
ergänzt („Steildach, Holzkonstruktion mit Ziegeldeckung"); das Original bleibt
in `quellen` stehen.

Die übrigen 127 brauchen das nicht. Ihre Namen sind brauchbar:
„Massive Konstruktion – Massivwand aus Hochlochziegeln", „Holzkonstruktion –
Fachwerkwand mit Lehmausfachung bis 25 cm", „Boden gegen Erdreich, Stahlbeton
massiv". Eingriffe in Quelldaten gehören auf die Stellen begrenzt, an denen sie
einen echten Mangel beheben.

### Stufe 2 — Typologiewerte als Vergleichsband

**Was:** Eine eigene, flache Tabelle `hottgenroth_typologie_uwerte` mit
Bauteilart, Region, Baualtersklasse, Gebäudetyp, U-Wert. Rund 3.776 Zeilen,
keine Schichten, keine Bilder, keine Embeddings.

**Wozu:** Zwei Fragen, die die Bauteilliste heute nicht beantwortet:

- *Plausibilität* — „Der Berater hat für diese Wand U = 1,1 angesetzt. Was ist
  für ein freistehendes Einfamilienhaus von 1958 in Niedersachsen üblich?"
- *Rückfall* — wenn `find_building_components` nichts findet (heute: leere
  Antwort plus Hinweis), lässt sich wenigstens die Größenordnung nennen.

**Warum getrennt:** Die Tabelle hat weder Aufbau noch Quelle-Datenblatt noch
Bild. Als Katalogzeile wäre sie ein leeres Datenblatt; im Kandidatendeckel wäre
sie Ballast; im Embedding wäre sie Rauschen. Getrennt kostet sie eine Tabelle,
ein MCP-Werkzeug (`get_typical_u_value`) und eine Kachel auf dem Datenblatt —
und lässt die bestehende Suche unangetastet.

**Eine Spalte mehr, als man zunächst denkt: die Lage.** Die Typologie bindet
ihre Werte nicht nur an Bauteilart, Baualtersklasse, Gebäudetyp und Region,
sondern auch an die Angrenzung — `InfoDesc` führt Fälle wie *„Dach (auch Wände
zwischen beheiztem und unbeheiztem Dachgeschoss)"*. Genau hier gehört die
Abseitenwand hin, die im Katalog keine eigene Bauteilart bekommt. Die Lage
gehört deshalb als eigenes Feld ins Band und nicht in einen Fließtext — sonst
ist sie nicht abfragbar, und das Band beantwortet die halbe Frage.

**Nebenbei ist das die wertvollere Hälfte des ganzen Vorhabens.** Die 143
Aufbauten erweitern einen Katalog, der mit 856 gut beschriebenen Datenblättern
schon steht — 17 % Zuwachs, inhaltlich mit Überschneidung. Das Raster aus
Bauteilart × Baualtersklasse × Gebäudetyp × Region × Lage führt der Altbauatlas
dagegen **gar nicht**, und es ist das, worauf der iSFP-Prozess zurückfällt, wenn
nichts aufgemessen wurde. Stufe 1 kommt trotzdem zuerst — sie ist klein und legt
Schema, Import und Identität, auf denen Stufe 2 aufsetzt.

### Stufe 3 — Projektbauteile kuratiert übernehmen

**Was:** Auf `/admin/hottgenroth/bauteile` steht bereits der gespiegelte
Bauteilbestand der Arbeitsplätze — 9.333 Bauteile aus den echten Projekten des
Büros. Ein Knopf „In die Bauteilliste übernehmen" macht daraus eine Zeile mit
`herkunft = 'eigen'`, vorausgefüllt aus dem Spiegel.

**Warum das womöglich der wertvollste Weg ist:** Diese Bauteile sind von einem
Energieberater dieses Büros für ein reales Gebäude angesetzt und in einem iSFP
verwendet worden. Sie tragen mehr Wissen als jeder Katalogeintrag — und weil
ein Mensch beim Übernehmen entscheidet, entsteht keine Massenware. Der Aufwand
ist klein: Der Spiegel ist da, das Formular ist da, es fehlt die Brücke
dazwischen.

Einschränkung, die dazugehört: Im iSFP-Bestand ist das Bauteil **ohne** Aufbau
der Regelfall — in `strackerjan.sqproj` 62 von 82. Übernommen werden können
sinnvoll nur die mit Schichten.

### Stufe 4 — die Bauteilarten erweitern

Dieser Punkt stand zuerst als Fußnote hier. Er gehört nach oben, seit die
eigenen Projekte ausgezählt sind.

Der Bauteilspiegel enthält 629 Bauteile aus echten Projekten des Büros. Gegen
die sechs FS-Bauteilarten gehalten:

| Lage im Projekt | Bauteile | FS-Bauteilart |
|---|---:|---|
| Fenster gegen außen | 171 | **fehlt** |
| Tür gegen außen | 88 | **fehlt** |
| Wand gegen außen | 68 | Außenwand |
| Boden gegen Erdreich | 67 | Fußboden |
| Dach gegen außen | 61 | Steildach / Flachdach |
| Wand gegen Erdreich | 44 | **fehlt** |
| Boden gegen Keller | 34 | Kellerdecke |
| Wand gegen unbeheizt | 24 | **fehlt** |
| Tür gegen beheizt | 24 | **fehlt** |
| Oberste Geschossdecke | 22 | Decke |
| Wand gegen beheizt | 18 | **fehlt** |
| Decke gegen beheizt | 8 | **fehlt** |

**Die sechs Bauteilarten decken 252 von 629 ab — 40 %.** Der häufigste Bauteiltyp
in den eigenen Projekten, das Fenster, hat überhaupt keine Entsprechung. Und die
Wand gegen unbeheizt (24) ist genau die Lage, an der Abseitenwand, Drempel und
Gaubenwange hängen.

Das ist kein Import-Problem und lässt sich auch nicht durch geschickteres
Zuordnen lösen — die FS-Liste kann diese Bauteile schlicht nicht halten. Eine
Erweiterung ist ein eigenes Vorhaben: eigene Formularvalidierung (Rahmen,
Verglasung, g-Wert statt Schichten), eigene Übergangswiderstände, eigener
Embedding-Text, und eine Entscheidung, ob „Wand" künftig nach Angrenzung
aufgeteilt wird (Außenwand / Kellerwand / Wand gegen unbeheizt) — wofür
`HottgenrothBauteil::KOSTENTOOL_CODES` mit AW, WE, WK längst die Kennungen hat.

Reihenfolge nach Nutzen, gemessen an der Tabelle oben: **Fenster und Türen
zuerst** (283 Bauteile), danach die Wandlagen (86).

---

## 5. Technik

### 5.1 Schema

Zwei Ergänzungen an `altbauatlas_bauteile`, sonst nichts:

```php
$table->string('quelle_ref', 64)->nullable()->after('herkunft');   // Dimension-GUID
$table->string('quelle_pfad')->nullable()->after('quelle_ref');    // Katalogordner, Herkunftsbeleg
$table->unique(['herkunft', 'quelle_ref']);
```

`herkunft` ist bereits ein String ohne Wertebereichsprüfung — `'hottgenroth'`
braucht keine Migration. Und weil der `AltbauatlasSeeder` ausschließlich
`herkunft = 'altbauatlas'` löscht, überlebt der Import jeden Neu-Crawl von
selbst.

**ID-Band:** Altbauatlas 1–1029, eigen ab 100000, **Hottgenroth ab 300000**.
Die ID wird beim ersten Import vergeben und über `quelle_ref` festgehalten —
nicht bei jedem Lauf neu.

### 5.2 Identität und Wiederholbarkeit

Das ist die Stelle, an der ein naiver Import zerbricht. `fs_projekt_bauteile`
verweist mit `restrictOnDelete` auf den Katalog. Würde ein zweiter Importlauf
neue IDs vergeben, wäre jeder Projektverweis tot — und der Löschversuch würde
am Fremdschlüssel scheitern, nicht sauber fehlschlagen.

Deshalb: Identität ist `quelle_ref` (die GUID der `TcBuildingElementDimension`),
nicht die Position im Export. Der Import arbeitet als **Upsert** und räumt
Entfallenes nach demselben Muster auf, das
`AltbauatlasSeeder::verschwundeneAufraeumen()` schon vormacht — verwendete
Zeilen bleiben stehen, der Rest geht, und der Bericht nennt beides.

### 5.3 Transport

Dem Muster des Altbauatlas folgen, nicht daneben ein zweites erfinden:

```
bauteile/tools/Export-Bauteile.ps1        →  am Arbeitsplatz, liest (localdb)\HSETU
database/data/hottgenroth/bauteile.ndjson →  versioniert im Repo, wie datenblaetter.ndjson
php artisan bauteile:hottgenroth-import   →  Upsert in die Bauteilliste
```

Der ausgelieferte Katalog ändert sich nur mit einem Software-Update. Ein
Datenstand im Repo ist damit richtig: reproduzierbar, überprüfbar, ohne Agent,
ohne Datei auf einem Desktop. `deploy.sh` synchronisiert `database/` bereits.

Der Weg über den Agenten (`katalog.export` als fünfter Auftragstyp, dieselben
lesenden `sql.query`-Schritte gegen `HsetuAppTimData`) bleibt die Reserve, falls
sich herausstellt, dass der Stand doch häufiger nachgezogen werden muss. Dann
zu beachten: `HottgenrothBauteilSync::MAX_BAUTEILE` steht auf 3000 — für Stufe 1
(~895) reicht das, für den vollen Katalog nicht.

### 5.4 Feldabbildung

| FS-Feld | kommt aus | Anmerkung |
|---|---|---|
| `titel` | `TcBasis.LongDesc` | |
| `bauteil` | `GroupType`/`UsageType` | Abbildung siehe 4./Stufe 1 |
| `konstruktion` | — | bleibt leer; Hottgenroth kennt das Feld nicht |
| `baualter_raw` | Ordnername, Segment mit Jahreszahl | **abgeleitet**, nicht aus der Datenbank — siehe unten |
| `baujahr_von` / `_bis` | daraus als Band gelesen | die Untergrenze steht nirgends in der Quelle |
| `u_wert_raw` / `_min` / `_max` | `TcBuildingElementDimension.UValue` | `u_wert_typ = 'einzel'`, min = max |
| `schichten.*` | `TcBuildingElementDimensionLayer` | Dicke m → cm; `material`, `lambda`, `rohdichte` direkt |
| `bemerkungen` | `TcBuildingElementDimension.InfoDesc` | trägt Gebäudetyp und Baualtersklasse im Klartext — **und landet damit im Embedding-Text** |
| `plz` | — | entfällt: die 143 stammen aus der bundesweiten Typologie, nicht aus einer Regionaltypologie |
| `quellen` | Teilkatalog + Ordner | |

#### Die Baualtersklasse: Label aus den Daten, Untergrenze abgeleitet

Das ist die einzige Größe des Imports, die nicht in der Quelle steht, und sie
verdient deshalb eine eigene Begründung.

**Woher das Label kommt.** Aus genau einer Stelle — dem Namen des Katalogordners
in `TcCatalogContent.LongDesc`:

```
=== T Y P O L O G I E  Deutschland -EnEV 2015- (mit Schichtaufbauten) | bis 1948 | Ein-/Mehrfamilien
```

Ein Textfeld, gesperrt gesetzt, bei allen acht Klassen **exakt 100 Zeichen**: Die
Spalte ist `nvarchar(100)`, der Gebäudetyp ist abgeschnitten. Als Zahl gibt es
die Jahre nirgends — geprüft und ausgeschlossen sind `ValidStartDate` und
`ValidEndDate` (beide 30.12.1899, das Delphi-Nulldatum), `Version`,
`DateRevised`, `Category`, `MatchCode` (alle leer) sowie `TcClassification`,
das mit 20.036 Zeilen ausschließlich Anlagentechnik führt und für Bauteile
**null** Treffer liefert.

**Warum daraus ein Band wird.** Die Quelle sagt „bis 1948"; gespeichert wird
1919–1948. Wörtlich gelesen — Untergrenze offen — fiele ein Gebäude von 1930 in
sechs der acht Klassen, weil `scopeBaujahr` überlappend filtert. Die Suche
lieferte sechsmal dieselbe Wand mit verschiedenen U-Werten und keinen Hinweis,
welcher gilt.

Dass die Bandlesart die richtige ist, steht in den Daten: Verfolgt man einen
Aufbau über die acht Klassen, trägt jede Klasse einen **eigenen** U-Wert.

| Konstruktion | bis 1918 | bis 1948 | bis 1957 | bis 1968 | bis 1978 | bis 1983 | bis 1994 | ab 1995 |
|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Sonstige massive Wandaufbauten | 3,00 | 3,00 | 3,00 | 1,40 | 1,00 | 0,80 | 0,70 | 0,70 |
| Massivwand aus Hochlochziegeln | 1,40 | 1,40 | 1,40 | 1,40 | 1,00 | 0,80 | 0,60 | 0,50 |
| sonstige Holzkonstruktion | 2,05 | 2,05 | 1,52 | 1,43 | 0,60 | 0,50 | 0,41 | 0,41 |
| Massivwand aus Vollziegeln 20–30 cm | 1,80 | 1,80 | 1,80 | — | — | — | — | — |

Wäre „bis 1978" kumulativ gemeint, könnte dieselbe Wand nicht gleichzeitig 3,00
und 1,00 sein. Die Sprünge sitzen zudem auf den Wärmeschutzverordnungen (1978,
1984, 1995), und die Vollziegelwand entfällt nach 1957, weil sie danach nicht
mehr gebaut wurde. Beides passt nur zur Bandlesart.

Die Umrechnung gehört als Tabelle ins Importkommando und in die Prüfansicht
(siehe UI-Entwurf), nicht als stille Regel:

| Quelle | gespeichert |
|---|---|
| bis 1918 | offen – 1918 |
| bis 1948 | 1919 – 1948 |
| bis 1957 | 1949 – 1957 |
| bis 1968 | 1958 – 1968 |
| bis 1978 | 1969 – 1978 |
| bis 1983 | 1979 – 1983 |
| bis 1994 | 1984 – 1994 |
| ab 1995 | 1995 – offen |

Zwei Fallen darin:

**Sentinelwerte.** Die Software schreibt −987654321,99 für „nicht gesetzt", und
zusätzlich steht bei Typologiebauteilen 0 in `Thickness`. Beides muss zu `NULL`
werden, nicht zu einer Zahl — `HottgenrothBauteilSync::NULL_FLOAT` macht es
vor.

**Inhomogene Bauteile.** Hottgenroth teilt sie in Gefache, jedes ein
vollständiger Schichtstapel mit Flächenanteil. `altbauatlas_schichten` hat dafür
kein Gegenstück: `variante_idx` meint dort *alternative Schichtstärken*, nicht
Gefache. Vorschlag: das flächengrößte Gefach als Aufbau übernehmen und den
Sachverhalt als Bemerkung mitführen („inhomogen, 3 Gefache; abgebildet ist das
flächengrößte"). Nichts anderes tut die Spalte „Aufbau" in der Excel-Mappe. Wer
es genauer braucht, geht auf den Arbeitsplatz.

### 5.5 Embeddings

Nach dem Import einmal `php artisan bauteile:embeddings` — das Kommando läuft
über alle Bauteile und erkennt fehlende Vektoren selbst.

`config('fs_projekt.embedding.version')` **nicht** erhöhen: Die Textvorlage
ändert sich nicht, nur der Bestand wächst. Ein Versionssprung würde alle 856
vorhandenen Vektoren neu berechnen lassen, ohne dass sich etwas an ihnen
geändert hätte.

### 5.6 Suche

Drei Änderungen, davon eine, die ohnehin fällig ist:

1. **Die stille Kürzung sichtbar machen.** `candidate_count` muss die Zahl
   *vor* dem Limit melden, und das Ergebnis ein `truncated`-Kennzeichen tragen.
   Das ist heute schon ein Mangel, nur einer ohne Wirkung — nach dem Import
   hätte er Wirkung.
2. **`quelle` als Filter** in `BauteilSucheAnfrage`, damit sich gezielt „nur
   Altbauatlas" oder „nur Hottgenroth" fragen lässt.
3. **`herkunft` und Quellenangabe je Treffer** ausgeben statt einmal pauschal.

Bewusst **keine** Änderung: kein Bonus für die eine oder andere Quelle. Welcher
Aufbau passt, entscheidet der Aufbau — nicht, aus welchem Katalog er stammt.

### 5.7 Zwei Stellen, die sonst still falsch werden

**`ProjektBauteilService` schreibt die Quelle fest.** In
[`ProjektBauteilService`](../../app/Services/Fs/ProjektBauteilService.php) steht
`'katalog_quelle' => 'altbauatlas'` als Konstante im Schlüssel der Zuordnung.
Sobald Hottgenroth-Zeilen in derselben Tabelle stehen, bekäme jedes zugeordnete
Hottgenroth-Bauteil die falsche Herkunft angeheftet — und ausgerechnet die
Spalte, die für diesen Fall vorgesehen ist, wäre wertlos.

Die Zeile muss `$bauteil->herkunft` übernehmen, und zwar **in Stufe 1, nicht
später**: `katalog_quelle` ist Teil des UNIQUE-Schlüssels. Wird erst nachträglich
korrigiert, lässt sich dasselbe Bauteil zweimal zuordnen — einmal falsch als
`altbauatlas` beschriftet, einmal richtig.

Die Entscheidung dahinter, die ins Protokoll gehört: `katalog_quelle` bedeutet
in diesem Entwurf **Herkunft der Zeile**, nicht Tabelle. Der Migrationskommentar
liest sich zwar wie „getrennte Tabelle" („spaeter z.B. 'hottgenroth' als
getrennte Retrieval-Quelle"), aber Stufe 1 legt die Zeilen bewusst in
`altbauatlas_bauteile` ab — sie sind von derselben Art, und eine zweite Tabelle
hieße Suche, Embeddings und Oberfläche doppelt zu bauen.

**Die Anleitung des KI-Bereichs ist testgeprüft.**
[`tests/Feature/Ai/DokumentationTest.php`](../../tests/Feature/Ai/DokumentationTest.php)
verlangt für **jedes** Werkzeug einen Abschnitt `### \`name\`` in
[`docs/ki-bauteilsuche.md`](../../docs/ki-bauteilsuche.md) und für **jeden**
Parameter eine Erwähnung. Das heißt konkret:

- der neue Filter `quelle` an `find_building_components` (Stufe 1a) bricht den
  Build, wenn er nicht im selben Commit dokumentiert wird;
- das Werkzeug `get_typical_u_value` (Stufe 2) ebenso, samt aller Parameter.

Das ist kein Hindernis, sondern der Grund, warum die Anleitung stimmt. Nur
gehört sie in den Aufwand eingerechnet und nicht ans Ende geschoben.

### 5.8 Oberfläche

`liste.json` liefert `herkunft` bereits mit; es fehlt nur der Filterknopf in
[`resources/views/altbauatlas/index.blade.php`](../../resources/views/altbauatlas/index.blade.php).
Nach dem Import muss `altbauatlas.liste.v2` aus dem Cache —
`AltbauatlasController::cacheLeeren()` gibt es schon, das Importkommando ruft es
auf.

Zweite Stelle: [`resources/views/fs_projekt/show.blade.php`](../../resources/views/fs_projekt/show.blade.php)
zeigt die zugeordneten Bauteile eines FS-Projekts. Dort gehört die Herkunft
sichtbar hin — sonst steht ein Altbauatlas-Datenblatt mit Quellenbeleg neben
einem Hottgenroth-Aufbau ohne, und beide sehen gleich aus.

**Dritte Stelle, und die wird sonst übersehen: die Jahresskala endet 1995.**
In [`index.blade.php`](../../resources/views/altbauatlas/index.blade.php) steht
`const JAHR_VON = 1850, JAHR_BIS = 1995;` fest im Skript. Regler, Histogramm und
Skala richten sich danach, und die Histogrammschleife überspringt jedes Bauteil,
dessen Zeitraum daneben liegt.

Heute ist das folgenlos: Der Altbauatlas endet bei `baujahr_bis` = 1994, und
**kein einziges** der 856 Datenblätter hat eine offene Obergrenze. Ein Baujahr
2026 lässt sich zwar ins Zahlenfeld tippen — der Filter läuft ungeklemmt —, es
kommt nur nichts zurück.

Nach dem Import ist es nicht mehr folgenlos. Die deutschen Typologien bringen
483 Werte für Baujahre ab 1995 mit (`ab 1995` 274, `1995-2001` 105, `ab 2002`
83, `seit 1995` 21), und `ab 2002` hat eine offene Obergrenze. Diese Bauteile
stünden in der Datenbank, ohne dass die Oberfläche sie zeigt. **Die Grenzen
müssen daher aus den Daten kommen** — Minimum und Maximum über
`baujahr_von`/`baujahr_bis`, offene Obergrenzen auf das laufende Jahr —, nicht
als Konstante im Blade stehen.

Wozu die Typologie auch dann nicht taugt: ein Gebäude von 2026 zu beschreiben.
Eine Typologie schätzt, wo Unterlagen fehlen; ein Neubau hat GEG-Nachweis und
Datenblätter. Und die Klasse „ab 2002" liegt vor EnEV 2007, 2009, 2014 und GEG
2020/2024. Für neue Gebäude sind die Zielaufbauten der Neubaukataloge das
richtige Mittel, nicht eine fortgeschriebene Bestandsklasse.

---

## 6. Reihenfolge und Aufwand

| | Ergebnis | grob |
|---|---|---|
| 1 | Migration + `bauteile:hottgenroth-import` (143 Zeilen) + Datenstand + Embeddings + `katalog_quelle` (5.7) | 1–2 Tage |
| 1a | Suchkorrekturen (5.6), Quellenangabe je Treffer, `docs/ki-bauteilsuche.md` | 0,5–1 Tag |
| 2 | Typologie-Vergleichsband (3.060 Werte): Tabelle, Import, MCP-Werkzeug, Kachel | 2–3 Tage |
| 3 | „Projektbauteil übernehmen" auf `/admin/hottgenroth/bauteile` | 1 Tag |
| 4 | Fenster und Türen als eigene Bauteilarten, danach die Wandlagen | eigenes Vorhaben |

Die Schätzungen sind grob. Stufe 0 (Sichtung des Schnitts) ist mit der
Entscheidung vom 11.09.2026 erledigt und entfällt.

**Stufe 1 und 1a gehören zusammen** — Stufe 1 allein auszuliefern hieße, die
Suche mit einem bekannten Deckel in einen Bestand zu schicken, der ihn erreicht.

**Der Nutzen liegt nicht in der Reihenfolge des Aufwands.** Stufe 2 trägt mehr
als Stufe 1 (siehe dort), und Stufe 4 schließt die größte Lücke von allen —
60 % der Bauteile in den eigenen Projekten haben heute keine FS-Bauteilart.
Stufe 1 steht trotzdem vorn, weil sie Schema, Import und Identität legt, auf
denen die anderen aufsetzen, und weil sie mit 143 Zeilen klein genug ist, um
daran die Mechanik zu prüfen.

---

## 7. Entscheidungen und was offen bleibt

### Getroffen am 11.09.2026

**Nutzungsrecht: ja.** Die Übernahme in die FS-Bauteilliste ist freigegeben.
Damit ist der einzige Punkt erledigt, der das Vorhaben ganz hätte aufhalten
können. Zu beachten bleibt: Der Altbauatlas-Bestand führt `quelle_url` und
`pdf_url` je Zeile — ein Hottgenroth-Import kann das nicht. Die Herkunft steht
stattdessen in `quelle_pfad` (Teilkatalog und Ordner), und die Quellenangabe je
Treffer (5.6) macht den Unterschied im Ergebnis sichtbar.

**Österreich: weglassen.** Kostet keinen einzigen Aufbau — alle 715 abbildbaren
österreichischen Bauteile sind U-Wert-Zeilen. Betroffen ist damit nur Stufe 2,
und dort ist die PLZ-Zuordnung ohnehin der Knackpunkt gewesen.

**Steildach / Flachdach: fest hinterlegt.** 16 Bauteile, alle über die äußerste
Schicht eindeutig — 8 Steildach, 8 Flachdach. Keine Heuristik, eine geprüfte
Tabelle im Importkommando. Begründung und Tabelle in 4./Stufe 1.

**Schnitt: deutscher Bestand.** 143 Aufbauten (Stufe 1), 3.060 Typologiewerte
(Stufe 2). Teilkataloge `Typologien` und `BauteileTypologie`, ohne die
österreichischen Ordner.

### Offen

**Was „Vorlage" heißen soll.** Die Holzkonstruktion aus der Dach-Typologie deckt
laut Quelle auch Drempel, Abseitenwand und Gaubenwange ab. Sie in der FS-Liste
als Vorlage für eine Gaube greifbar zu machen, geht auf zwei verschiedenen
Wegen, und die Wahl entscheidet, was gebaut wird:

- **Suchen und finden** — die Gaubenwange soll über eine Bauteilsuche auffindbar
  sein. Dann führt der Weg über Stufe 4: Ohne eine Bauteilart, die „Wand gegen
  unbeheizt" halten kann, findet keine Suche sie, egal wie der Import sortiert.
- **Anlegen und anwenden** — die Konstruktion soll als fertiger Aufbau in ein
  Hottgenroth-Projekt übernommen werden. Das ist die Schreibrichtung und steht
  in [`bauteile-uebernehmen.md`](bauteile-uebernehmen.md), nicht hier.

Beide sind machbar, aber es sind zwei Vorhaben. Solange das nicht geklärt ist,
bleiben die acht Holzkonstruktionen Steildach — dort sind sie richtig abgelegt
und über `component_type: 'Dach'` auffindbar.

---

## Anhang: Wo was steht

| | |
|---|---|
| Datenmodell Hottgenroth | [`bauteile/docs/hottgenroth-bauteil-sql.md`](../../bauteile/docs/hottgenroth-bauteil-sql.md) |
| Export der Bauteile | [`bauteile/tools/Export-Bauteile.ps1`](../../bauteile/tools/Export-Bauteile.ps1), [`baue-excel.php`](../../bauteile/tools/baue-excel.php) |
| FS-Bauteilliste, Schema | [`database/migrations/2026_08_06_120000_create_altbauatlas_tables.php`](../../database/migrations/2026_08_06_120000_create_altbauatlas_tables.php) |
| FS-Bauteilliste, Suche | [`app/Services/Fs/BauteilSucheService.php`](../../app/Services/Fs/BauteilSucheService.php) |
| Embedding-Text | [`app/Services/Altbauatlas/EmbeddingTextBuilder.php`](../../app/Services/Altbauatlas/EmbeddingTextBuilder.php) |
| Spiegel der Projektbauteile | [`app/Services/HottgenrothBauteilSync.php`](../../app/Services/HottgenrothBauteilSync.php) |
| Gegenrichtung (FS → Hottgenroth) | [`bauteile-uebernehmen.md`](bauteile-uebernehmen.md) |
