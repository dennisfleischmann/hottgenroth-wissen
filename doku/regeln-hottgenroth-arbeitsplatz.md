# Hottgenroth-Arbeitsplatz

Regeln für den Bauteilspiegel eines Hottgenroth-Arbeitsplatzes — was der Server
vom Rechner des Beraters holt, und was eine Auskunft darüber versprechen darf.
Der FS-Bauteilkatalog ist etwas anderes und steht in
[bauteilkatalog.md](bauteilkatalog.md). Konvention: [README.md](README.md).

---

## HA-01 — Ein Spiegel ist erst ein Ergebnis, wenn der Abruf übernommen ist

**Regel:** Jede Auskunft aus dem Spiegel nennt den jüngsten Abruf des Projekts
mit seinem Zustand: `wartet_auf_arbeitsplatz`, `wird_gelesen`, `uebernommen`,
`nicht_uebernommen` oder `fehlgeschlagen`. Übernommen ist ein Abruf erst, wenn
das Projekt auf ihn zeigt (`bauteile_task_id`) — nicht schon, wenn der Auftrag
auf `succeeded` steht. Scheitert er, steht der Grund in der Auskunft.

**Warum:** Der Abruf ist absichtlich ohne Warten gebaut: der Auftrag liegt, der
Arbeitsplatz holt ihn beim nächsten Poll. Am 15.09.2026 stieß ein Modell den
Abruf an und las im selben Atemzug nach. Der Arbeitsplatz hatte ihn da noch
nicht abgeholt, der Spiegel zeigte den Stand von vorher — und das Modell
schrieb „ob die Änderungen drin sind, kann ich nicht bestätigen". Der Berater
meldete einen Fehler. Die einzige Erfolgskontrolle war ein Zeitstempelvergleich,
und der fällt direkt nach dem Anstoßen immer „unverändert" aus.

Dazu kommt: „erledigt" am Agenten heißt nur, dass der Server HTTP 200 geantwortet
hat. Die Übernahme danach fängt ihre Ausnahmen ab und schreibt sie als Warnung an
den Auftrag. Die sah bisher nur, wer die Verwaltung öffnete.

**Dasselbe gilt für die Projektliste** (seit 16.09.2026). Sie ist ein zweiter,
unabhängiger Spiegel mit eigenem Auftragstyp (`projekte.liste`), und übernommen
ist ein Abbild erst, wenn der Arbeitsplatz `abbild_synced_at` dafür trägt — ein
abgeschnittenes Ergebnis lässt den Zeitstempel ausdrücklich stehen, und genau
dann fehlen Projekte, ohne dass irgendetwas fehlgeschlagen wäre. Die Liste nennt
ihren Stand deshalb selbst.

**Im Code:** [HottgenrothWerkzeug.php](../../app/Ai/Tools/Hottgenroth/HottgenrothWerkzeug.php)
(`abrufStand()`, `abrufZustand()`, `abbildStand()`, `abbildZustand()`) ·
[HottgenrothProjekt.php](../../app/Models/HottgenrothProjekt.php) (`letzterBauteilAbruf()`) ·
`next_step` in [RefreshHottgenrothComponentsTool.php](../../app/Ai/Tools/Hottgenroth/RefreshHottgenrothComponentsTool.php)
und [UpdateHottgenrothProjectsTool.php](../../app/Ai/Tools/Hottgenroth/UpdateHottgenrothProjectsTool.php)

**Bewacht durch:** `McpHottgenrothTest::test_ein_laufender_abruf_wird_gemeldet_statt_als_ergebnis_verkauft`,
`McpHottgenrothTest::test_ein_nicht_uebernommener_abruf_nennt_den_grund`,
`McpHottgenrothTest::test_ein_fehlgeschlagener_abruf_nennt_den_fehler`,
`McpHottgenrothTest::test_die_projektliste_nennt_ihren_eigenen_stand`,
`McpHottgenrothTest::test_ein_nicht_uebernommenes_abbild_gilt_nicht_als_erledigt`

---

## HA-02 — Der Spiegel nennt den Speicherstand in Hottgenroth

**Regel:** Der Abruf liest `PrProject.StampEdit` mit, und die Auskunft nennt ihn
als `in_hottgenroth_gespeichert_am` — neben `gelesen_am`, dem Moment, in dem der
Arbeitsplatz gelesen hat. Kennt ein älteres Ergebnis den Speicherstand nicht,
fehlt das Feld; geraten wird nicht.

**Warum:** Ein Abruf sieht nur, was gespeichert ist, und die Software speichert
nicht alles zur selben Zeit. Katalogbauteile stehen sofort in der Datenbank, die
Zuweisung einer Konstruktion an Flächen erst nach dem Speichern des Projekts —
und `BmElement.StampEdit` bewegt sich dabei nicht einmal. Am 15.09.2026 las ein
Abruf um 16:35:12; die neuen Konstruktionen waren da, die Speicherung des
Projekts kam um 16:40. Ein „frischer" Spiegel ohne die Änderungen ist von einem
kaputten nicht zu unterscheiden, solange niemand sagt, bis wann gespeichert war.

**Im Code:** [HottgenrothBauteilSync.php](../../app/Services/HottgenrothBauteilSync.php)
(Schritt „Projektkopf lesen" in `auftragFuerBauteile()`) ·
[HottgenrothWerkzeug.php](../../app/Ai/Tools/Hottgenroth/HottgenrothWerkzeug.php) (`gespeichertAm()`)

**Bewacht durch:** `McpHottgenrothTest::test_ein_uebernommener_abruf_nennt_lesezeit_und_speicherstand`,
`McpHottgenrothTest::test_der_abruf_liest_den_speicherstand_mit`

---

## HA-03 — Schreiben auf den Arbeitsplatz braucht ein eigenes Recht

**Regel:** `import_hottgenroth_projekt`, `add_hottgenroth_bauteile` und
`add_components` hängen an `hottgenroth:schreiben`, nicht am Leserecht. Der
Scope ist über die Zustimmungsseite ankreuzbar — und wie jeder andere durch
`users.mcp_scopes` gedeckelt. Ein Admin gibt ihn je Mensch einmal frei; ohne das
nützt das Kästchen nichts. Der Upload-Endpunkt `POST /api/mcp/dateien` verlangt
dasselbe Recht.

**Warum ein eigenes Recht:** `refresh_hottgenroth_components` ist schreibend im
Sinne des Protokolls, rührt aber nichts an: auf dem Arbeitsplatz laufen sechs
SELECTs, neu geschrieben wird nur der Spiegel auf dem Server. Diese drei sind
etwas anderes. Ein Import legt ein Projekt in der LocalDB eines Menschen an —
zweimal aufgerufen zweimal, weil die Software beim Import neue GUIDs vergibt und
keine Wiederholung erkennt. Eingespielte Bauteile stehen danach im Katalog
seines Kunden, und `add_components` hängt vorhandene Flächen an eine andere
Konstruktion um. Wer die Bauteilliste sehen darf, darf deshalb nicht automatisch
hineinschreiben.

**Warum die Schranke umgezogen ist (19.09.2026):** Bis dahin war der Scope
ausdrücklich NICHT ankreuzbar — er stand nicht in `config('oauth.scopes')` und
wurde von Hand vergeben. Das ist an der Praxis gescheitert. Der
claude.ai-Connector stellt sich bei **jeder** Autorisierung ein neues Token aus;
am 19.09.2026 waren es zwischen 10:07 und 14:02 allein sieben (#681, #684, #685,
#691, #693, #694, #696). Jedes davon startet ohne die nachgetragenen Rechte.

Das Ergebnis war kein vorsichtigerer Zugang, sondern ein Werkzeug, das nach
jeder Neuanmeldung still verschwand. Eine Sitzung meldete an dem Tag
`add_components` als „nicht verfügbar“ und hielt es für einen Defekt — und weil
ein Werkzeug ohne Recht als `werkzeug_unbekannt` antwortet und gar nicht erst
gelistet wird, sah es auch genau so aus. Eine Schranke, die man nicht sieht und
die sich stündlich selbst zurücksetzt, schützt nichts; sie kostet nur
Fehlersuche.

Die Entscheidung ist damit **nicht** gelockert, sondern an die Stelle verschoben,
die sie halten kann: `users.mcp_scopes`. Die liegt beim Admin, gilt je Mensch und
überlebt jede Neuanmeldung — dieselbe Lösung, die `hottgenroth:arbeitsplatz`
schon vorher hatte.

**Im Code:** `WERKZEUG_SCOPES` in [ToolRegistry.php](../../app/Ai/ToolRegistry.php) ·
`scopes` in [config/oauth.php](../../config/oauth.php) ·
`scopes()` in [McpController.php](../../app/Http/Controllers/Ai/McpController.php)
(Schnittmenge aus Token und `users.mcp_scopes`, je Aufruf neu) ·
[McpDateiController.php](../../app/Http/Controllers/Ai/McpDateiController.php) (`SCOPE`)

**Bewacht durch:** `McpHottgenrothSchreibenTest::test_ein_lesetoken_darf_nicht_importieren`,
`McpHottgenrothSchreibenTest::test_ein_lesetoken_darf_nicht_hochladen`,
`McpHottgenrothZuweisenTest::test_ein_lesetoken_darf_nicht_zuweisen`,
`DokumentationTest::test_jedes_recht_laesst_sich_auch_vergeben` (die Ausnahmeliste
dort ist seitdem leer)

---

## HA-04 — Die Datei reist am Werkzeugaufruf vorbei

**Regel:** Eine .sqproj wird nie als Argument übergeben. Der Werkzeugaufruf
nennt sie nur — entweder als Drive-Datei, die der Server selbst holt (HA-10),
oder als Schlüssel eines vorherigen HTTP-Uploads an `POST /api/mcp/dateien`
(höchstens 40 MB, nur `.sqproj`). Für den Schlüssel gilt: das Werkzeug nimmt
ausschließlich Schlüssel aus dem Upload-Ordner an und prüft, dass die Datei dort
liegt. Die Antwort des Uploads nennt eine SHA-256.

**Warum:** Argumente eines Werkzeugaufrufs gehen durch das Kontextfenster des
Modells — jedes Byte muss dort erzeugt werden. Eine Projektdatei wiegt 7 bis 40
MB; als base64 im Aufruf ist das nicht knapp, sondern unmöglich, und keine
Protokolleinstellung ändert daran etwas. Die Prüfsumme gehört dazu, weil ein
abgeschnittener Upload sonst dieselbe Antwort hat wie ein vollständiger.

Die Schlüsselprüfung ist kein Formalismus: ohne sie wäre `datei` ein Weg, den
Agenten eine beliebige Datei der Ablage laden zu lassen — der Download-Endpunkt
ist token-, nicht agentgebunden (siehe offene Lücken).

**Im Code:** [McpDateiController.php](../../app/Http/Controllers/Ai/McpDateiController.php) ·
`schluessel()` in [ImportHottgenrothProjektTool.php](../../app/Ai/Tools/Hottgenroth/ImportHottgenrothProjektTool.php)

**Bewacht durch:** `McpHottgenrothSchreibenTest::test_ein_schluessel_ausserhalb_des_upload_ordners_wird_abgewiesen`,
`McpHottgenrothSchreibenTest::test_der_upload_liefert_schluessel_und_pruefsumme`

---

## HA-05 — Zentimeter, und die Lage bestimmt den U-Wert

**Regel:** Schichtdicken kommen in **Zentimetern** (`dicke_cm`), umgerechnet wird
im Server. Werte unter 0,5 cm werden abgewiesen. Die Lage eines Bauteils wird als
Wort angegeben (`gegen_aussen`, `boden_gegen_keller` …) und in `usageType`
übersetzt.

**Warum:** Der Baustein auf dem Arbeitsplatz rechnet in Metern, gesprochen wird
in Zentimetern („24 cm Aufsparrendämmung"). `0.16` statt `16` ergibt 1,6
Millimeter Dämmung — das Bauteil entsteht klaglos und hat nur einen zu hohen
U-Wert. Dasselbe gilt für `usageType`: die Software leitet daraus Rsi und Rse ab
und überschreibt abweichende Werte, eine falsche Zahl ist von außen unsichtbar.
Beides sind Fehler ohne Fehlermeldung, deshalb stehen die Namen im Schema und die
Umrechnung an einer Stelle.

**Dazu gehört die Baustoffgruppe** (seit 01.10.2026): Sie ist die **Farbe** der Schicht
im Schichtaufbau (`Hsetu.FW.Calculations.BaustoffFarbe()`: Mauerwerk rot, Dämmung gelb,
Holz braun) und meist die erste Ziffer des Katalogpfads. Sie wird **nicht geraten** — eine
erfundene Gruppe behauptet etwas über den Baustoff und stellt die Schicht im Materialbaum
an die falsche Stelle. Die Zuordnung der neun Gruppen ist an rund 28.000 Schichten der
LocalDB gemessen.

**Ohne Gruppe wird die Schicht violett, nicht grau** (gemessen 03.10.2026): `BaustoffFarbe()`
hat keinen Zweig für `mgdNone`, die 0 fällt in den Default-Zweig und bekommt (136, 81, 136) —
dasselbe Violett wie Gruppe 8 „Sonstiges". Grau ist Gruppe 2. Der fehlende Wert ist damit
nicht als fehlend erkennbar; „lieber grau als falsch gefärbt" geht als Abwägung nicht auf.
Das ändert nichts daran, dass nicht geraten wird — es ändert, was man dem Bild ansieht.

**Der Katalogpfad darf der Gruppe widersprechen** (korrigiert 03.10.2026): Bis dahin wies das
Werkzeug einen Pfad ab, dessen erste Ziffer nicht der Gruppe entsprach. Die Software schreibt
es selbst so: von 23.353 Schichten mit einem Pfad aus dem Baum widersprechen 1.912 (8,2 %)
der eigenen Gruppe, allein 1.258-mal Pfad `6.x` in Gruppe 3 — Holzwerkstoffplatten wie OSB
stehen im Baum unter Holz und sind als Bauplatte eingefärbt. Geprüft wird nur noch, dass die
erste Ziffer zwischen 1 und 9 liegt: der Baum hat neun Wurzeln.

**Schichtart und Gruppe greifen an zwei gemessenen Stellen ineinander:** `gruppe: daemmung`
ohne Schichtart ergibt eine Dämmschicht (4.932 von 5.042 Schichten der Gruppe 5 tragen
LayerType 3; LayerType 0 mit MaterialType 1 kommt im Bestand nicht vor), und `gruppe: holz`
setzt MaterialType 12 (5.289 von 5.381 der Gruppe 6; der Typ kommt in keiner anderen Gruppe
vor). Eine ausdrückliche Schichtart gewinnt. Ohne den zweiten Schritt trug eine Holzschicht
die richtige Farbe und den Typ „nichts" — sichtbar wurde nur das eine.

**Im Code:** [HottgenrothBauteilImport.php](../../app/Services/HottgenrothBauteilImport.php)
(`ARTEN`, `LAGEN`, `GRUPPEN`, `SCHICHTARTEN`, `MATERIALTYPEN`, `schicht()`, `schichtart()`, `katalogpfad()`)

**Bewacht durch:** `McpHottgenrothSchreibenTest::test_meter_statt_zentimeter_wird_abgewiesen`,
`McpHottgenrothSchreibenTest::test_gruppe_und_schichtart_reisen_in_der_sprache_des_bausteins`,
`McpHottgenrothSchreibenTest::test_ohne_gruppe_wird_keine_behauptet`,
`McpHottgenrothSchreibenTest::test_holz_traegt_seinen_materialtyp`,
`McpHottgenrothSchreibenTest::test_eine_daemmung_ohne_schichtart_ist_eine_daemmschicht`,
`McpHottgenrothSchreibenTest::test_ein_katalogpfad_darf_der_gruppe_widersprechen`,
`McpHottgenrothSchreibenTest::test_ein_katalogpfad_ausserhalb_der_neun_wurzeln_wird_abgewiesen`,
`McpHottgenrothSchreibenTest::test_bauteile_werden_in_zentimetern_uebergeben_und_in_metern_geschrieben`,
`McpHottgenrothSchreibenTest::test_eine_unbekannte_lage_nennt_die_erlaubten`

---

## HA-08 — Ein fehlendes Projekt ist zuerst ein alter Spiegel, keine Abwesenheit

**Regel:** Bevor eine Auskunft „dieses Projekt gibt es auf dem Arbeitsplatz
nicht" sagt, wird die Projektliste einmal aufgefrischt
(`update_hottgenroth_projects`). Die Liste nennt dafür ihren eigenen Stand, und
die Werkzeugbeschreibung nennt den Griff.

**Warum:** Die Projektliste hing an drei Anlässen, die alle auf dem Server
entstehen: Anmeldung des Agenten, Klick in der Verwaltung, Import über den
Server. Ein Berater, der in Hottgenroth ein Projekt anlegt oder eine `.sqproj`
von Hand einspielt, löst keinen davon aus — sein neues Projekt ist auf dem
Rechner da und im Spiegel nicht. Am 16.09.2026 stand deshalb die Frage im Raum,
ob ein importiertes Projekt fehlt oder bloß noch nicht gespiegelt ist, und von
einem Agenten aus war sie nicht zu beantworten: für die Bauteile gab es einen
Abruf, für die Liste selbst keinen.

**Im Code:** [UpdateHottgenrothProjectsTool.php](../../app/Ai/Tools/Hottgenroth/UpdateHottgenrothProjectsTool.php) ·
[HottgenrothAbbild.php](../../app/Services/HottgenrothAbbild.php) (`fordereAn()`, Sperre gegen Doppelaufträge) ·
`abbildHinweis()` in [HottgenrothWerkzeug.php](../../app/Ai/Tools/Hottgenroth/HottgenrothWerkzeug.php)

**Bewacht durch:** `McpHottgenrothTest::test_die_projektliste_laesst_sich_auffrischen`,
`McpHottgenrothTest::test_zweimal_auffrischen_stellt_keinen_zweiten_abbild_auftrag`,
`McpHottgenrothTest::test_ein_arbeitsplatz_ohne_sql_query_wird_nicht_angestossen`

---

## HA-06 — Variantenbeträge sind kumulativ, die Paketinvestition ist die Differenz

**Regel:** Jede Auskunft über Sanierungsvarianten nennt neben den kumulierten
Kosten einer Variante den **Zuwachs gegenüber der vorigen**
(`kosten.investition_paket`) und sagt dazu, dass die Beträge kumulativ sind. Das
gilt auch, wenn nur eine einzelne Variante abgefragt wird — der Zuwachs wird
dann trotzdem aus dem Vorgänger gebildet.

**Warum:** Ein Maßnahmenpaket enthält im Container die Maßnahmen aller
vorangehenden Pakete noch einmal. Wer die ausgewiesenen Summen der fünf Pakete
addiert, zählt die Dachdämmung fünfmal und bekommt eine Investitionssumme, die
um ein Vielfaches zu hoch ist — und die niemandem auffällt, weil jede einzelne
Zahl stimmt. Am 15.09.2026 lagen die kumulierten Beträge bei Baumöhl zwischen
53.502 € und 144.277 €; die Summe der Pakete wäre 465.000 € gewesen statt der
richtigen 144.277 €.

Dasselbe gilt für die **Sowieso-Kosten**: sie stehen nirgends gespeichert,
sondern sind `SANKOSTEN − SANKOSTEN_EE`. Wer nur die Gesamtkosten weitergibt,
lässt die Zahl weg, die über die Förderung entscheidet.

**Im Code:** [GetHottgenrothSanierungsvariantenTool.php](../../app/Ai/Tools/Hottgenroth/GetHottgenrothSanierungsvariantenTool.php)
(`variante()`, `kosten()`) ·
[Export-Sanierungsvarianten.ps1](../../hottgenroth-agent/tools/Export-Sanierungsvarianten.ps1)

**Bewacht durch:** `McpHottgenrothVariantenTest::test_die_investition_eines_pakets_ist_der_zuwachs_nicht_die_summe`,
`McpHottgenrothVariantenTest::test_eine_einzelne_variante_behaelt_ihren_zuwachs`,
`McpHottgenrothVariantenTest::test_massnahmen_werden_zusammengefasst_und_kostenlose_gemeldet`

---

## HA-07 — Eine Zuweisung wird erst geschrieben, wenn ihr Vorher-Zustand festgehalten ist

**Regel:** Ein Auftrag, der `BmElement` ändert, liest die betroffenen Zeilen
vorher vollständig und legt sie als Beleg an den Vorgang, **bevor** die erste
Änderung geschrieben wird — je Fläche `CatalogBasisUUID`, `CatalogDimUUID`,
`CatalogBasisElementType`, `CatalogBasisGroupType`, `UValue`, `ElementUValue` und
`UValueMarker`. Davor steht ein `assert` darauf, dass keine Projektsoftware
läuft, und eine Zählprobe, dass jede genannte `element_uid` zu diesem Projekt
und zu `RepositoryType = 1` gehört. Das `UPDATE` selbst trägt `expectedRows`.

**Warum:** Alles bisher Schreibende in diesem Bereich macht `INSERT`s —
misslingt einer, fehlt etwas, und man sieht es. Eine Zuweisung ändert Zeilen,
die es schon gibt. Misslingt sie halb, steht dort ein Zustand, den niemand
hergestellt hat, und der vorige steht **nirgends**: der Spiegel kennt weder
`CatalogDimUUID` noch den Marker und ist Minuten bis Tage alt.

Dazu kommen zwei Fallen, die beide nicht auffallen:

- **Eine laufende Anwendung verwirft die Änderung still.** Sie hält das Projekt
  als Objektmodell im Speicher und serialisiert es beim Beenden zurück. `INSERT`s
  überleben das, `UPDATE`s nicht (gemessen 07.08.2026: ein gesetzter
  `TcBasis.UsageType` stand kurz darauf wieder auf dem alten Wert, mit passend
  umgeschriebenen Rsi/Rse). Das Tor dafür war bis zum 19.09.2026 kaputt:
  `agent.diagnose` zählte `HsetuServices` mit — einen Hintergrunddienst, der
  ständig läuft — und kannte weder `EEBerater` noch `HottCAD`.
- **`RepositoryType` gehört in jede Bedingung, nicht nur in den Spiegel.**
  `BmElement` hält dasselbe Haus zweimal, und die beiden Hälften werden
  **unterschiedlich** beschrieben — welche Spalte wohin gehört, steht unten.

**Eine Zuweisung trifft BEIDE Repositories — korrigiert am 19.09.2026.** Hier
stand bis dahin, die Zeichnung gehöre nicht dazu. Das war aus der Abwesenheit
von `CADXMLData` an Repo-1-Flächen geschlossen (keine einzige der 19.917 trägt
eine; die 5.014 hängen an Repo 3) und ist als Aussage über `CADXMLData` weiter
richtig — als Aussage über die Zuweisung war es falsch.

Gemessen an einer von Hand ausgeführten Zuweisung im EE-Berater
(`bauteile/tools/snapshots/00-vorher` gegen `01-aw-angelegt`): die Software hat
**35 Zeilen** auf die neue Konstruktion gesetzt — **22 in Repo 1** (die
Teilflächen) und **13 in Repo 3** (11 Zeichnungsobjekte `EW 001`…`EW 015`, dazu
zwei Dächer als Nebenwirkung des Speicherns). Wer nur Repo 1 schreibt, lässt das
gezeichnete Bauteil auf der alten Konstruktion stehen; HottCAD liest die
Zeichnung zurück und rechnet Abgeleitetes selbst nach.

**Die beiden Hälften bekommen NICHT dasselbe:**

| Spalte | Repo 1 (Teilfläche) | Repo 3 (Zeichnungsobjekt) |
|---|---|---|
| `CatalogBasisUUID`, `CatalogDimUUID` | ja | ja |
| `CatalogBasisElementType` = 2, `CatalogBasisGroupType` | ja | ja |
| `UValue`, `ElementUValue` | ja | ja |
| `UValueMarker` | der **Name** der Zeile (`EW 003-2`) | **nicht anfassen** |
| `CoatingThickness` = 0 | ja | nein |

`UValueMarker` ist am Zeichnungsobjekt ein Typcode, den die Software aus der
Wanddicke bildet — in derselben Messung bekamen `EW 001/002/009/010/011/014`
den Wert `AW_36_5` und `EW 003/004/012/013/015` den Wert `AW_24_0`. Einen
solchen Code zu raten hieße, eine Aussage über die Konstruktion zu erfinden;
deshalb bleibt die Spalte dort unberührt.

**Im Code:** [HottgenrothBauteilZuweisung.php](../../app/Services/HottgenrothBauteilZuweisung.php)
(`schritte()`, `flaechenPruefen()`, `lagePruefen()`) ·
[AddComponentsTool.php](../../app/Ai/Tools/Hottgenroth/AddComponentsTool.php) ·
`DiagnosePrimitive` in [UtilityPrimitives.cs](../../hottgenroth-agent/src/HottgenrothAgent/Steps/Primitives/UtilityPrimitives.cs)

**Bewacht durch:** `McpHottgenrothZuweisenTest::test_der_auftrag_prueft_und_belegt_vor_dem_schreiben`,
`McpHottgenrothZuweisenTest::test_der_auftrag_bricht_bei_laufender_software_ab`,
`McpHottgenrothZuweisenTest::test_jede_bedingung_nennt_das_gerechnete_gebaeude`,
`McpHottgenrothZuweisenTest::test_das_update_ist_auf_die_zahl_der_flaechen_festgenagelt`,
`McpHottgenrothZuweisenTest::test_eine_fremde_flaeche_wird_abgewiesen`

---

## HA-09 — Ein fehlender Bauteilkatalog wird angelegt, nicht gemeldet

**Regel:** Fehlt einem Projekt der `TcCatalog` oder der Ordner für eigene
Bauteile, legt der Arbeitsplatz beides an, statt abzubrechen. Angelegt wird durch
**Klonen einer vorhandenen Zeile** derselben Datenbank, innerhalb der Transaktion
des Auftrags — ein Probelauf rollt den Katalog also mit zurück. `TIMUId` wird
dabei **neu vergeben**, nie übernommen.

**Der Ordner wird über seinen NAMEN gesucht**
(`LongDesc = '=== Benutzerdefinierte Bauteile ==='`), nicht über
`CatalogContainerType = 6`.

**Warum:** Am 19.09.2026 über alle 213 Projekte der lokalen `(localdb)\HSETU`
gezählt:

| Lage | Projekte |
|---|---:|
| kein `TcCatalog` | 27 |
| Katalog, aber kein Typ-6-Ordner | 12 |
| Typ-6-Ordner da, aber nicht der Benutzerordner | **47** |
| in Ordnung | 116 |

Die ersten beiden brachen laut ab, mit der Aufforderung „das Projekt einmal in
der Software öffnen und speichern“. Bei 39 Projekten ist das keine Anweisung,
sondern ein Nachmittag — und es trifft genau die Projekte, die vom Zeichner
kommen und noch nie geöffnet wurden.

**Die dritte Zeile ist die gefährliche.** `CatalogContainerType = 6` ist nicht
der Benutzerordner: unter demselben Typ liegen auch „DIN 4108 Bbl 2: 2019 - 06“
(Wärmebrücken, 13×), „Anlagenkomponenten Simulation“ (11×) und namenlose
(28×). Die alte Abfrage nahm `TOP 1` und hätte bei 47 Projekten einen **fremden
Ordner** getroffen — ohne Fehlermeldung. Das Bauteil wäre entstanden und hätte
in der Wärmebrückenablage gestanden.

**Warum `TIMUId` neu vergeben wird:** 125 verschiedene Werte auf 181 Zeilen, und
keiner davon zeigt auf einen Katalog in `HsetuAppTimData` (0 Treffer). Es ist
eine Kennung je Katalog. Die eines fremden Projekts mitzukopieren hieße, zwei
Kataloge dieselbe tragen zu lassen.

**Abgenommen an der Wirkung, nicht an den Zeilen.** Am 19.09.2026 am Projekt
M4NH3 (vom Zeichner, nie geöffnet): Katalog und Ordner von außen angelegt, dann
den EE-Berater geöffnet. Unter „Bauteile im Projektkatalog“ stand die Außenwand
mit U = 1,035 W/(m²K) und 61,5 cm — genau den Werten, die der Arbeitsplatz
gerechnet hatte, samt Schichtvorschau. Ein von außen angelegter Katalog ist für
die Software also gleichwertig.

Nebenbei der Name, an dem man sucht: intern heißt der Ordner
„=== Benutzerdefinierte Bauteile ===“, in der Oberfläche steht er als
**„Bauteile im Projektkatalog“**.

**Im Code:** `KatalogAsync()`, `LiesOderLegeKatalogAn()`, `LiesOderLegeOrdnerAn()`
in [BauteilWriter.cs](../../hottgenroth-agent/src/HottgenrothAgent/Hottgenroth/BauteilWriter.cs)

**Bewacht durch:** — (Agentseite; abgenommen von Hand, siehe oben)

---

## HA-10 — Aus Drive holt der Server die Projektdatei selbst

**Regel:** `import_hottgenroth_projekt` nimmt mit `drive_datei` eine Drive-ID,
einen Drive-Link oder einen **genauen** Dateinamen mit `.sqproj`. Der Server lädt
die Datei über die app-weit geteilte Drive-Verbindung in denselben Upload-Ordner
wie `POST /api/mcp/dateien`; ab dort läuft alles wie beim Upload. Dabei gilt:

- Ein Name, den es mehrmals gibt, wird **nicht** aufgelöst — zurück kommt die
  Liste mit Ordner und Datum.
- Geprüft wird **vor** dem Laden (Endung, kein Google-Format, höchstens 40 MB)
  und **danach** (Bytezahl und MD5 wie von Drive gemeldet, SQLite-Kopf). Was
  durchfällt, wird weder abgelegt noch eingestellt.
- Läuft ein Import derselben Drive-Datei noch, kommt er zurück. Ist derselbe
  **Inhalt** (MD5) auf diesem Arbeitsplatz schon erfolgreich eingespielt, kommt
  `schon_importiert`, und nichts wird angestoßen — außer mit `erneut: true`.
  Beide Proben laufen **vor** dem Download.

**Warum:** Die Exporte liegen im Kundenordner in Drive, und das Modell am
claude.ai-Connector hat nur Werkzeugaufrufe — einen HTTP-Upload kann es nicht
machen. Der Upload-Weg (HA-04) war für diesen Aufrufer also gar keiner: das
Werkzeug existierte, war aber vom Connector aus nicht erreichbar. Der Server hat
die Datei dagegen eine Leitung weiter.

Die Prüfung nach dem Laden gehört dazu, weil ein abgeschnittener Download
dieselbe Antwort hätte wie ein ganzer — der Fehler zeigte sich erst Minuten
später auf dem Rechner des Beraters, als gescheiterter Import ohne erkennbaren
Grund.

Die Probe auf den **erledigten** Import ist neu gegenüber dem Upload, und das
mit Absicht: beim Upload ist jede Wiederholung ein neuer Upload und damit eine
bewusste Handlung. Aus Drive ist sie derselbe Aufruf noch einmal — und das
typische Muster dahinter ist ein Modell, das das Projekt im alten Spiegel nicht
findet (HA-08) und den Import für gescheitert hält. Verglichen wird der Inhalt,
nicht nur die ID: legt die Drive-Synchronisation einen neuen Export über den
alten, bleibt die ID gleich, der Stand ist aber ein anderer.

**Bewusst in Kauf genommen:** Die Drive-Verbindung ist die der Firma, nicht die
des Aufrufers. Wer `hottgenroth:schreiben` hat, erreicht damit jede `.sqproj`,
die diese Verbindung sieht — auch die eines Kollegen. Das Ziel bleibt dabei
immer der **eigene** Arbeitsplatz (HA-03), und mehr als SQLite-Dateien mit der
Endung `.sqproj` kommen nicht durch.

**Im Code:** [HottgenrothDriveDatei.php](../../app/Services/HottgenrothDriveDatei.php) ·
`ausDrive()`, `fruehererImport()` in [ImportHottgenrothProjektTool.php](../../app/Ai/Tools/Hottgenroth/ImportHottgenrothProjektTool.php)

**Bewacht durch:** `McpHottgenrothDriveImportTest::test_ein_doppelter_name_wird_nicht_geraten`,
`McpHottgenrothDriveImportTest::test_derselbe_inhalt_wird_nicht_ein_zweites_mal_eingespielt`,
`McpHottgenrothDriveImportTest::test_ein_neuer_stand_unter_derselben_id_darf_durch`,
`McpHottgenrothDriveImportTest::test_ein_abgeschnittener_download_wird_erkannt`,
`McpHottgenrothDriveImportTest::test_was_keine_sqlite_datei_ist_wird_nicht_eingestellt`

---

## HA-11 — Eine gesetzte Anlagentechnik ist erst gerechnet, wenn ein Mensch die Variante geöffnet hat

**Regel:** `set_hottgenroth_heizung` schreibt den DIN-18599-Objektgraph in eine
Variante und meldet ausdrücklich **nicht** „fertig". Die Antwort nennt drei
Schritte: `get_vorgang` (ob geschrieben wurde), dann **der Berater öffnet Projekt
und Variante in der Software und speichert**, dann `get_hottgenroth_heizung` — und
erst wenn sich dort die **Endenergie** bewegt hat, ist die Anlage angekommen.
Solange das nicht geprüft ist, sagt die Auskunft „geschrieben, nicht gerechnet",
und es wird keine Zahl genannt, die auf der neuen Anlage beruht.

**Warum:** Am 13.08.2026 lief ein vollständiger Sanierungsfahrplan durch alle
Prüfungen und war trotzdem falsch. Alle Prüfungen waren Selbstprüfungen —
byte-identische Rückschreibprobe, Satzzahl gegen Kopf, Rundlauf über 84
Projekte. Sie beantworten ausschließlich „steht da, was ich geschrieben habe",
nie „erreicht es die Stelle, die rechnet". Der Grund liegt im Datenmodell: der
Blob wird beim Anlegen einer Variante unverändert mitkopiert, und die Software
gleicht ihn **erst beim Öffnen der Variante** ab. Nicht geöffnete Varianten
rechneten mit den Ist-Werten; die Nutzenergie sank um 6 % statt um ein Drittel.

Daraus folgt auch, wie „gerechnet" belegt wird: nicht am Blob, sondern am Satz in
`TableHeizung`. Der ist **Ergebnis, keine Eingabe** — die Software schreibt ihn
beim Rechnen. Fehlt er, ist nichts angekommen, unabhängig davon, dass die Variante
einen Blob führt (den führt fast jede). Für die Hülle ist die entsprechende Größe
`UA`; für die Anlagentechnik sagt `UA` nichts, weil eine Wärmepumpe keinen U-Wert
ändert.

**Und der Auftrag sagt selbst, ab wann er schreibt.** `payload.meta.schreibt_ab`
nennt den einen Schritt, der das Projekt verändert (`container.ps1 -Zurueck`).
Ohne diese Angabe würde die Vorgangsdeutung jeden `shell.run` für schreibend
halten — auch das Prüfen der Werkzeugkette —, und `get_vorgang` müsste nach jedem
Abbruch `ungewiss` melden. Bei einem nicht idempotenten Auftrag ist das die
teuerste aller Antworten.

Die Angabe allein genügt aber nicht: die Deutung braucht auch den **erreichten**
Schritt, und der steht nicht verlässlich in `progress_message` — dort liegt nur
die jüngste Meldung, und jeder `shell.run` meldet danach selbst weiter
(„Exit-Code 1, …"). Gelesen wird die Schrittzahl deshalb aus dem **Protokoll**.
Vorgang 191 vom 30.09.2026 scheiterte in Schritt 1 von 5 und meldete trotzdem
`ungewiss`, obwohl `schreibt_ab` gesetzt war.

**Im Code:** [HottgenrothHeizung.php](../../app/Services/HottgenrothHeizung.php)
(`schreibtAb()`, `auftragFuerSetzen()`) ·
`next_step` in [SetHottgenrothHeizungTool.php](../../app/Ai/Tools/Hottgenroth/SetHottgenrothHeizungTool.php) ·
[GetHottgenrothHeizungTool.php](../../app/Ai/Tools/Hottgenroth/GetHottgenrothHeizungTool.php) ·
`werkzeuge/bdexit/zeige-heizung.ps1` (außerhalb des Repos, siehe HOTTGENROTH_WERKZEUGE)

**Bewacht durch:** `McpHottgenrothHeizungTest::test_setzen_meldet_ab_wann_es_das_projekt_veraendert`,
`McpHottgenrothHeizungTest::test_lesen_meldet_dass_es_nirgends_schreibt`,
`McpHottgenrothHeizungTest::test_lesen_schreibt_nichts_zurueck`,
`McpGetVorgangTest::test_eine_ueberschriebene_meldung_macht_die_antwort_nicht_ungewiss`

---

## HA-12 — Bilder gehören in die Bilderverwaltung, nicht in die iSFP-XML

**Regel:** Ein Foto eines Projekts wird als Zeile in `PrMedia` angelegt
(`MediaType` 14), nie als Stream in `PrMedia.iSFP2.xml`. Die vier Angaben daran
sind `XimMediaType` (**Funktion**), `Category` (Reihenfolge), `LongDesc` (Name — die
Oberfläche zeigt nur diesen, `ShortDesc` wird mitgeschrieben) und `InfoDesc` (Beschreibung); `MediaCopyright` trägt die Bildquelle. Die
Funktion ist **Pflicht** — `import_hottgenroth_bilder` kennt vier Namen und
keine freie Zahl.

**Warum:** Am 27.09.2026 sah ein Abgleich zwischen dem Projekt Klenke und seinem
fertigen Fahrplan zehn Fotos in der `.mSFPprojekt`-Datei und null im Projekt. Der
naheliegende Schluss — „die Bilder fehlen in Hottgenroth" — war falsch: die
Bilder lagen die ganze Zeit in `PrMedia`, und in **allen 59 Projekten der
LocalDB** ist jeder Foto-Stream in der `iSFP2.xml` leer. Die Software setzt die
Bytes erst ein, wenn sie die `.mSFPprojekt` für die Druckanwendung erzeugt. Ein
Werkzeug, das Fotos in die XML schriebe, schriebe an eine Stelle, die niemand
liest — und die beim nächsten Erzeugen überschrieben wird.

Die Zuordnung ist Feld für Feld an zwei fremden Projekten nachgewiesen: die
Anzahl der Zeilen je `XimMediaType` stimmt exakt mit den `item`-Knoten unter
`fotos/` überein, und die Reihenfolge folgt `Category`.

| `XimMediaType` | im iSFP | Anzahl |
|---|---|---|
| 10 | `fotos/titel` | 1 |
| 12 | `fotos/fotoHeute/item` | 4 |
| 13 | `fotos/ansichten/item` | beliebig |
| 1 | Unterlage, erscheint nicht im Fahrplan | beliebig |
| 17 | Zonierung, erscheint nicht im Fahrplan | beliebig |
| 18 | Systemgrenze, erscheint nicht im Fahrplan | beliebig |
| 11 | Unterschrift, setzen die Berichte der Software ein | 1 |
| 0 | **nirgends** | — |

**`XimMediaType` 0 ist die Falle.** Die Oberfläche lässt ein Foto ohne Zuordnung
ablegen; es liegt dann im Projekt und in keinem Fahrplan. Bei Klenke waren es
zwei. Deshalb ist die Funktion im Schema Pflicht und `0` keine Wahlmöglichkeit.

**Die Gegenrichtung gibt es nicht.** Was in `MeinSanierungsfahrplan.exe`
entsteht, erreicht Hottgenroth nie, und die Druckanwendung rechnet beim Speichern
jedes Bild auf rund 300 px herunter. Die Fassung im Projekt ist deshalb bei
Skizzen und Fotos immer die bessere — zurückholen verschlechtert sie.

**Ein neuer Satz übernimmt die Schreibweise seines Projekts.** Über 932
Bildsätze gemessen gibt es zwei, und beide kommen in Projekten vor, die
einwandfrei drucken: das **volle Muster** (868 Sätze, `GId` ist eine eigene
Kennung, `VariantRoot` trägt eine dritte in geschweiften Klammern) und das
**einfache** (64 Sätze, `GId` = `UUID`, `VariantRoot` leer). `VariantRoot` zeigt
dabei auf nichts — weder auf `UUID` noch auf das Projekt, und nur in 25 von 868
Fällen auf `GId`. Auch `MediaType` (14 oder 15) und `Id` (−1 oder eine echte
Nummer) schwanken. Welches richtig ist, entscheidet deshalb nicht das Skript,
sondern das Projekt: `Import-Bilder.ps1` liest den letzten vorhandenen Bildsatz
und schreibt den neuen genauso. Aus **einem** Satz zu schließen hätte hier
danebengelegen — der Entwurf tat es und erzeugte Zeilen, die neben ihren
Geschwistern auffielen.

**Im Code:** [HottgenrothBilder.php](../../app/Services/HottgenrothBilder.php)
(`FUNKTIONEN`, `schreibtAb()`) ·
[ImportHottgenrothBilderTool.php](../../app/Ai/Tools/Hottgenroth/ImportHottgenrothBilderTool.php) ·
[Import-Bilder.ps1](../../hottgenroth-agent/tools/Import-Bilder.ps1) ·
[McpDateiController.php](../../app/Http/Controllers/Ai/McpDateiController.php) (`ARTEN`)

**Bewacht durch:** `McpHottgenrothBilderTest::test_funktion_ohne_zuordnung_gibt_es_nicht`,
`McpHottgenrothBilderTest::test_auftrag_schreibt_erst_beim_anlegen`,
`McpHottgenrothBilderTest::test_bilder_gehen_nicht_in_die_isfp_xml`

---

## HA-16 — Eine neue Agent-Fassung wird erst geglaubt, wenn sie sich gemeldet hat

**Regel:** Der Agent tauscht sich beim Start selbst gegen eine neuere Fassung aus,
aber erst, nachdem drei Tore passiert sind: Größe, SHA-256 und ein Probelauf
`--version`, dessen Antwort der angebotenen Fassung entsprechen muss. Die
Vorgängerfassung bleibt danach liegen, bis die neue sich **beim Server angemeldet**
hat. Scheitert irgendetwas, bleibt die laufende Fassung unberührt und der Agent
arbeitet weiter.

**Warum:** Auf dem Rechner eines Beraters gibt es niemanden, der eine kaputte
Aktualisierung bemerkt und repariert — der Agent ist dort unsichtbar, bis er
fehlt. Jedes der drei Tore verhindert einen eigenen Weg dorthin: ein abgebrochener
Download (Größe), eine unterwegs veränderte Datei (Prüfsumme), und eine Exe, die
zwar vollständig ankommt, aber auf diesem Rechner nicht startet (Probelauf). Das
dritte ist das wichtigste und zugleich der Grund, warum `--version` ohne
Konfiguration, ohne Verzeichnis und ohne Netz auskommen muss (seit 2.5.2).

**Der Rückweg wird spät weggeworfen** (seit 2.5.5): Eine Fassung, die startet und
`--version` beantwortet, sich aber beim Server nicht anmelden kann, ist auf einem
Arbeitsplatz genauso unbrauchbar wie eine, die gar nicht startet. 2.5.4 löschte die
Vorgängerfassung schon beim Start der neuen — genau zwischen diesen beiden Punkten
lag die Lücke. Sie kostet 122 MB; das ist der Preis dafür, dass der Rückweg
existiert, solange er gebraucht wird.

**Umbenennen, nicht überschreiben.** Eine laufende Exe lässt sich unter Windows
nicht überschreiben und nicht löschen — umbenennen aber schon. Darauf beruht der
ganze Ablauf, und deshalb braucht es keinen zweiten Prozess, der zusieht.

**Beim Start, nicht im Poll.** Der Poll läuft alle 15 Sekunden; dort zu fragen
hieße, viertausendmal am Tag dieselbe Antwort zu bekommen. Die Anmeldung geschieht
einmal je Start — und nur dann läuft kein Auftrag, der mittendrin abbräche. Mit
`--once` bleibt die Prüfung aus.

**Serverseitig wird nur angeboten, was NEUER ist** (`version_compare`, nicht
Ungleichheit), und nur, wenn der Zeiger `releases/aktuell.json` auf eine Datei
zeigt, die wirklich da ist. Ein Arbeitsplatz ohne lesbare Fassungsangabe bekommt
nichts — er könnte auch nach dem Austausch keine melden und liefe bei jedem Start
in dieselbe Aktualisierung.

**Die erste Fassung kommt immer von Hand.** Ein Agent, der die Selbstaktualisierung
noch nicht kennt, kann sie nicht benutzen; 2.5.3 ignorierte das Angebot
vollständig. Ab 2.5.4 geht es allein.

**Im Code:** [HottgenrothRelease.php](../../app/Services/HottgenrothRelease.php) ·
[HottgenrothReleaseCommand.php](../../app/Console/Commands/HottgenrothReleaseCommand.php) ·
`Selbstaktualisierung.cs` und `Program.cs` im Agenten

**Bewacht durch:** `HottgenrothReleaseTest` (neun Zusicherungen, die vor allem
prüfen, wann NICHTS angeboten wird) · am 04.10.2026 am laufenden Arbeitsplatz
gemessen: 2.5.4 startet, bekommt 2.5.5 angeboten, prüft, tauscht, startet neu und
meldet sich als 2.5.5 beim Server.

---

## HA-17 — Die Grenze eines Bausteins ist nicht die Grenze der Software

**Regel:** Kann ein Werkzeug etwas nicht, nennt es die Grenze **als seine eigene** und
sagt, wo der Weg sonst entlangführt. Ein Werkzeug sagt nie „das Feature gibt es
nicht", wenn es das Feature gibt.

**Warum:** Am 04.10.2026 bekam ein Berater auf die Frage nach einer inhomogenen
Schicht die Antwort „unsere Schnittstelle kann das nicht" — richtig — und daraus
abgeleitet, es sei in der Software nicht anlegbar. Das war falsch: Hottgenroth führt
1.306 inhomogene Bauteile, und das Schema dafür liegt seit dem 07.08.2026
auseinandergenommen in `bauteile/docs/hottgenroth-bauteil-sql.md`, Abschnitt 9a, mit
einem fertigen Beispiel für genau diesen Bauteiltyp. Der Berater hat die Decke
daraufhin selbst im Bauteileditor angelegt — der Weg war also sogar der bequemste von
dreien.

Der Schluss entstand **aus dem Schweigen**: `get_hottgenroth_components` meldet
`inhomogen`, `gefach` und `gefach_anteil`, `add_hottgenroth_bauteile` erwähnte das
Thema mit keinem Wort. Wer beim Lesen etwas sieht und beim Schreiben nichts findet,
deutet das als Abwesenheit. Eine Lücke in einer Werkzeugbeschreibung ist deshalb nicht
neutral — sie wird zu einer Aussage, und zwar zur falschen.

Das kostet doppelt: der Berater verzichtet auf etwas, das er haben könnte, und er
verliert Vertrauen in die übrigen Auskünfte, sobald er merkt, dass es doch ging.

**Im Code:** [AddHottgenrothBauteileTool.php](../../app/Ai/Tools/Hottgenroth/AddHottgenrothBauteileTool.php)
(`beschreibung()`) · [ki-hottgenroth.md](../ki-hottgenroth.md), Abschnitt
`add_hottgenroth_bauteile`

**Bewacht durch:** `DokumentationTest::test_werkzeugbeschreibungen_tragen_die_fachfallen`

---

## HA-14 — Eine Variante wird über ihren Namen gewählt, nicht über ihre Nummer

**Regel:** Werkzeuge, die eine einzelne Sanierungsvariante treffen, adressieren sie
über `VarianteBez` — den Namen. Die laufende Nummer (`PROJEKT_ID` im Container) wird
nicht übergeben und nicht gemerkt.

**Warum:** Sie ist flüchtig. Werden Varianten gelöscht, vergibt die Software die
Nummern neu. Im Projekt V4DZX trug dasselbe Maßnahmenpaket am 03.10.2026 die **12**
und am 04.10.2026 die **3**, nachdem fünf Varianten entfernt worden waren. Ein
Auftrag, der eine gemerkte Nummer mitbringt, trifft danach lautlos eine andere
Variante — und das fällt nirgends auf, weil jede Nummer für sich gültig ist.
Dieselbe Lehre wie bei `HUELL_ID`, nur eine Ebene höher. Erschwerend: es gibt
**zwei** Nummern, die beide „Variante" heißen —
`get_hottgenroth_sanierungsvarianten` meldet eine Position (0 = Ist-Zustand), der
Container führt `PROJEKT_ID`, und die beiden stimmen nicht überein.

Der Name ändert sich nur, wenn ihn jemand ändert. Er muss Zeichen für Zeichen aus
`get_hottgenroth_sanierungsvarianten` kommen, denn die Software kürzt lange Namen im
Container ab (aus „MP6 EH 85 – Kundenziel (aus Ist-Zustand)" wird
„MP6 EH 85 – Kundenziel (aus Ist-Zus").

**Im Code:** [HottgenrothCadBindung.php](../../app/Services/HottgenrothCadBindung.php)
(`auftrag()`) · [Set-CadBindung.ps1](../../hottgenroth-agent/tools/Set-CadBindung.ps1)
(Auflösung über `TableProjekt.VarianteBez`)

**Bewacht durch:** `McpHottgenrothSchreibenTest::test_die_cad_bindung_reist_mit_dem_namen`,
`McpHottgenrothSchreibenTest::test_der_ist_zustand_wird_nicht_geloest`

---

## HA-15 — Die CAD-Bindung zu lösen gibt etwas auf, deshalb fragt es vorher

**Regel:** `set_hottgenroth_cad_bindung` nennt in Beschreibung und Antwort, was eine
gelöste Variante verliert: sie folgt dem HottCAD-Modell nicht mehr. Der Probelauf ist
der erste Aufruf, und der Arbeitsordner mit der Containersicherung bleibt nach einem
echten Lauf stehen.

**Warum:** Es ist keine Reparatur, sondern ein Tausch. Die Sperre („Diese Ansicht ist
rein informativ") ist kein Fehler, sondern die Folge davon, dass die Geometrie der
Zeichnung gehört — gemessen am 04.10.2026 hängt sie an genau einem Feld,
`TableZusatz.ProjektPfad3D` mit dem Wert `Art=CAD`. Wer es herausnimmt, bekommt die
tabellarische Bearbeitung und verliert, dass spätere Änderungen an der Zeichnung
ankommen. Ein Werkzeug, das das stillschweigend täte, nähme dem Berater eine
Entscheidung ab, deren Folge er erst Wochen später bemerkt — beim nächsten
Zeichnungsstand, der nicht mehr durchschlägt.

Deshalb schreibt der Arbeitsplatz auch nur **eine** Tabelle neu (`TableZusatz`),
prüft vorher jede Tabelle des Containers Satz für Satz gegen die Satzzahl im Kopf,
legt eine Sicherung des ganzen Containers an und liest nach dem Schreiben aus der
Datenbank zurück statt aus dem Speicher. Läuft die Software, wird abgewiesen statt
überschrieben.

**Im Code:** [SetHottgenrothCadBindungTool.php](../../app/Ai/Tools/Hottgenroth/SetHottgenrothCadBindungTool.php)
(`beschreibung()`, `antwort()`) · [HottgenrothCadBindung.php](../../app/Services/HottgenrothCadBindung.php)

**Bewacht durch:** `McpHottgenrothSchreibenTest::test_die_cad_bindung_nennt_den_preis`,
`McpHottgenrothSchreibenTest::test_der_probelauf_raeumt_auf_der_echte_lauf_nicht`,
`DokumentationTest::test_werkzeugbeschreibungen_tragen_die_fachfallen`

---

## HA-13 — Varianten werden angehängt, nie ersetzt; gelöscht wird nur von Hand

**Regel:** `set_hottgenroth_sanierungsvarianten` legt neue Varianten **hinter**
die vorhandenen. Vorhandene werden nicht angefasst, und das Werkzeug löscht
keine — dafür gibt es keinen Weg und soll es keinen geben. Die Nummern vergibt
der **Arbeitsplatz** aus dem Container, nicht der Server. Was der Auftrag prüft,
ist nur noch, ob der Ist-Zustand da ist: ohne ihn zeigt die `VarianteID` jeder
neuen Variante ins Leere, und die Software meldet „Ist-Zustand nicht vorhanden!".

`basis` entscheidet die Vorlage: `kette` baut jede Variante auf der vorigen auf
(ein Fahrplan, Regel HA-06), `ist` baut jede auf dem Ist-Zustand auf (eine
einzelne Zielvariante neben einem bestehenden Fahrplan).

**Warum:** Bis zum 01.10.2026 brach der Auftrag ab, sobald das Projekt
überhaupt Varianten führte. Die Begründung war richtig — eine Variante trägt
Arbeit, die im Fahrplan nicht steht: Fotos, Texte, Kennwerte aus der iSFP-Maske
—, aber sie deckte den falschen Fall ab. Geschützt werden muss das **Löschen**,
nicht das Anlegen.

Am Projekt V4DZX_Nadine Klenke kostete das einen Abend: fünf Pakete vorhanden,
eine Zielvariante „EH 85 aus dem Ist-Zustand" gewünscht, Auftrag abgewiesen
(Vorgang 215). Der Ausweichvorschlag — Projekt kopieren, in der Kopie alle fünf
Varianten löschen — war aufwendiger und gefährlicher als das, was verhindert
werden sollte.

Serverseitig vergebene Nummern (`ist_zustand + lfd`) gingen damit ebenfalls
nicht mehr: im zweiten Lauf hätten sie auf vorhandene Varianten gezeigt, und die
Kopie hätte fremde Arbeit überschrieben. Deshalb ermittelt der erste Schritt die
nächste freie Nummer, und jeder spätere rechnet mit ihr.

**Im Code:** [HottgenrothSanierungsvarianten.php](../../app/Services/HottgenrothSanierungsvarianten.php)
(`bestandErmitteln()`, `nummer()`, `BASIS_KETTE`/`BASIS_IST`) ·
[SetHottgenrothSanierungsvariantenTool.php](../../app/Ai/Tools/Hottgenroth/SetHottgenrothSanierungsvariantenTool.php)

**Bewacht durch:** `McpHottgenrothVariantenSchreibenTest::test_ha13_der_auftrag_prueft_nicht_mehr_auf_leer_sondern_haengt_an`,
`McpHottgenrothVariantenSchreibenTest::test_die_variantennummer_kommt_vom_arbeitsplatz`,
`McpHottgenrothVariantenSchreibenTest::test_basis_ist_baut_jede_variante_aus_dem_ist_zustand`

---

## HA-18 — Ein Kontakt zählt erst, wenn die Software ihn so anlegt, wie sie es selbst täte

**Regel:** Wer einen Kontakt in ein Projekt schreibt (Eigentümer, Projektadresse, Planer),
setzt drei Dinge, die in keiner Fehlermeldung auftauchen, wenn sie fehlen:

1. eine **Kontaktart** (`ccePerson`, bei einer Firma `cceCompany`),
2. eine **Hauptadresse** (`SequenceType = mczSeq01`),
3. die Rolle **zweimal** — einmal am Kontakt selbst, einmal an der Projekt-Kontaktgruppe.

Und er schreibt nur bei **geschlossener** Software.

**Warum:** Am 10.10.2026 in vier Durchgängen am Testprojekt Modrak gemessen:

- Nur die Gruppenrolle gesetzt, Kontaktart und Hauptadresse leer: die Zeilen standen in
  `CmContact`, `CmAddress` und `CmContactRole`, die Reiter Projektadresse, Planer und
  Eigentümer blieben leer. Abgelesen wurde das Soll an „Nickels“, einem Projekt, dessen
  Reiter ein Mensch gefüllt hat: dort trägt jeder Kontakt `ContactType` 2 und eine
  Adresse mit `SequenceType` 1.
- Mit beidem, aber ohne Rolle am Kontakt: im Projekt selbst richtig — nach Export und
  Import (nativ wie über die Brücke) waren die Reiter wieder leer. Der Importer trägt
  einen Kontakt nur über die Rolle **am Kontakt** mit; die Gruppenrollen kamen mit und
  zeigten ins Leere, auf die Kontakt-GUIDs des Ursprungsprojekts.
- Mit allen dreien: richtig im Projekt und nach einem Re-Import.

Derselbe Doppelsinn der Rolle steht schon hinter dem Import-Nachzug vom 09.08.2026
(`HottgenrothBrueckenImport::kontaktschritte`) — dort von der anderen Seite: die Datei
bringt die Rolle am Kontakt, die Oberfläche liest die der Gruppe.

Geschlossene Software, weil eine laufende Instanz das Projekt im Speicher hält und beim
Beenden zurückschreibt; und weil sie die Kontakte nur beim Öffnen liest — ein offenes
Projekt zeigt neue Kontakte ohnehin erst nach einem Neustart.

**Im Code:** [HottgenrothHottcadProjekt.php](../../app/Services/HottgenrothHottcadProjekt.php)
(`kontakt()`, `auftrag()`) · [ki-hottgenroth.md](../ki-hottgenroth.md), Abschnitt
`create_hottcad_projekt`

**Bewacht durch:** `McpHottcadProjektTest::test_jeder_kontakt_hat_art_hauptadresse_und_beide_rollen`,
`McpHottcadProjektTest::test_der_auftrag_prueft_zuerst_die_software_und_spielt_dann_die_vorlage_ein`

---

## HA-19 — Exportiert wird mit dem Exporter der Software, und ein Export ist nie ein Grund, ein Projekt neu anzulegen

**Regel:** Eine `.sqproj` entsteht über `Hsetu.ImExporter.exe --parallel "-e|<XmProject.UUID>|<Ziel>"`
— das Programm, das die Oberfläche selbst startet —, nicht über eigene Zeilenkopien und nicht
über die Brücke. Sie geht nur hoch, wenn sie den SQLite-Kopf trägt und unter 128 MB liegt.
Hinter `create_hottcad_projekt` ist der Export **nachgeordnet**: sein Scheitern lässt den
Auftrag nicht scheitern, `get_vorgang` meldet `export_fehlt`. Herausgegeben wird die Datei
über einen **signierten, ablaufenden Link** (72 Stunden), nicht über den Adminbereich.

**Warum:** Am 10.10.2026 drei Wege verglichen. Die Brücke (`TFWSQLiteProjectExporter`) und
der native Exporter liefern beide eine vollständige Datei — Bauteilelemente, alle
`PrMedia`-Anhänge einschließlich `eberater.zip`, Kontakte, Bilder. Der native Weg ist die
Kommandozeile der Software selbst und übersteht Updates; die Brücke hängt an Klassen, deren
Form sich mit jeder Fassung ändern kann (während des Tests von 6.7.1 auf 6.7.8). Ohne
Oberfläche erprobt: 17 Sekunden, Exit-Code 0.

Der native Exporter **lässt die Rollen an der Projekt-Kontaktgruppe weg** und nimmt nur die
am Kontakt mit — die zweite Begründung für HA-18.

Nachgeordnet, weil das Projekt das Ergebnis ist und die Datei eine Zugabe: ließe ein
gescheiterter Upload (etwa über 128 MB) den ganzen Auftrag scheitern, stünde ein angelegtes
Projekt auf „fehlgeschlagen“, und der naheliegende zweite Aufruf legte es doppelt an. Die
128 MB sind die Grenze von Nginx (`client_max_body_size`) und PHP (`post_max_size`); eine
Datei darüber scheiterte erst mitten im Rumpf, ohne zu sagen, warum.

Der signierte Link, weil der Download im Adminbereich eine Sitzung mit Rolle `admin` oder
`projekte` verlangt: ein Berater am MCP — oder der Kollege, dem er den Link schickt — käme
damit nicht an die Datei, obwohl das Werkzeug ihm ihr Entstehen meldet. Dasselbe Muster wie
bei den Webmail-Anhängen: die Signatur ist die Berechtigung, die Laufzeit die Grenze.

**Im Code:** [HottgenrothSqprojExport.php](../../app/Services/HottgenrothSqprojExport.php)
(`exportBefehl()`, `schritte()`) ·
[ExportHottgenrothProjektTool.php](../../app/Ai/Tools/Hottgenroth/ExportHottgenrothProjektTool.php) ·
[GetVorgangTool.php](../../app/Ai/Tools/Hottgenroth/GetVorgangTool.php) (`exportFehlt()`)

**Bewacht durch:** `McpHottgenrothSqprojExportTest::test_eine_datei_ueber_128_mb_wird_nicht_hochgeladen`,
`McpHottcadProjektTest::test_zum_schluss_wird_in_die_fs_app_exportiert`,
`McpHottcadProjektTest::test_get_vorgang_meldet_einen_fehlenden_export`

---

## HA-20 — Ein Raumstempel steht an zwei Stellen, und die Rechnung sieht nur Räume in einer Zone

**Regel:** Wer Raumart, Name, Heizstatus oder Temperatur eines Raums setzt, setzt beide
Stellen — `BmRoom` **und** das CAD-XML in `BmData.ClassValue` — in einer Transaktion.
Ein Raum hängt in genau einer DIN-18599-Zone (`BmZoneReference`, `ZoneType 5`); beheizte
Räume gehören hinein, unbeheizte nicht. `set_hottgenroth_raeume` prüft vorher, dass keine
Hottgenroth-Anwendung läuft und jedes Geschoss mit Räumen zugeteilt ist, sichert die
Datenbank, richtet Zone und Profil nur ein, wenn sie fehlen, setzt dann Geschossebene und
Ausnahmen, und liest den Stand nach. `payload.meta.schreibt_ab` nennt den
Einrichtungsschritt; im Probelauf schreibt kein Schritt. Nur Raumarten mit belegter
`mrt*`-Bezeichnung dürfen gesetzt werden.

**Warum:** Am 18.10.2026 trug ein importierter Anbau 14 Räume mit den Standard-Stempeln der
Erkennung — „Kellerraum" im Obergeschoss, 15 °C im Wohnraum — und keine einzige
DIN-18599-Zone. Bauteile darauf zuzuweisen hätte eine Bilanz ergeben, die den Hauptwohnraum
als unbeheizten Lagerraum rechnet. Und wer nur eine der beiden Stellen setzt, hinterlässt ein
Modell, das sich selbst widerspricht: die Oberfläche zeigt die eine, gerechnet wird die
andere (`hottgenroth-raum-zone-sql.md`, Abschnitt 3). Eine laufende Anwendung verwirft die
Änderung still (HA-07). Ein erfundener `mrt*`-Name macht das XML unbrauchbar (Abschnitt 11).

**Im Code:** [HottgenrothRaeume.php](../../app/Services/HottgenrothRaeume.php) ·
[SetHottgenrothRaeumeTool.php](../../app/Ai/Tools/Hottgenroth/SetHottgenrothRaeumeTool.php) ·
[GetHottgenrothRaeumeTool.php](../../app/Ai/Tools/Hottgenroth/GetHottgenrothRaeumeTool.php) ·
`hottgenroth-agent/tools/Setup-Wohngebaeude.ps1`, `Set-Raumstempel.ps1`, `Set-Raum-Zone.ps1`,
`Get-Raeume.ps1` (Quelle: `bauteile/tools/`)

**Bewacht durch:** `McpHottgenrothRaeumeTest::test_setzen_baut_die_kette_in_der_richtigen_reihenfolge`,
`McpHottgenrothRaeumeTest::test_der_probelauf_schreibt_nirgends`,
`McpHottgenrothRaeumeTest::test_nur_raumarten_aus_dem_katalog`,
`McpHottgenrothRaeumeTest::test_get_vorgang_liefert_den_nachgelesenen_stand`

---

## Offene Lücken

- **Die Raumstempel sind über MCP noch nicht am echten Kundenprojekt geschrieben**
  (Stand 18.10.2026). Belegt ist der Auftragsbau und das lesende Skript gegen ein echtes
  Projekt (14 Räume, 0 Zonen); der schreibende Weg wurde bisher nur lokal mit
  `Setup-Wohngebaeude.ps1` an Pohlstraße gegangen. Der erste echte Lauf gehört dem
  Probelauf, danach der Wirkungsprobe in der Software (rechnet die Zone ihre Fläche nach?).
- **Die Raum-Skripte liegen zweimal im Repository:** als Quelle in `bauteile/tools/` und als
  Auslieferungskopie in `hottgenroth-agent/tools/` (nur die wird deployt und über
  `files/skripte/` ausgeliefert). Eine Änderung an der Quelle muss nachgezogen werden;
  einen Wächter dafür gibt es noch nicht.

- **Ein Projekt aus der Basisvorlage heißt wie die Vorlage.** `create_hottcad_projekt`
  macht es über die Gruppe wiederfindbar (`<Referenz>_<Kunde>_<Datum>`). Umbenennen über
  `TPrmProject.Name` und `MergeDALObject` direkt nach dem Import blieb am 10.10.2026 ohne
  Wirkung — `XmProject.LongDesc` und `PrProject.LongDesc` trugen danach weiter den alten
  Namen. Der Weg der Oberfläche zum Umbenennen ist noch nicht gelesen.
- **Die Verwaltungsansicht kennt beides noch nicht.** `/admin/hottgenroth` zeigt
  `synced_at` und einen laufenden Auftrag, aber weder den Speicherstand noch eine
  gescheiterte Übernahme am Projekt.
- **Hochgeladene Projektdateien sind für jeden Arbeitsplatz lesbar.** Der
  Download-Endpunkt des Agents (`files/{pfad}`) prüft das Token, nicht den
  Besitzer: ein beliebiger angemeldeter Arbeitsplatz könnte jede Datei unter
  `file_root` holen, wenn er ihren Namen kennt. Die Namen tragen eine
  Zufallskennung, das ist aber eine Hürde und keine Schranke. Gehört mit dem
  Download-Endpunkt zusammen behoben, nicht im Werkzeug.
- **Eingespielte Dateien bleiben liegen.** Nach einem erfolgreichen Import wird
  die .sqproj in der Ablage nicht aufgeräumt.
- **Der Import prüft nicht, ob die Software gerade läuft.** Er schreibt über die
  Brücke; sichtbar wird das Projekt erst nach einem Neustart des Energieberaters.
  Ob eine laufende Instanz den Import stören kann, ist nicht gemessen. Das Tor
  dafür gibt es seit dem 19.09.2026 (`projektsoftware_laeuft`, HA-07) — nur
  `add_components` benutzt es bisher.
- **Was die Software mit einer von außen gesetzten Zuweisung macht, ist nicht
  gemessen.** Dass die Zeile steht, ist belegt; dass die Bauteilerfassung sie
  zeigt und `UA` sich bewegt, nicht. Das ist die Wirkungsprobe, und sie gehört
  vor die Freigabe von `add_components` für echte Kundenprojekte.
- **Der Übernahmeweg fehlt.** Bauteile mit `herkunft = 'hottgenroth'` und ohne
  Schichten — Typologiewerte, Fenster, Türen — lassen sich nicht nachrechnen;
  sie müssten über ihre `quelle_ref` aus `HsetuAppTimData` kopiert werden.
  `add_components` weist sie derzeit mit `bauteil_nur_uebernehmbar` ab.
- **Ob `PrProject.StampEdit` jede Speicherung trifft, ist nicht belegt.**
  Beobachtet ist, dass er mit dem Speichern im Energieberater mitläuft. Ob ein
  Speichern allein in HottCAD ihn ebenfalls bewegt, hat niemand gemessen.
- **Die Anlagentechnik ist über MCP nicht am echten Kundenprojekt erprobt**
  (Stand 26.09.2026). Belegt ist der Auftragsbau (19 Zusicherungen) und die
  Werkzeugkette selbst, an vier Containern und einem echten Blob. Ein
  vollständiger Durchlauf über einen Arbeitsplatz — holen, setzen,
  zurückschreiben, rechnen lassen, Wirkungsprobe — hat noch nicht stattgefunden.
  Der erste echte Lauf gehört `get_hottgenroth_heizung`, nicht `set_`.
- **Die Werkzeugkette liegt in keinem Repository.** `HOTTGENROTH_WERKZEUGE` zeigt
  auf einen Ordner auf dem Rechner des Beraters (`werkzeuge/ibp`,
  `werkzeuge/bdexit`), und der ist heute nur auf einem Arbeitsplatz vorhanden.
  Solange es keinen Ausrollweg gibt, ist das Feature auf diesen einen Rechner
  beschränkt — erkennbar daran, dass der erste Schritt die fehlenden Dateien
  nennt.
- **Lüftung fehlt im Austauschformat.** Es führt Heizung, Speicher und
  Warmwasser. Zu einem Effizienzhaus gehört eine Lüftungsanlage; die ist über
  diese Kette nicht setzbar.
