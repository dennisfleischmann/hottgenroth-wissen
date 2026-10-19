# Eigener Hottgenroth-Arbeitsplatz — Anleitung für KI-Agenten

Dieser Bereich zeigt die **Bauteildaten aus der Hottgenroth-Software eines Energieberaters**.
Sie liegen in einer LocalDB auf dessen eigenem Windows-Rechner; die fs-App hält davon einen
Spiegel, den der Arbeitsplatz von sich aus befüllt.

Die Fachlogik der Deutung (Kennungen, BEG-Grenzwerte, Typbezeichnungen) liegt in
`app/Models/HottgenrothBauteil.php` und `app/Services/Kostentool/BauteilKatalog.php`. Das
Werkzeug ist nur eine kontrollierte Schnittstelle davor.

**Erreichbar über zwei Wege, identisch im Verhalten:**

| Zugang | Für wen | Aufruf |
|---|---|---|
| Function Calling | KI-Funktionen der fs-App | `GET /api/ai/tools`, dann `POST /api/ai/tools/{name}` |
| MCP | externe Agenten | `POST /api/mcp` (JSON-RPC 2.0), Bearer-Token |

**Rechte:**

| Recht | Schaltet frei |
|---|---|
| `hottgenroth:lesen` | `get_hottgenroth_components`, `refresh_hottgenroth_components`, `update_hottgenroth_projects`, `export_hottgenroth_projekt`, `get_hottgenroth_heizung`, `get_hottgenroth_raeume`, `get_vorgang` |
| `hottgenroth:schreiben` | `import_hottgenroth_projekt`, `create_hottcad_projekt`, `add_hottgenroth_bauteile`, `add_components`, `set_hottgenroth_raeume`, `set_hottgenroth_heizung`, `set_hottgenroth_sanierungsvarianten`, `set_hottgenroth_cad_bindung`, `import_hottgenroth_bilder` — und den Upload `POST /api/mcp/dateien` |
| `hottgenroth:arbeitsplatz` | kein Werkzeug — damit meldet sich der **Agent** auf dem Berater-PC an |

`hottgenroth:schreiben` steht **nicht** auf der OAuth-Zustimmungsseite. Es ändert den
Bestand auf dem Rechner eines Menschen und wird deshalb von Hand vergeben:

```
php artisan mcp:token neu "Claude Arbeitsplatz" --hottgenroth --hottgenroth-schreiben --user=<id>
```

```
php artisan mcp:token neu "Claude Arbeitsplatz" --hottgenroth --user=<id>
```

**Der Zugang muss einem Benutzer gehören.** Ohne `--user` lehnt der Befehl ab, und das
Werkzeug antwortet `zugang_ohne_benutzer`. Das ist keine Formalie: welche Daten sichtbar
sind, folgt ausschließlich daraus, wem der Arbeitsplatz gehört.

---

## Das Modell dahinter

### Ein Arbeitsplatz gehört genau einem Menschen

Die Kette ist `user_id → agent_id → projekt_id`. Ein Agent erreicht über dieses Werkzeug
ausschließlich Projekte von Arbeitsplätzen, die dem Benutzer des Zugangs gehören — **auch
ein Administrator sieht keine fremden.** Wer fremde Projektdaten braucht, geht über
`/admin/hottgenroth`, wo ein Mensch angemeldet ist.

**Die Zuordnung entsteht bei der Anmeldung des Arbeitsplatzes.** Der Rechner, der sich mit
einem persönlichen Zugang meldet, gehört ab dann diesem Menschen. Zwei Wege führen dahin:

**Im Browser** (der übliche): `hottgenroth-agent.exe --anmelden` öffnet ein Fenster, der
Berater meldet sich an und bestätigt. Kein Token wandert durch eine Nachricht, und auf der
Zustimmungsseite steht, was freigegeben wird. Voraussetzung ist ein einmaliger Klick: ein
Admin gibt dem Berater unter `/admin/users` das Recht **`hottgenroth:arbeitsplatz`**.

**Von Hand** (für Automaten und Altbestand):

```
php artisan mcp:token neu "Arbeitsplatz NB-Mustermann" --arbeitsplatz --user=<id>
```

Das Token kommt in die Agent-Konfiguration (`HGA_Token` bzw. `appsettings.local.json`).
Arbeitsplätze, die weiterhin mit dem alten gemeinsamen Secret laufen, funktionieren
unverändert — sie bekommen dabei aber keinen Besitzer und bleiben über MCP unsichtbar. Die
Umstellung geschieht damit Rechner für Rechner, ohne Stichtag.

Für Altbestand, Besitzerwechsel und Notaus gibt es daneben `php artisan hottgenroth:besitzer`.

### Zwei Bauteilbestände, die nichts miteinander zu tun haben

Das ist die Fachfalle, die ein Modell sonst sicher falsch macht:

| Quelle | Was es ist | Hat | Hat nicht |
|---|---|---|---|
| `katalog` | eine Konstruktion (`TcBasis`) — „Außenwand 36,5 Vollziegel" | Schichtaufbau, U-Wert | Fläche am Gebäude |
| `gebaeude` | eine modellierte Fläche (`BmElement`) — „EW 001-2, 8,60 m²" | Fläche, Ausrichtung | Schichten |

**Die beiden Listen dürfen nicht addiert werden.** Dieselbe Konstruktion steckt an dreißig
Stellen im Haus; sie einmal als Bauteil und dreißigmal als Fläche zu zählen, ergibt Unsinn.

### Kennungen

`kennung` ist die Bauteilkennung des Energieberater-Exports, dieselbe, mit der auch das
Kostentool arbeitet: `AW` Außenwand, `WE` Wand gegen Erdreich, `WK` Wand gegen unbeheizt,
`FA` Fenster, `TA` Tür, `DA` Dach, `OG` oberste Geschossdecke, `BK` Boden gegen Keller,
`BE` Boden gegen Erdreich und weitere. Sie trägt mehr als der Typ allein: die Angrenzung
steht mit drin.

Bauteile ohne Hüllflächenbezug haben keine Kennung — die Decke zwischen zwei beheizten
Geschossen und die Wärmebrücke etwa. `null` ist dort richtig und kein Fehler.

### U-Werte und BEG

`u_wert: null` heißt **nicht eingetragen**, nicht 0. Damit wird nicht gerechnet und daraus
wird kein Mangel abgeleitet.

`beg_umax` ist der höchstzulässige U-Wert der Förderung für diese Kennung — **nicht** das
Ziel des Beraters, das meist darunter liegt. `beg_erfuellt: null` heißt „nicht beurteilbar",
weil entweder der U-Wert fehlt oder für die Kennung kein Grenzwert geregelt ist.

Bei den Hüllflächen ist `u_wert` **flächengewichtet** gemittelt, nicht arithmetisch: zwanzig
Quadratmeter Fenster und ein Quadratmeter Tür ergäben sonst einen Wert, den es am Gebäude
nirgends gibt.

### Zwei Spiegel, zwei Abrufe

Der Server hält **zwei** Stände, und sie sind unabhängig voneinander:

| Spiegel | Auftragstyp | Frisch holen mit | Wird sonst geholt |
|---|---|---|---|
| Gruppen und **Projektliste** | `projekte.liste` | `update_hottgenroth_projects` | beim Start des Agenten, per Klick unter `/admin/hottgenroth`, nach einem Import über den Server |
| **Bauteile** eines Projekts | `bauteile.export` | `refresh_hottgenroth_components` | gar nicht — nur auf Anforderung |

**Das ist die häufigste Verwechslung.** Eine frisch abgerufene Bauteilliste sagt nichts
darüber, ob die *Projektliste* aktuell ist. Legt der Berater ein Projekt an oder importiert
es von Hand auf seinem Rechner, löst das keinen der Anlässe oben aus — der Server erfährt
davon nichts, bis jemand `update_hottgenroth_projects` ruft. Genau so fehlte am 16.09.2026
ein importiertes Projekt in der Liste, ohne dass irgendetwas kaputt war.

**Melde deshalb nie „dieses Projekt gibt es nicht", ohne die Liste einmal aufgefrischt zu
haben.** Wie alt sie ist, steht in der Antwort ohne `projekt` unter `stand`: je Arbeitsplatz
`gespiegelt_am`, `erreichbar` und der `letzter_abruf` mit demselben Zustandsvokabular wie
unten beim Bauteilabruf.

### Der Stand kommt aus dem Spiegel — und lässt sich auffrischen

Die Antwort ist so alt wie der letzte Abruf. `stand.gespiegelt_am` sagt wann. **Ist das Datum
älter als ein paar Tage, gehört es in die Antwort an den Menschen** — sonst wird ein Stand
von letzter Woche als aktuell verkauft. `stand.unvollstaendig` heißt, dass der Abruf selbst
schon abgeschnitten war.

Neu holen geht mit `refresh_hottgenroth_components`. **Das wartet nicht:** der Auftrag steht
bereit, der Arbeitsplatz holt ihn beim nächsten Poll ab — üblicherweise nach 20 bis 30
Sekunden. **Wer sofort nachliest, sieht den vorigen Stand.** Genau das ist am 15.09.2026
passiert: ein Modell stieß den Abruf an, las im selben Atemzug nach und meldete „die
Änderungen sind nicht angekommen" — der Arbeitsplatz hatte den Auftrag da noch gar nicht
abgeholt (Regel HA-01).

Ob der Spiegel das Ergebnis des letzten Abrufs ist, sagt deshalb `stand.letzter_abruf`:

| `status` | Bedeutung | Was tun |
|---|---|---|
| `wartet_auf_arbeitsplatz` | Auftrag liegt, noch nicht abgeholt | Nicht auswerten, in 20–30 s erneut fragen. Bei `arbeitsplatz_erreichbar: false` dem Menschen sagen |
| `wird_gelesen` | Der Arbeitsplatz liest gerade | Nicht auswerten, gleich erneut fragen |
| `uebernommen` | Der Spiegel **ist** dieser Abruf | Auswerten |
| `nicht_uebernommen` | Der Arbeitsplatz hat geliefert, der Server hat es nicht abgelegt | `problem` dem Menschen nennen — das ist ein Serverfehler |
| `fehlgeschlagen` | Der Abruf selbst ist gescheitert | `problem` dem Menschen nennen |

Daneben `vorgang_id`, `angelegt_am`, `abgeholt_am`, `abgeschlossen_am`.

**Ein frischer Abruf enthält nur, was in Hottgenroth gespeichert war** (Regel HA-02).
Katalogbauteile schreibt die Software sofort, die Zuweisung einer Konstruktion an Flächen
erst beim Speichern des Projekts. `stand.in_hottgenroth_gespeichert_am` nennt die letzte
Speicherung, `stand.gelesen_am` den Moment, in dem der Arbeitsplatz gelesen hat. Hat der
Berater nach der Speicherung noch etwas geändert, fehlt es — dann erst speichern, dann neu
abrufen. Ältere Abrufe kennen den Speicherstand nicht; das Feld fehlt dann.

---

## Werkzeuge

### `get_hottgenroth_components` — lesend (Recht `hottgenroth:lesen`)

Die Bauteilliste eines Projekts vom eigenen Arbeitsplatz — und ohne Projektangabe die Liste
der eigenen Projekte.

| Feld | Typ | Bedeutung |
|---|---|---|
| `projekt` | string | Namensteil, Projektnummer oder GUID. **Weglassen** listet die eigenen Projekte auf — das ist der Einstieg. |
| `quelle` | enum | `katalog`, `gebaeude` oder `alle` (Vorgabe). Siehe die zwei Bestände oben. |
| `nur_huelle` | boolean | Nur Flächen der thermischen Hülle zählen. Vorgabe `false`. **Für jede Kostenrechnung auf `true` setzen** — ungefiltert liegt die Fläche an echten Projekten um den Faktor 1,14 bis 4,38 zu hoch. |
| `flaechen_einzeln` | boolean | Zusätzlich jede Fläche einzeln, mit ihrer `element_uid`. Vorgabe `false`. |
| `kennung` | string | Schränkt `flaechen_einzeln` auf eine Kennung ein, z. B. `AW`. |
| `zeichnungsobjekt` | string | Schränkt `flaechen_einzeln` auf **ein gezeichnetes Bauteil** ein, z. B. `EW 003` — dann kommen alle seine Teilflächen. Welche es gibt, steht in `zeichnungsobjekte`. Die GUID des Zeichnungsobjekts wird auch angenommen. |
| `mit_schichten` | boolean | Schichtaufbau je Bauteil mitliefern. Vorgabe `true`. |
| `limit` | integer | Anzahl Bauteile, 1 bis 500, Vorgabe 200. |

**Der Ablauf ist zweistufig und das ist Absicht:** erst ohne `projekt` aufrufen, dann eines
der genannten Projekte benennen. Ein eigenes Werkzeug für die Projektliste gibt es nicht —
sie *ist* die Antwort auf den mehrdeutigen Fall.

Die Antwort trägt bei einem Treffer `projekt`, `stand`, `einheiten`, `bauteile`,
`huellflaechen` und `hinweise`. `huellflaechen` fasst die Flächen nach Kennung zusammen, mit
Fläche, Anzahl, flächengewichtetem U-Wert, Aufteilung nach Himmelsrichtung und dem
BEG-Vergleich — das ist die Sicht, die auch der Excel-Export des Energieberaters zeigt.

`gekuerzt: true` heißt, dass `limit` gegriffen hat und es mehr Bauteile gibt.

#### Einzelne Flächen — der Weg zur `element_uid`

`huellflaechen` ist zusammengefasst: eine Zeile sagt „53 Flächen, 192 m²“, aber nicht,
**welche**. Wer eine Konstruktion zuweisen will, braucht die einzelnen Flächen —
`add_components` nimmt ausschließlich ausdrücklich genannte `element_uid` entgegen und rät
nie.

Mit `flaechen_einzeln: true` kommen zusätzlich `flaechen`, `flaechen_anzahl`,
`flaechen_gekuerzt`, `flaechen_hinweis` und `zeichnungsobjekte`. Jede Zeile trägt
`element_uid`, `name` („EW 001-2“), `kennung`, `typ` („Wand gegen außen“),
`group_type`/`usage_type`, `zeichnungsobjekt`, `raum`, `geschoss`, `u_wert`, `flaeche_m2`,
`brutto_m2`, `richtung`, `katalog_uid`, `in_huelle` und `teilflaeche`. Bei Öffnungen
kommen `sitzt_in` („Dach“) und `parent_element_type` dazu.

Vier Dinge dazu:

- **Es wird gekürzt.** Ein Projekt bringt bis zu 8.000 Flächen mit; gezeigt werden die 200
  größten. `flaechen_gekuerzt: true` sagt es, und `kennung` schränkt ein. Schließe aus
  einer gekürzten Liste nie, es gäbe keine weiteren.
- **`katalog_uid` fehlt häufig, und das ist normal.** Es heißt „ohne detaillierte
  Bauteilerfassung“ — im iSFP-Bestand der Regelfall. Genau diese Flächen sind die, denen
  eine Zuweisung fehlt.
- **`raum` nennt mehrere Räume, wenn die Fläche an mehrere grenzt.** Bei Innenwänden ist
  das der Normalfall, kein Fehler: 43 % aller Flächen der gemessenen Datenbank grenzen an
  zwei oder mehr Räume. Beide zu nennen ist die Wahrheit, einen davon zu wählen wäre
  geraten.
- **`raum`, `geschoss` und `zeichnungsobjekt` können fehlen.** Sie stammen erst aus Abrufen
  ab dem 19.09.2026, und ein Projekt ohne Raummodell hat sie gar nicht. Fehlend heißt
  „nicht bekannt“, nicht „keins“ — dann hilft `refresh_hottgenroth_components`.

#### Das Zeichnungsobjekt — die Wand, nicht die Teilfläche

Das Gebäudemodell zerlegt eine gezeichnete Wand in Teilflächen, eine je angrenzendem Raum.
„EW 003“, „EW 003-2“ und „EW 003-3“ sind **eine** Wand; am gemessenen Projekt stehen 11
Zeichnungsobjekte hinter 22 Teilflächen. Der Energieberater filtert in seiner Oberfläche
auf den Zeichnungsobjekten — ein Mensch meint die Wand, die Teilflächen sind Buchhaltung.

`zeichnungsobjekte` in der Antwort listet sie mit `teilflaechen`, `flaeche_m2`, `raeume`,
`geschoss` und der Kennung, nach Fläche absteigend und bei 100 Einträgen gedeckelt. Die
Kennung steht als `kennung`, wenn es nur eine gibt, und als `kennungen` (Liste), wenn die
Wand außen und innen weiterläuft. `zeichnungsobjekt: "EW 003"` holt danach genau deren
Teilflächen — mit allen `element_uid`, die `add_components` für diese Wand braucht.

**Frag den Menschen nach der Wand, nicht nach der GUID.** „Meinst du EW 003 (Küche,
Wohnungsflur, WC-Raum, Erdgeschoss)?“ ist beantwortbar,
„meinst du 21b8a001-dc1e-037b-90a6-cba6ce61fdd7?“ nicht.

Der Name wird zuerst **genau** verglichen (Groß-/Kleinschreibung egal), und erst wenn das
nichts trifft, als Teilzeichenkette. Sonst holte „EW 003“ auch „EW 0031“ herein, ohne dass
es jemandem auffiele.

#### Dachfenster heißen `DF`, nicht `FA`

Ein Dachfenster und ein Fassadenfenster sind in der Datenbank derselbe Typ — `ElementType 3`
gegen außen. Der einzige Unterschied ist, worin sie sitzen (`parent_element_type`): ein Dach
oder eine Wand. Die Kennung berücksichtigt das, `sitzt_in` sagt es im Klartext. Für ein
Dachfenster gelten ein anderer BEG-Höchstwert und ein anderer Quadratmeterpreis als für ein
Fassadenfenster — vor dem 19.09.2026 liefen alle 109 Dachfenster der gemessenen Datenbank
unter `FA`.

**Jede Antwort trägt einen `link`** — auch jede Zeile der Projektliste. Er zeigt auf die
Bauteilansicht an genau diese Stelle:

```
/admin/hottgenroth/bauteile/agent-1/gruppe-17/projekt-71
```

Die Kette kann tiefer sein, weil Gruppen Untergruppen haben. **Gib den Link weiter, wenn ein
Mensch nachsehen soll:** die Kachelansicht dort zeigt den Schichtaufbau, den eine
Werkzeugantwort nur beschreiben kann. Die Seite hängt an `role:admin,projekte`.

### `refresh_hottgenroth_components` — stößt den Abruf an (Recht `hottgenroth:lesen`)

Holt die Bauteilliste eines Projekts frisch vom Arbeitsplatz.

| Feld | Typ | Bedeutung |
|---|---|---|
| `projekt` | string | **Pflicht.** Namensteil, Projektnummer oder GUID — dieselbe Auflösung wie beim Anzeigen. |

Die Antwort trägt `status` (`angestossen` oder `lief_schon`), `arbeitsplatz_erreichbar`,
`zuletzt_gesehen`, `stand_vorher` und `vorgang_id`.

**Es wird nicht gewartet.** Ein zweiter Aufruf stellt keinen zweiten Auftrag — läuft schon
einer für dasselbe Projekt, kommt er zurück (`status: lief_schon`). Bei
`arbeitsplatz_erreichbar: false` liegt der Auftrag, bis der Rechner wieder da ist; das gehört
dem Menschen gesagt, statt ihn warten zu lassen.

**Nicht unmittelbar danach nachlesen.** Erfolgskontrolle ist `stand.letzter_abruf.status` in
`get_hottgenroth_components`, nicht ein Vergleich von `gespiegelt_am` — der fällt direkt nach
dem Anstoßen immer „unverändert" aus. Hat der Berater gerade etwas geändert, vorher fragen,
ob gespeichert ist.

Auf dem Rechner des Beraters wird dabei ausschließlich gelesen — sechs SELECTs. Verändert
wird nur der Spiegel auf dem Server.

### `update_hottgenroth_projects` — frischt die Projektliste auf (Recht `hottgenroth:lesen`)

Holt Gruppen und Projekte frisch vom Arbeitsplatz — den Bestand, den die Software in ihrem
Projektbrowser zeigt. Das Gegenstück eine Ebene über `refresh_hottgenroth_components`.

| Feld | Typ | Bedeutung |
|---|---|---|
| `arbeitsplatz` | string | Name oder Hostname eines eigenen Arbeitsplatzes. **Weglassen frischt alle eigenen auf** — bei nur einem Rechner der Normalfall. Anders als beim Import wird hier nicht nach dem Ziel gefragt: es werden nur zwei SELECTs gelesen. |

Die Antwort trägt `status` und je Arbeitsplatz eine Zeile mit `arbeitsplatz`, `erreichbar`,
`zuletzt_gesehen`, `stand_vorher`, `projekte_bisher`, `status` und `vorgang_id`.

| `status` | Bedeutung |
|---|---|
| `angestossen` | Der Auftrag steht bereit |
| `lief_schon` | Es war schon einer offen — `vorgang_id` nennt ihn. Kein zweiter wird gestellt |
| `nicht_moeglich` | Der Arbeitsplatz meldet `sql.query` nicht; `grund` sagt es. Meist eine alte Agentenfassung |
| `teilweise` | Nur als Gesamtstatus bei mehreren Arbeitsplätzen mit unterschiedlichem Ausgang |

**Es wird nicht gewartet**, und die Erfolgskontrolle ist dieselbe wie beim Bauteilabruf:
`get_hottgenroth_components` **ohne** `projekt` aufrufen und erst auswerten, wenn dort
`stand.arbeitsplaetze[].letzter_abruf.status` auf `uebernommen` steht (Regel HA-01). Nicht
in einer Schleife rufen.

Übernommen wird das Abbild **vollständig oder gar nicht**: der Spiegel wird ersetzt, nicht
zusammengeführt. Was der Arbeitsplatz nicht meldet, bekommt `verschwunden_seit` — gelöscht
wird nichts. War das Ergebnis abgeschnitten, unterbleibt genau das, und der Zustand steht
auf `nicht_uebernommen` mit dem Grund in `problem`.

Auf dem Rechner des Beraters wird dabei ausschließlich gelesen — zwei SELECTs auf
`XmProjectGroup` und `XmProject`.

---

### `get_hottgenroth_sanierungsvarianten` — Varianten mit Kosten und Bilanz (Recht `hottgenroth:lesen`)

Liefert Ist-Zustand und Maßnahmenpakete nebeneinander: Maßnahmen mit Ziel-U-Wert und Kosten,
Energiebilanz, Anlagentechnik und Verluste.

| Feld | Typ | Bedeutung |
|---|---|---|
| `projekt` | string | **Pflicht.** Namensteil, Projektnummer oder GUID. |
| `umfang` | enum | `ueberblick` nur Energie und Kosten, `massnahmen` (Vorgabe) zusätzlich die Maßnahmen, `bauteile` jede einzelne Bauteilzeile. |
| `variante` | string | Nur eine Variante, als Name oder Nummer (`0` = Ist-Zustand). |
| `neu_holen` | boolean | Einen frischen Lauf stellen, statt den gelesenen Stand zu zeigen. |

**Die Daten stehen nicht in SQL.** Die Varianten liegen als `eberater.zip` in `PrMedia` —
neun Tabellen im Format `.BDExit`. Ein Skript auf dem Arbeitsplatz liest sie und gibt JSON
zurück ([Export-Sanierungsvarianten.ps1](../hottgenroth-agent/tools/Export-Sanierungsvarianten.ps1)).
Deshalb gibt es hier **keinen Spiegel**: was der Server kennt, ist das Ergebnis des letzten
Laufs. Ohne vorherigen Lauf wird einer gestellt (`status: angestossen`) — das **wartet
nicht**, nach etwa einer Minute erneut aufrufen.

**Die Beträge sind kumulativ.** Jedes Paket führt die Maßnahmen der vorigen noch einmal.
`kosten.investition_paket` ist der Zuwachs gegenüber der Vorgängervariante — das ist die
Zahl, die im iSFP als Investition des Pakets steht. Die kumulierten Beträge der Pakete
**nicht** addieren.

**Sowieso-Kosten** stehen in der Datenbank nirgends; sie sind die Differenz aus Gesamt- und
energiebedingten Kosten und hier ausgerechnet. Sie entscheiden über die Förderung.

`massnahmen[].ohne_kosten` zählt Bauteile, die eine Maßnahme tragen, aber 0 € kosten. Das
ist fast immer ein Versehen: Die Einsparung rechnet mit, die Investition fehlt.

Bei einer Wärmepumpe ist `heizung.aufwandszahl` der Kehrwert der Jahresarbeitszahl
(0,3 entspricht JAZ 3,3).

### `get_hottgenroth_heizung` — Anlagentechnik lesen (Recht `hottgenroth:lesen`)

Liest Heizung, Speicher und Warmwasserbereitung nach DIN 18599 — den gerechneten Stand
je Variante, und auf Wunsch die Anlagenbeschreibung einer Variante.

| Feld | Typ | Bedeutung |
|---|---|---|
| `projekt` | string | **Pflicht.** Namensteil, Projektnummer oder GUID. |
| `variante` | integer | Nummer der Variante, deren Beschreibung gebraucht wird. Weglassen für die Übersicht — die nennt die Nummern erst. |

**Ohne `variante` aufrufen, bevor irgendetwas anderes passiert.** Welche Nummer der
Ist-Zustand ist und welche das Maßnahmenpaket, steht nirgends sonst.

**Es gibt hier keinen Spiegel**, anders als bei den Bauteilen. Die Anlagentechnik liegt als
BinaryFormatter-Objektgraph im Feld `TableZusatz.Kernel18599V5` — **einer je Variante**.
Ein Spiegel wäre ein zweiter Ort für dieselbe Sache, und genau dieses Muster hat bei den
U-Werten schon einmal eine Variante sanierte Werte *anzeigen* und mit den alten *rechnen*
lassen. Gelesen wird deshalb immer frisch; die Ausgaben stehen danach in `get_vorgang` mit
`protokoll: true`.

**Der gerechnete Stand ist die Wirkungsprobe.** Er kommt aus `TableHeizung`, und das ist
**Ergebnis, keine Eingabe**: die Software schreibt den Satz beim Rechnen. Daraus folgen zwei
Lesarten, die man nicht verwechseln darf:

| Ausgabe | heißt |
|---|---|
| Endenergie, Aufwandszahl, Verluste | die Software hat auf diesem Modell gerechnet |
| **NICHT GERECHNET** | kein Satz in `TableHeizung` — niemand hat diese Variante geöffnet |

**„NICHT GERECHNET" heißt nicht „kaputt".** Jede Variante führt meist ein Modell, weil es
beim Anlegen mitkopiert wird; bei einer frisch angelegten Variante ist das der Normalfall.
Ob eines da ist, sagt die Liste der Modelle in derselben Antwort — sie ist eine **andere**
Auskunft als der gerechnete Stand.

Die Anlagenbeschreibung ist dasselbe Austauschformat, das `set_hottgenroth_heizung`
annimmt. Damit wird „Anlage von Projekt A nach B übernehmen" zu zwei Aufrufen.

### `get_hottgenroth_raeume` — Geschosse, Zonen und Raumstempel lesen (Recht `hottgenroth:lesen`)

Liest Geschosse, DIN-18599-Zonen und jeden Raum eines Projekts — frisch vom Arbeitsplatz,
auch bei offener Software (dann der zuletzt gespeicherte Stand).

| Feld | Typ | Bedeutung |
|---|---|---|
| `projekt` | string | **Pflicht.** Namensteil, Projektnummer oder GUID. |

**Warum es das gibt.** Der Bauteilspiegel nennt je Fläche einen Raumnamen, aber weder die
Raumnummer noch Raumart, Heizstatus, Temperatur oder Zone — und über die **Nummer**
(`EG-R9`, `OG1-R1`) wählen die Skripte. Ein importiertes Modell trägt zudem oft nur die
Standard-Stempel der Erkennung: am 18.10.2026 stand in einem Anbau ein „Kellerraum" im
Obergeschoss mit 15 °C, und das Projekt hatte keine einzige DIN-18599-Zone. Die
18599-Rechnung sieht nur Räume, die in einer Zone hängen — mit solchen Stempeln ist jede
Bilanz falsch, bevor ein U-Wert eine Rolle spielt.

**Die Antwort kommt über `get_vorgang`**, unter `ergebnis.stand`:

| Schlüssel | Inhalt |
|---|---|
| `geschosse[]` | `kuerzel` (das Kürzel für `set_hottgenroth_raeume`), `name`, `typ`, `raeume` |
| `zonen[]` | nur DIN-18599-Zonen (ZoneType 5): `name`, `profil`, `profil_typ`, `raeume`, `flaeche_m2`, `flaeche_gerechnet`, `eberater_kennung` |
| `zonen_gesamt` | alle Zonen inkl. Brandschutz — sie dienen als Vorlage, wenn eine DIN-18599-Zone erst entsteht |
| `raeume[]` | `nr`, `name`, `geschoss`, `raumart`, `raumart_name`, `heizstatus` (beheizt/unbeheizt/separat), `temperatur_c`, `flaeche_m2`, `volumen_m3`, `wohnflaeche_m2`, `zone`, `in_zone`, `zonen_anzahl`, `cad_xml`, `xml_room_type`, `widersprueche[]` |
| `zusammenfassung` | Zählung: beheizt, unbeheizt, in Zone, ohne CAD-XML, mit Widerspruch |

**`widersprueche` ist die wichtigste Spalte.** Jeder Stempel steht zweimal — in `BmRoom`
und im CAD-XML des Raums. Weichen sie ab, zeigt die Oberfläche das eine und rechnet mit
dem anderen. **`flaeche_gerechnet: false`** an einer Zone heißt: die Software hat die
Zuordnungen gelesen, aber noch nicht verrechnet (Sentinel) — erst ein Öffnen und Speichern
in der Software ändert das.

**`zonen: []`** heißt: noch keine DIN-18599-Zone. `set_hottgenroth_raeume` legt sie an.

### `import_hottgenroth_projekt` — spielt eine .sqproj ein (Recht `hottgenroth:schreiben`)

Importiert eine Projektdatei über den Importer der Software selbst (Brücke).

| Feld | Typ | Bedeutung |
|---|---|---|
| `drive_datei` | string | Die Datei in Google Drive: ID, Link oder genauer Dateiname mit `.sqproj`, z. B. `YDL5D_Aschersleben_260915.sqproj`. **Der Regelfall.** |
| `datei` | string | Nur für Dateien, die **nicht** in Drive liegen: der `schluessel` aus der Antwort des Uploads, z. B. `files/uploads/vorlage-20260916-101500-ab12cd.sqproj`. |
| `gruppe` | string | **Pflicht.** Name der Projektgruppe in der Software. Sinnvoll ist die Projektreferenz — darüber ist das Projekt danach wiederzufinden. |
| `arbeitsplatz` | string | Nur nötig, wenn dem Benutzer mehrere Arbeitsplätze gehören: Name oder Rechnername. Bei genau einem entfällt die Angabe. |
| `erneut` | boolean | Nur mit `drive_datei`: auch dann einspielen, wenn genau dieser Inhalt schon einmal importiert wurde — das ergibt ein **zweites** Projekt. Vorgabe `false`, nur auf ausdrücklichen Wunsch. |

Genau eines von `drive_datei` und `datei` — beide oder keines ergibt `datei_doppelt` bzw.
`datei_fehlt`.

**Die Datei reist nicht durch den Werkzeugaufruf.** Argumente gehen durch das Kontextfenster
des Modells; eine .sqproj wiegt 7 bis 40 MB. Der Aufruf nennt sie deshalb nur.

**Aus Google Drive (`drive_datei`) holt der Server sie selbst** — über die app-weit
geteilte Drive-Verbindung, die auch Buchhaltung und Backup nutzen. Das ist der Weg für ein
Modell am Connector, das keinen HTTP-Upload machen kann, und der Regelfall, weil die
Exporte im Kundenordner liegen. Ein Name wird nur **genau** genommen; gibt es ihn mehrmals,
kommt `drive_datei_mehrdeutig` mit Ordner, Datum und `id` je Treffer, und der Mensch wählt.
Vor dem Laden werden Endung, Format und Größe geprüft, danach Bytezahl, MD5 und der
SQLite-Kopf — eine unvollständige oder falsche Datei wird gar nicht erst eingestellt.

**Ohne Drive geht die Datei vorher als gewöhnlicher HTTP-Upload** an
`POST /api/mcp/dateien` — dieselbe Adresse, dasselbe Bearer-Token:

```bash
curl -X POST https://www.fs-energieberater.de/api/mcp/dateien \
     -H "Authorization: Bearer fsmcp_…" \
     -F "datei=@C:/Projekte/Baumoehl.sqproj"
# -> {"schluessel":"files/uploads/baumoehl-20260916-101500-ab12cd.sqproj","groesse_mb":7.7,"sha256":"…"}
```

Grenze 40 MB, nur `.sqproj`. Die Antwort trägt `sha256` — damit lässt sich prüfen, dass
angekommen ist, was geschickt wurde. In PowerShell `Invoke-WebRequest -InFile` verwenden und
**`Content-Length` setzen lassen**: fortrabbit verwirft Rümpfe mit `Transfer-Encoding:
chunked` und antwortet trotzdem mit 200.

Die Antwort des Werkzeugs trägt `status`, `gruppe`, `datei`, `arbeitsplatz`,
`arbeitsplatz_erreichbar`, `vorgang_id` und `next_step`; aus Drive zusätzlich
`quelle: google_drive`, `drive_ordner` und `groesse_mb`.

**Es wird nicht gewartet, und der Aufruf ist nicht wiederholbar.** Der Import dauert je nach
Projektgröße Minuten. Ein zweiter Aufruf legt dasselbe Projekt ein zweites Mal an — die
Software vergibt beim Import neue GUIDs und erkennt keine Wiederholung. Läuft derselbe
Import noch, kommt er zurück (`status: lief_schon`). Ist dieselbe Drive-Datei mit
demselben Inhalt auf diesem Arbeitsplatz schon erfolgreich eingespielt, kommt
`status: schon_importiert` und es wird nichts angestoßen — erst `erneut: true` legt ein
zweites Exemplar an. **Die Software liest ihren
Projektbestand beim Öffnen**: was ankommt, während sie läuft, erscheint erst nach einem
Neustart.

### `create_hottcad_projekt` — neues Projekt aus der Basisvorlage (Recht `hottgenroth:schreiben`)

Legt für ein Zoho-Projekt ein neues HottCAD-Projekt auf dem eigenen Arbeitsplatz an. Ein
einziger Auftrag spielt die **Basisvorlage** ein und trägt danach **Eigentümer**,
**Projektadresse** und **Planer** ein.

| Feld | Typ | Bedeutung |
|---|---|---|
| `crm_project_id` | string | **Pflicht.** Die Zoho-Projekt-Record-ID (Modul `Projekte`). Daraus kommen Kunde und Projektadresse. |
| `vorschau` | boolean | `true` zeigt die Daten, die eingetragen würden, und legt **nichts** an. Damit anfangen und dem Menschen vorlegen. |
| `gruppe` | string | Name der Projektgruppe in der Software. Vorgabe: Projektreferenz, Kundenname und Datum, z. B. `3QHTK_Lennart Krause_261010`. |
| `arbeitsplatz` | string | Nur nötig, wenn dem Benutzer mehrere Arbeitsplätze gehören. |
| `mit_komponenten` | boolean | Die Bauteile des FS-Projekts zu diesem Zoho-Projekt in den **Katalog** des neuen Projekts einspielen. Vorgabe `false`. |
| `komponenten` | array | Weitere Katalog-Bauteile, je `catalog_component_id`, optional `component_type`, `variante`, `name`. Höchstens 8 zusammen mit denen des FS-Projekts. |
| `export` | boolean | Das fertige Projekt zum Schluss als `.sqproj` in die fs-app laden (Exporte-Seite). Vorgabe `true`. |
| `bilder` | array | **Optional.** Bilder für die Bilderverwaltung, nach den Kontakten eingespielt. Je Eintrag dieselben Felder wie bei `import_hottgenroth_bilder`: `schluessel`, `funktion`, `name`, `beschreibung`, `bildquelle`, `reihenfolge`. |
| `erneut` | boolean | Ein weiteres Projekt anlegen, obwohl für dieses Zoho-Projekt schon eines angelegt wurde. Vorgabe `false`. |

**Woher die Daten kommen.** Die Projektadresse aus den `Gebaeudedaten` des Zoho-Projekts
(Straße mit Hausnummer, PLZ, Ort). Der Eigentümer ist der Kontakt im Lookup `Kunde`:
`Anrede` („Sehr geehrter Herr“ → Anrede `Herr`, männlich), Vor- und Nachname, `Street`,
`ZIP`, `City`, `Email`, `Phone`. Hat der Kontakt keine eigene Anschrift, gilt die
Objektadresse — die Antwort sagt es unter `hinweise`. Der **Planer** ist immer
FS Energieberater GmbH, hinterlegt in `config('hottgenroth.hottcad_projekt.planer')`.
Fehlen Kunde oder Objektadresse im CRM, kommt `kunde_fehlt` bzw. `objektadresse_fehlt`, und
es wird nichts angelegt — geraten wird nicht.

**Die Vorlage** lädt ein Admin unter `/admin/hottgenroth` hoch (Karte „Basisvorlage für
neue HottCAD-Projekte“). Es gibt genau eine; ein neuer Upload ersetzt sie. Fehlt sie, kommt
`vorlage_fehlt`. Der Auftrag merkt sich Name und SHA-256 der Vorlage in `payload.meta`.

**Der Ablauf auf dem Arbeitsplatz:** Umgebung melden → prüfen, dass die Software zu ist →
Vorlage laden → Import über die Software → Projekt-GUID ermitteln → Kontakte schreiben →
(optional) Bauteile in den Katalog →
(optional) Bilder über `Import-Bilder.ps1`, mit der GUID aus dem Import (`{{ projekt.scalar }}`) →
(Vorgabe) Export als `.sqproj` in die fs-app, wie bei `export_hottgenroth_projekt`. Der Export
ist **nachgeordnet**: scheitert er, ist das Projekt trotzdem angelegt und der Vorgang erledigt —
`get_vorgang` meldet dann `export_fehlt`, und `export_hottgenroth_projekt` holt ihn nach.
Geprüft werden die Bilder vorher auf dem Server, genau wie bei `import_hottgenroth_bilder`: ein
unbrauchbarer Eintrag verhindert den ganzen Auftrag, nicht nur das Bild.
Ist eine Hottgenroth-Anwendung offen, bricht er **vor** dem Import ab: eine laufende
Software verwirft die Kontakte beim Beenden.

**Mit Komponenten heißt: in den Katalog, nicht an Flächen.** Ein neues Projekt steht noch
nicht im Spiegel und hat keine Flächen, die der Server prüfen könnte. Die Bauteile werden
deshalb aufgelöst wie bei `add_components` — Variante, Schichten oder Direktwert, dieselben
Fehlercodes —, aber nur eingespielt; eine `element_uid` wird mit `flaechen_nicht_moeglich`
abgewiesen. Zuweisen danach mit `add_components`, wenn das Modell gezeichnet ist, und dann
erneut `export_hottgenroth_projekt`. Ein Bauteil, das sich nicht auflösen lässt, verhindert
den ganzen Auftrag. Fehlen am FS-Projekt Bauteile, obwohl `mit_komponenten` gesetzt ist,
kommt `fs_projekt_ohne_bauteile`.

**Wie ein Kontakt geschrieben wird (Regel HA-18).** Jeder Kontakt bekommt eine Kontaktart
(`ccePerson`, beim Planer `cceCompany`), eine Hauptadresse (`mczSeq01`) und seine Rolle
**zweimal** — am Kontakt selbst und an der Projekt-Kontaktgruppe. Fehlt eines davon, stehen
die Zeilen in der Datenbank und die Reiter bleiben trotzdem leer, oder sie sind nach einem
Export und Re-Import wieder leer.

Die Antwort trägt `status` (`vorschau`, `angestossen`, `lief_schon`, `schon_angelegt`,
`vorheriger_lauf_unvollstaendig`), `gruppe`, `kunde`, `bilder`, `arbeitsplatz`, `arbeitsplatz_erreichbar`, `vorgang_id` und `next_step`.

**Nicht wiederholbar.** Jeder Lauf legt ein weiteres Projekt an. Läuft schon einer für
dasselbe Zoho-Projekt, kommt er zurück (`lief_schon`); ist schon einer erledigt, kommt
`schon_angelegt`. Brach ein früherer Lauf ab, **nachdem** er zu schreiben begann — etwa bei den
Kontakten oder Bildern —, kommt `vorheriger_lauf_unvollstaendig`: das Projekt liegt dann
vermutlich schon auf dem Rechner, fehlende Bilder holt `import_hottgenroth_bilder` nach. Erst
`erneut: true` legt ein zweites an. Das Projekt **behält den Namen
der Vorlage**; wiederzufinden ist es über die Gruppe. Es erscheint in der Software erst
nach einem Neustart.

### `export_hottgenroth_projekt` — Projekt als .sqproj in die fs-app (Recht `hottgenroth:lesen`)

Erzeugt aus einem Projekt auf dem eigenen Arbeitsplatz eine `.sqproj` und legt sie auf der
Seite Hottgenroth-Exporte ab (Art `sqproj`). Von dort lässt sie sich herunterladen,
weitergeben oder mit `import_hottgenroth_projekt` wieder einspielen.

| Feld | Typ | Bedeutung |
|---|---|---|
| `projekt` | string | **Pflicht.** Namensteil, Projektnummer oder GUID — gefunden wird im Spiegel. |

**Mit dem nativen Exporter** (`Hsetu.ImExporter.exe`, Pfad in
`config('hottgenroth.sqproj_export.exporter')`), genau dem Programm, das „Projekt
exportieren“ in der Oberfläche startet. Am Kundenprojekt ändert sich nichts — deshalb genügt
das Leserecht. Exportiert wird der **gespeicherte** Stand.

**Grenze 128 MB** (`hottgenroth.sqproj_export.max_mb`): größer nehmen Nginx und fortrabbit
nicht an. Eine größere Datei wird gar nicht erst hochgeladen; der Vorgang scheitert mit Größe
und Grenze in der Meldung, und der Berater exportiert in der Software selbst.

Die Antwort trägt `status` (`angestossen`, `lief_schon`), `projekt`, `datei`,
`arbeitsplatz`, `arbeitsplatz_erreichbar`, `vorgang_id` und `next_step`. Die fertige Datei
nennt `get_vorgang` unter `dateien`. Ein Aufruf, während derselbe Export läuft, gibt ihn
zurück; danach ist ein neuer Aufruf gefahrlos und erzeugt eine neue Datei.

### `add_hottgenroth_bauteile` — legt Bauteile an (Recht `hottgenroth:schreiben`)

Schreibt Bauteile mit Schichtaufbau in den Katalog eines Projekts.

| Feld | Typ | Bedeutung |
|---|---|---|
| `projekt` | string | **Pflicht.** Namensteil, Projektnummer oder GUID — dieselbe Auflösung wie beim Anzeigen. |
| `bauteile` | array | **Pflicht.** Höchstens 25 je Aufruf. Je Bauteil `name`, `art`, `lage` und `schichten`. |
| `praefix` | string | Wird jedem Namen vorangestellt, z. B. `VAR Fassade:` — so sind eingespielte Bauteile im Katalog wiederzufinden. Das trennende Leerzeichen ergänzt das Werkzeug; ein mitgeschicktes ginge unterwegs verloren. |
| `probelauf` | boolean | `true` rechnet den Aufbau durch und schreibt nichts. **Damit anfangen.** |

Je Schicht: `name`, `lambda` in W/(mK) und `dicke_cm` in **Zentimetern**, dazu optional
`dichte`, `kapazitaet`, `mu_unten` und `mu_oben`. Schichten von **innen nach außen**. U-Wert
und R-Wert rechnet der Arbeitsplatz aus den Schichten — nicht vorgeben.

**Die `gruppe` ist die Farbe.** `Hsetu.FW.Calculations.BaustoffFarbe()` färbt jede Schicht
im Schichtaufbau nach ihrer Baustoffgruppe ein; zugleich ist die Gruppe die **erste Ziffer
des Katalogpfads** und steuert den Filter im Materialbaum:

| `gruppe` | Nr. | Farbe | im Katalog u. a. |
|---|---|---|---|
| `putz_estrich` | 1 | blaugrau | Anhydrit-, Zementestrich |
| `beton` | 2 | grau | Beton |
| `platte` | 3 | grün | Holzfaser-, XPS-Platten |
| `mauerwerk` | 4 | rot | Ziegelmauerwerk, Betonhohlsteine |
| `daemmung` | 5 | gelb | Polystyrol, Mineralwolle |
| `holz` | 6 | braun | Sperrholz |
| `belag_abdichtung` | 7 | blau | Abdichtungen, PVC |
| `sonstiges` | 8 | violett | Aluminiumlegierungen |
| `systemplatte` | 9 | violett | Systemplatten |

Die Zuordnung ist an rund 28.000 Schichten der LocalDB gemessen, nicht geraten.

**Ohne Angabe wird die Schicht nicht grau, sondern violett.** `BaustoffFarbe()` hat keinen
Zweig für „keine Gruppe"; die 0 fällt in den Default und bekommt (136, 81, 136) — dasselbe
Violett wie Gruppe 8. Grau ist Gruppe 2. Ein Aufbau ohne Gruppen sieht deshalb nicht
unfertig aus, sondern plausibel falsch; er behauptet im Bild, alles sei „Sonstiges". Geraten
wird trotzdem nicht: eine erfundene Gruppe behauptet zusätzlich etwas über den Baustoff und
stellt die Schicht im Materialbaum an die falsche Stelle.

**`schichtart` ist etwas anderes als die Gruppe.** Die Gruppe sagt, woraus die Schicht ist;
die Schichtart, wie die Software sie behandelt: `normal`, `daemmschicht`, `luftschicht`
(ruhend) oder `belueftete_luftschicht` — letztere zählt im Wärmedurchgang nicht mit.

Die beiden greifen an zwei gemessenen Stellen ineinander:

| Angabe | LayerType / MaterialType | gemessen |
|---|---|---|
| `gruppe: daemmung`, keine Schichtart | 3 / 1 wie `daemmschicht` | 4.932 von 5.042 Schichten der Gruppe 5 tragen LayerType 3 |
| `gruppe: holz` | 0 / **12** (mmdWood) | 5.289 von 5.381 Schichten der Gruppe 6; MaterialType 12 kommt in keiner anderen Gruppe vor |

Wer bei einer Dämmung ausdrücklich `schichtart: normal` schreibt, bekommt sie — die Angabe
gewinnt. Umgekehrt gibt es LayerType 0 mit MaterialType 1 im ganzen Bestand nicht; deshalb
reist „Dämmstoff" an der Schichtart und nicht an der Gruppe.

**Nur homogene Aufbauten — und das ist die Grenze des Werkzeugs, nicht die der Software.**
Dieser Baustein schreibt eine Schichtfolge. Sparrendächer, Holzbalkendecken, Ständer- und
Fachwerkwände bestehen aus nebeneinanderliegenden Abschnitten (Gefach und Rippe); die kann er
nicht anlegen — `LayerSectionUId` bleibt die Null-GUID.

Hottgenroth führt sie sehr wohl: **1.306 der 12.802 Bauteile** der LocalDB sind inhomogen, mit
3.510 Abschnitten und 28.204 Schichtzeilen darin. `get_hottgenroth_components` meldet sie auch —
über `inhomogen`, `gefach` und `gefach_anteil`. Genau diese Schieflage hat am 04.10.2026 dazu
geführt, dass einem Berater „das Feature gibt es nicht" gesagt wurde: beim Lesen sichtbar, beim
Schreiben unerwähnt, also vom Modell als Abwesenheit gedeutet.

**Sag deshalb nie „das geht nicht".** Es geht auf zwei anderen Wegen: von Hand im Bauteileditor
der Software, oder per SQL über den Baustein `sql.script` — Schema, Fünf-Punkte-Anleitung und ein
fertiges Beispiel für eine oberste Geschossdecke stehen in
[bauteile/docs/hottgenroth-bauteil-sql.md](../bauteile/docs/hottgenroth-bauteil-sql.md),
Abschnitt 9a.

Wer das Gefach hier dennoch unterbringen will, mittelt es zu einer **Ersatzschicht** (λ nach
Flächenanteil gemischt). Das ist zulässig und liegt auf der sicheren Seite — an einer
Nagelbrettbinder-Decke gemessen 0,470 gegen 0,461 nach EN ISO 6946, rund 2 %. Es bleibt aber eine
Vereinfachung, und die gehört in die Antwort an den Berater, nicht in seine spätere Entdeckung.

**`katalogpfad`** (z. B. `4.1.2.6`) nur angeben, wenn er aus dem Katalog stammt. Die erste
Ziffer liegt zwischen 1 und 9 — der Baum hat neun Wurzeln. Sie ist **meist** die Gruppe,
**darf ihr aber widersprechen**: von 23.353 Schichten mit Pfad widersprechen 1.912 (8,2 %)
der eigenen Gruppe, und zwar systematisch. Häufigster Fall: Pfad `6.x` in Gruppe 3 (1.258-mal)
— Holzwerkstoffplatten wie OSB stehen im Baum unter Holz und sind als Bauplatte eingefärbt.
Bis zum 03.10.2026 wies das Werkzeug solche Aufrufe ab und verwarf damit korrekte Eingaben.

`art`: `wand`, `tuer`, `fenster`, `boden_decke`, `dach`.
`lage`: `gegen_beheizt`, `gegen_aussen`, `gegen_erdreich`, `wand_gegen_unbeheizt`,
`decke_gegen_unbeheizt`, `boden_gegen_keller`.

**`lage` ist nicht kosmetisch.** Die Software leitet daraus Rsi und Rse ab und überschreibt
abweichende Werte; eine falsche Lage ergibt über falsche Übergangswiderstände einen falschen
U-Wert, ohne jede Meldung.

**Zentimeter, nicht Meter.** `dicke_cm: 0.16` wären 1,6 Millimeter Dämmung — gemeint sind
fast immer 16 cm. Dem fertigen Bauteil sieht man das nicht an, es hat nur einen zu hohen
U-Wert. Deshalb werden Werte unter **0,5 cm** abgewiesen; dünnere Schichten (Folien,
Anstriche) tragen zur Bilanz ohnehin nichts bei.

Die Bauteile landen im **Katalog** des Projekts. Einer Fläche zugewiesen sind sie damit
nicht — dafür gibt es `add_components`. Neue Katalogbauteile zeigt die Software erst nach
einem Neustart.

### `add_components` — einspielen UND zuweisen (Recht `hottgenroth:schreiben`)

Nimmt ein Bauteil aus dem **FS-Bauteilkatalog**, legt es im Projekt an und hängt die
genannten Flächen des Gebäudes daran. Das Stück, das bisher von Hand lief.

Nicht zu verwechseln mit `add_component_to_project`: das schreibt eine Zeile in die
FS-Datenbank, dieses ändert das Kundenprojekt auf dem Rechner des Beraters.

| Feld | Typ | Bedeutung |
|---|---|---|
| `projekt` | string | **Pflicht.** Namensteil, Projektnummer oder GUID des Hottgenroth-Projekts. |
| `zuordnungen` | array | Je Eintrag ein Bauteil und seine Flächen. Höchstens 8 Bauteile und 80 Flächen je Aufruf. |
| `fs_projekt_id` | integer | Statt `zuordnungen`: alle Bauteile dieses FS-Projekts **nur einspielen**. |
| `crm_project_id` | string | Dasselbe über die Zoho-Record-ID. |
| `software_schliessen` | string | `nein` (Vorgabe), `verwaiste` oder `alle` — siehe unten. |
| `probelauf` | boolean | `true` rechnet durch und schreibt nichts. **Damit anfangen.** |

Je Eintrag in `zuordnungen`: `catalog_component_id` (Pflicht, aus
`find_building_components`), `element_uids` (die Flächen), optional `variante` und `name`.

**Der Ablauf hat drei Schritte, nicht einen:**

1. `find_building_components` — das Bauteil suchen, `component_id` merken.
2. `get_hottgenroth_components` mit `flaechen_einzeln: true` — die `element_uid` der
   Flächen. **Ohne diesen Schritt hast du keine**, denn `huellflaechen` ist zusammengefasst.
3. `add_components` mit `probelauf`, Ergebnis ansehen, dann ohne.

**Die Flächen werden nicht geraten.** Das Werkzeug prüft nur, ob eine `element_uid` zu
diesem Projekt gehört und ob die Bauteilart zur Lage der Fläche passt — welche Wand welchen
Aufbau hat, weiß der Berater. Eine fremde Fläche ergibt `flaeche_fremd`, und der Auftrag
entsteht gar nicht erst.

**Ohne `zuordnungen` wird nur eingespielt.** `fs_projekt_bauteile` kennt Bauteiltyp und
Katalogeintrag, aber keine Fläche — die beiden Projektbegriffe sind nicht verbunden.

**Ein Bauteil braucht keinen Schichtaufbau** (Regel BK-13). Typologiewerte, Türen und
sämtliche Fenster tragen statt Schichten einen direkten U-Wert — 6.880 Katalogzeilen sind
so gebaut, und ein Fenster ist in dieser Software **nie** ein Schichtstapel. Der Auftrag
schickt dann `u_wert` statt `schichten`, bei Fenstern zusätzlich `g_wert` und
`rahmenanteil` (in **Prozent**). Beides zugleich gibt es nicht.

**Zwei Fälle führen dorthin**, und beide stehen als `schichtlos` am Vorgang, mit Name,
U-Wert und Grund — `get_vorgang` zeigt sie:

| | |
|---|---|
| Der Katalogeintrag hat keine Schichten | Der Regelfall: Fenster, Türen, alle Typologiewerte |
| **Inhomogenes Bauteil** (Sparren neben Dämmung) | Der Katalog hält nur das **größte Gefach**; aus dem allein käme ein zu guter U-Wert. Also der U-Wert der Katalogzeile, der für das ganze Bauteil gilt |

Der Tausch ist bewusst: die schichtlose Form verliert Wärmespeicherfähigkeit, Tauwasser und
sommerlichen Wärmeschutz — die hängen an den Schichten. Sie gewinnt den U-Wert, und an dem
hängt die Bilanz.

**Abgewiesen wird, wo der U-Wert nicht eindeutig ist.** Ein Katalogwert wie `1,30 / 1,13`
ist kein Rechenwert: welcher davon für dieses Bauwerk gilt, sagt der Katalog nicht, und
gemittelt wird nichts (`u_wert_mehrdeutig`). Fehlt beides — Schichten und U-Wert —, kommt
`bauteil_ohne_u_wert`. Wärmebrücken bleiben draußen: ihr Psi ist W/(mK), kein U-Wert.

**Ein Fenster ohne g-Wert wird abgewiesen** (`fenster_ohne_g_wert`), statt eine Vorgabe zu
setzen. Ohne den Gesamtenergiedurchlassgrad fallen die solaren Gewinne auf null — das
Fenster sieht in jeder Ansicht richtig aus, der Heizwärmebedarf ist zu hoch, und nirgends
steht eine Meldung. 2.170 der 2.175 Katalogfenster führen ihn; der Abbruch trifft fünf.
Der **Rahmenanteil** ist dagegen keine Pflicht — ihn führt nur gut die Hälfte des Katalogs,
und ohne ihn fehlt nichts, was eine ganze Bilanzgröße wegnimmt.

**Die Software muss zu sein.** Eine offene Anwendung hält das Projekt im Speicher und
schreibt ihren Stand beim Beenden zurück. Neue Zeilen (`INSERT`) überstehen das, geänderte
(`UPDATE`) nicht — und eine Zuweisung ist ein `UPDATE`. Der Auftrag prüft es selbst und
bricht ab.

**`software_schliessen` beendet sie vorher**, geschlossen wird über das Fenster (WM_CLOSE),
nie hart — die Software darf ihren Stand zurückschreiben:

| Wert | |
|---|---|
| `nein` | Vorgabe. Läuft eine Anwendung, bricht der Auftrag ab. |
| `verwaiste` | Nur Prozesse **ohne Fenster**. Die hält der Mensch davor ohnehin für beendet — das darfst du selbst setzen. |
| `alle` | Auch das offene Fenster. Das ist die Arbeitsumgebung eines Menschen: **frag ihn, nimm seine Zustimmung nicht an.** |

Der Schritt steht **vor** dem Tor und ersetzt es nicht. Bleibt ein Speichern-Dialog offen,
läuft die Anwendung weiter, und der Auftrag bricht trotzdem ab — mit dem Fenstertitel in
der Meldung, damit erkennbar ist, worauf sie wartet. Ein Probelauf schließt nichts.

**Der Auftrag sichert den alten Stand, bevor er schreibt** (Regel HA-07). Er steht am
Vorgang; ohne ihn wäre ein Fehlgriff nur über ein Backup zu heilen, denn der Spiegel kennt
weder `CatalogDimUUID` noch den Marker.

**„Erledigt“ heißt noch nicht „angekommen“.** Erst wenn die Flächen im Spiegel die neue
Konstruktion tragen, ist die Zuweisung da — also `refresh_hottgenroth_components`, warten,
`get_hottgenroth_components`.

### `set_hottgenroth_raeume` — Zone, Nutzungsprofil und Raumstempel setzen (Recht `hottgenroth:schreiben`)

Richtet ein Wohngebäude als Einzonenmodell ein und setzt die Raumstempel — im Kundenprojekt
auf dem Rechner des Beraters.

| Feld | Typ | Bedeutung |
|---|---|---|
| `projekt` | string | **Pflicht.** Namensteil, Projektnummer oder GUID. |
| `geschosse_beheizt` | string[] | **Pflicht.** Geschosskürzel aus `get_hottgenroth_raeume`, deren Räume beheizt sind und in die Zone gehören. |
| `geschosse_unbeheizt` | string[] | Geschosskürzel, deren Räume unbeheizt sind und aus der Zone bleiben. **Jedes Geschoss mit Räumen muss in einer der beiden Listen stehen**, sonst bricht der Auftrag ab. |
| `profil` | enum | Nutzungsprofil der Zone, falls sie erst entsteht: `efh` (Vorgabe, „42 - Wohnung Einfamilienhaus") oder `mfh` („43 - Wohnung Mehrfamilienhaus"). |
| `zone_name` | string | Name der Zone, falls sie erst entsteht. Vorgabe „Wohnen". |
| `raumart_beheizt` | integer | Raumart für **alle** Räume der beheizten Geschosse. `0` (Vorgabe) lässt die Raumarten stehen und setzt nur den Heizstatus. |
| `raeume` | array | Ausnahmen je Raum, die nicht dem Geschoss folgen — werden **nach** der Geschossebene gesetzt. |
| `probelauf` | boolean | `true` rechnet durch und schreibt nichts. **Damit anfangen.** |

Je Eintrag in `raeume`:

| Feld | Typ | Bedeutung |
|---|---|---|
| `nr` | string | **Pflicht.** Raumnummer aus `get_hottgenroth_raeume`, z. B. `OG1-R1`. Nicht der Name. |
| `raumart` | integer | Aus dem Katalog unten. Bringt Heizstatus und Temperatur als Vorgabe mit. |
| `name` | string | Neuer Raumname, bis 60 Zeichen. |
| `status` | enum | `beheizt` oder `unbeheizt` — in `BmRoom` **und** im CAD-XML. |
| `temperatur` | number | Raumtemperatur in °C. Ohne Angabe die Vorgabe der Raumart bzw. des Status (20 beheizt, 10 unbeheizt). |
| `in_zone` | boolean | `true` ordnet den Raum der Zone zu, `false` nimmt ihn heraus. Weglassen lässt die Geschossebene entscheiden. |

**Der Raumartkatalog ist eine Positivliste:** 1 Wohnraum · 2 Schlafen · 3 Kind · 4 Küche ·
5 Essen · 6 Flur · 11 Bad/Dusche/Umkleideraum · 23 Kellerraum · 24 Heizungsaufstellraum ·
25 Dachraum · 34 Abstellraum · 42 Garage. Nur für diese ist die `mrt*`-Bezeichnung im CAD-XML
belegt; andere (WC-Raum, Treppenhaus, Heizraum, …) weist das Skript ab — ein erfundener Name
machte das XML unbrauchbar.

**Was der Auftrag tut, in dieser Reihenfolge** (`Setup-Wohngebaeude.ps1`, dann die
Ausnahmen, dann `Get-Raeume.ps1`):

1. Vorbedingungen: keine Hottgenroth-Anwendung offen, jedes Geschoss mit Räumen zugeteilt,
   Räume vorhanden. Bricht ab, **bevor** etwas geschrieben wird.
2. Sicherung der Datenbank nach `%TEMP%\hottgenroth-sicherung` — der Pfad steht im Bericht.
3. DIN-18599-Zone anlegen, falls keine existiert (Kopie einer vorhandenen Zone des Projekts,
   `ZoneType 5`, `HeatingType 1`, `InfoDesc` = Zonenkennung aus dem EE-Berater, falls lesbar).
4. Nutzungsprofil an die Zone, falls keines dran ist. **`ProfileUsageType` ist nicht die
   Zahl im Namen:** 42 → 34, 43 → 35.
5. Heizstatus je Geschoss (beidseitig), Zonenzuordnung der beheizten Räume, Entfernen der
   unbeheizten.
6. Die Ausnahmen aus `raeume`, raumgenau über `-Geschoss * -Raum <nr>`.
7. Invarianten prüfen und den Stand nachlesen.

**Vorher dem Menschen vorlegen, in Klartext je Raum:** „OG1-R1 Kellerraum → Wohnraum, beheizt,
20 °C, in die Zone". Ein falscher Stempel fällt in keiner Bilanz auf.

**Die Software muss geschlossen sein** — auch der EE-Berater (`EEBerater`) und HottCAD. Eine
laufende Anwendung schreibt ihr Modell beim Beenden zurück und verwirft alles von außen.
Das prüft `Assert-SoftwareZu` in jedem Skript; im Probelauf ist eine offene Software erlaubt.

**Danach `get_vorgang`.** `geschrieben` ist belastbar (`meta.schreibt_ab` nennt den
Einrichtungsschritt; im Probelauf schreibt kein Schritt). `ergebnis.bericht` ist die Ausgabe
der Einrichtung mit den Invarianten, `ergebnis.stand` der nachgelesene Stand. Zwei Dinge sind
dort **erwartet** und kein Fehler: im Probelauf rote Invarianten, wenn die Zone erst entstehen
muss — und nach einer raumgenauen Ausnahme der Befund „Heizstatus je Geschoss wie vorgegeben"
für genau diesen Raum, weil die Prüfung je Geschoss argumentiert. Ein Ausnahmeraum gehört in
die Projektnotiz.

**Was es nicht kann:** Räume zeichnen (das Polygon kommt aus HottCAD), eine **zweite** Zone
(der `[HASH8]` der Zonenkennung ist nicht nachbildbar), und den Übertrag in die `eberater.zip`
— Zone, Profil und Zuordnung stehen danach im Gebäudemodell; was die Software daraus macht,
sieht man erst nach Öffnen und Speichern: zeigt die Zone ihre Räume, und **rechnet sie ihre
Fläche nach** (`flaeche_gerechnet`)?

### `set_hottgenroth_heizung` — Anlagentechnik setzen (Recht `hottgenroth:schreiben`)

Ersetzt Heizung, Speicher und Warmwasserbereitung **einer Variante** im Kundenprojekt.

| Feld | Typ | Bedeutung |
|---|---|---|
| `projekt` | string | **Pflicht.** Namensteil, Projektnummer oder GUID. |
| `variante` | integer | **Pflicht.** Nummer der Variante. Aus `get_hottgenroth_heizung` — nicht raten. |
| `konfiguration` | string | ID oder Name aus dem firmenweiten Anlagenkatalog (`find_anlagen_konfigurationen`). **Der Normalweg**, auch für den Ist-Zustand. |
| `vorgabe` | enum | Ein geprüfter Vorgabesatz auf dem Arbeitsplatz: `waermepumpe-sanierung` (55/45, Heizkörper) oder `waermepumpe-flaechenheizung` (35/28, verlangt Flächenheizung). |
| `anlage` | object | Die vollständige Beschreibung im Austauschformat, so wie `get_hottgenroth_heizung` sie liefert. |

**Genau eines von `konfiguration`, `vorgabe` und `anlage`.** Irgendeine Beschreibung ist
Pflicht: ohne sie greifen die Vorgabewerte der Fabriken, und die passen zum Bestandskessel,
nicht zur Sanierung — 70/55 statt 55/45, kein hydraulischer Abgleich, überdimensionierte
Pumpe, und die Warmwasser-Verteilung fehlt ganz.

**`konfiguration` ist der Weg, den du zuerst versuchst.** Der Anlagenkatalog trägt, was in
dieser Software tatsächlich funktioniert — Bauarten, Regelungskennungen,
Auslegungstemperaturen. Die Antwort sagt über `wirkung_nachgewiesen` und `wirkung_beleg`,
ob für diese Konfiguration schon einmal gemessen wurde, dass ihre Wirkung im Rechenkern
ankommt. Ist sie es nicht, steht das als `warnung` dabei und **gehört in die Antwort an den
Menschen** (Regel SP-04). Drei Gründe, aus denen eine Konfiguration hier abgewiesen wird:
`gewerk_nicht_schreibbar` (Photovoltaik), `gewerk_falsches_werkzeug` (Lüftung — das
Austauschformat führt sie nicht) und `nutzlast_unvollstaendig` (Felder, die nur gemeinsam
gelten, stehen einzeln da).

**Den Ist-Zustand zu erfassen ist derselbe Aufruf** — nur mit der Variante des Ist-Zustands
(üblicherweise 2) und einer Konfiguration, die den **Bestands**kessel beschreibt, nicht die
geplante Wärmepumpe. Verwechselt man beides, rechnet der Fahrplan seine Einsparung gegen eine
Anlage, die es nie gab.

**Die vorhandene Heizung wird entfernt, nicht ergänzt.** Andere Varianten bleiben unberührt:
jede führt ihre eigene Anlagentechnik. Deshalb ist das Werkzeug als `destruktiv`
gekennzeichnet und nicht idempotent — ein zweiter Aufruf ersetzt erneut.

**Es wird nicht gerechnet, und damit ist es nicht fertig.** Der Auftrag schreibt den Graphen
in die Variante. Rechnen kann nur die Software, und dazu muss **ein Mensch das Projekt und
diese Variante öffnen** und speichern. Bis dahin ist die Anlage geschrieben, nicht
gerechnet — jede Zahl, die man ihr vorher zuschreibt, ist erfunden. Regel HA-01 gilt hier in
ihrer schärfsten Form:

1. `get_vorgang` — steht `geschrieben` auf `true`?
2. Den Menschen bitten, Projekt **und Variante** zu öffnen und zu speichern.
3. `get_hottgenroth_heizung` — **bewegt sich die Endenergie** gegenüber vorher?

Erst nach 3 ist die Anlage angekommen. Am 13.08.2026 lief ein vollständiger
Sanierungsfahrplan durch alle Prüfungen und war trotzdem falsch: alle Prüfungen waren
Selbstprüfungen — „steht da, was ich geschrieben habe". Ob es die Stelle erreicht, die
**rechnet**, beantwortet nur die Endenergie.

**`Energieberater.exe` muss geschlossen sein.** Eine laufende Instanz hält den Container im
Speicher und macht den Schreibvorgang beim nächsten Speichern kommentarlos rückgängig — ein
Prozess ohne Fenster zählt auch. Der Auftrag bricht dann mit einer Meldung ab, die die PID
nennt.

**Die Werkzeugkette liegt nicht beim Agent.** Die `ibp-*.exe` sind .NET Framework 4.8 und
laden `DIN18599DataModel.dll` aus der HSETU-Installation; der Agent läuft auf .NET 10 und
ruft sie deshalb als Unterprozess auf (`shell.run`). Wo sie liegen, steht in
`config/hottgenroth.php` unter `werkzeuge` (überschreibbar mit `HOTTGENROTH_WERKZEUGE`).
Fehlt etwas, bricht der **erste** Schritt ab und nennt die fehlenden Dateien — der Rechner
bleibt unberührt.

**Zwei Voraussetzungen am Arbeitsplatz**, und beide melden sich als Fehlschlag des Auftrags,
nicht als Fehler des Werkzeugs:

| Meldung im Vorgang | heißt |
|---|---|
| `shell.run ist auf diesem Arbeitsplatz abgeschaltet` | `AllowShell = false` in seiner `appsettings.local.json` — dieser Rechner bietet die Anlagentechnik nicht an. Ein Admin muss es freischalten. |
| `Die Werkzeugkette … fehlt auf diesem Rechner` | Die Kette ist dort nicht ausgerollt. Die genannten Dateien fehlen. |

Beides ist eine Sache für einen Menschen — nicht wiederholen, sondern weitergeben.

**`geschrieben` ist hier belastbar.** Der Auftrag trägt `meta.schreibt_ab` und nennt damit
den einen Schritt, der das Projekt verändert (`container.ps1 -Zurueck`). Bricht er vorher
ab — beim Prüfen, Holen, Lesen, Entfernen oder Anlegen —, meldet `get_vorgang`
`geschrieben: false`, und ein erneuter Aufruf ist gefahrlos. Alles davor arbeitet in einem
eigenen Ordner, der danach weggeräumt wird.

### `set_hottgenroth_sanierungsvarianten` — Fahrplan in die Software (Recht `hottgenroth:schreiben`)

Schreibt den in der fs-app gespeicherten Sanierungsfahrplan als Sanierungsvarianten ins
Kundenprojekt — je Maßnahmenpaket eine Variante, mit Bauteilmaßnahmen und Anlagentechnik.

| Feld | Typ | Bedeutung |
|---|---|---|
| `projekt` | string | **Pflicht.** Namensteil, Projektnummer oder GUID des Hottgenroth-Projekts. |
| `project_id` | integer | Das FS-Projekt, dessen Fahrplan geschrieben wird — aus `get_sanierungsplan`. |
| `crm_project_id` | string | Alternativ dazu: die Zoho-Projekt-Record-ID. |
| `ist_zustand` | integer | Nummer der Ist-Zustands-Variante, üblicherweise 2. Aus `get_hottgenroth_sanierungsvarianten` — nicht raten. |
| `pakete` | array | Nur diese Paketnummern schreiben. Leer lassen schreibt alle; das ist der Normalfall. |
| `basis` | enum | `kette` (Vorgabe) baut jede Variante auf der vorigen auf — ein Fahrplan. `ist` baut jede auf dem Ist-Zustand auf — eine einzelne Zielvariante. |
| `ohne_anlagen` | boolean | Nur Bauteilmaßnahmen, Anlagentechnik auslassen. Notausgang. |

**Vorher zweimal lesen:** `get_sanierungsplan` (was geschrieben werden soll — dem Menschen
vorlegen) und `get_hottgenroth_sanierungsvarianten` (welche Nummer der Ist-Zustand hat und
was das Projekt schon führt).

**`ist_zustand` ist der wichtigste Parameter.** Er ist die Vorlage jeder neuen Variante
**und** wird in deren `VarianteID` eingetragen. Steht dort etwas anderes — etwa ein
hochgezählter Zähler —, meldet die Software „Ist-Zustand nicht vorhanden!", der
Variantenwähler bleibt leer und der Fahrplan vergleicht gegen ein fremdes Gebäude.

### Angehängt, nie ersetzt (Regel HA-13)

Vorhandene Varianten bleiben unberührt; die neuen kommen dahinter. **Die Nummern vergibt
der Arbeitsplatz**, nicht der Server: welche `PROJEKT_ID` frei ist, steht nur im Container,
und sie laufen nicht lückenlos. Deshalb nennt die Antwort auch keine Variantennummer — sie
steht erst nach dem Lauf fest, im Protokoll des Vorgangs und in
`get_hottgenroth_sanierungsvarianten`.

Geprüft wird nur noch, ob der **Ist-Zustand** da ist. Fehlt er, bricht der Auftrag ab und
schreibt nichts.

**Löschen kann dieses Werkzeug nicht**, und das bleibt so: eine Variante trägt Arbeit, die
im Fahrplan der fs-app nicht steht — Fotos, Texte, Kennwerte aus der iSFP-Maske. Wegräumen
entscheidet ein Mensch, in der Software.

**Ein zweiter Aufruf legt zweite Varianten an.** Er überschreibt nichts, aber er ist auch
nicht wiederholbar — nach einem Abbruch erst `get_vorgang` lesen.

**`basis: ist`** ist der Fall „noch eine Zielvariante dazu": jede neue Variante baut dann
auf dem Ist-Zustand auf statt auf der vorigen. Für einen Fahrplan bleibt `kette` richtig,
sonst fehlen im zweiten Paket die Maßnahmen des ersten (Regel HA-06).

### Alles oder nichts

Der Container wird einmal geholt, alle Pakete entstehen in einer **Kopie**, und erst der
letzte Schritt schreibt zurück. Scheitert ein Paket, bricht der Auftrag ab und das
Kundenprojekt hat nie etwas davon gesehen. Deshalb gehören alle Pakete in einen Auftrag und
nicht in fünf.

`geschrieben` ist damit belastbar: `meta.schreibt_ab` nennt den einen Schritt
(`container.ps1 -Zurueck`), der das Projekt verändert.

### Was geschrieben wird und was nicht

- **`bauteil`** — ausgewählt über das `kennzeichen`, nie über eine Flächen-ID. Gesetzt
  werden Bezeichnung, Ziel-U-Wert, Dämmstoffdicke und -lambda sowie die Kosten. Danach
  läuft je Variante `uwerte-uebernehmen.ps1` — **der Schritt, den man von Hand vergisst**:
  ohne ihn zeigt die Variante sanierte Werte und rechnet mit den alten.
- **`anlage`** — ersetzt die Anlagentechnik der Variante vollständig, aus dem
  Anlagenkatalog. Nur Heizung und Warmwasser. Lüftung und Photovoltaik gehen diesen Weg
  **nicht**; sie erscheinen unter `uebersprungen`.
- **`umfeld`** — übersprungen. Gerüst und Blower-Door haben im Rechenmodell keine
  Entsprechung und zählen nur in der Kosten- und Förderrechnung.

Was übersprungen wurde, steht in der Antwort unter `uebersprungen`. **Lies es und sag es dem
Menschen** — sonst hält er den Fahrplan für vollständig.

### Die Beträge reisen als Gesamtbeträge

Die fs-app führt Euro, Hottgenroth führt Euro je Quadratmeter auf der **Brutto**fläche —
und die kennt nur der Container. Die Umrechnung macht deshalb der Arbeitsplatz: er summiert
`FLAECHE_BR` über alle getroffenen Bauteile und teilt. Bei einer Außenwand mit
Fensteröffnungen sind das 121,70 statt 99,02 m², und wer hier teilte, müsste die Fläche
raten.

### Es wird nicht gerechnet, und damit ist es nicht fertig

Der Auftrag baut die Varianten. Rechnen kann nur die Software, und dazu muss ein Mensch
**jede** Variante öffnen und speichern. Drei Schritte, alle nötig:

1. `get_vorgang` — steht `geschrieben` auf `true`?
2. Den Menschen bitten, jede Variante zu öffnen und zu speichern.
3. `get_hottgenroth_sanierungsvarianten` — **fällt die Endenergie je Paket?**

Erst nach 3 ist der Fahrplan angekommen. Bis dahin ist er geschrieben, nicht gerechnet —
und jede Zahl, die man ihm vorher zuschreibt, ist erfunden.

`warnungen` nennt Anlagenkonfigurationen ohne Wirkungsnachweis (`gerechnet = false`). Auch
das gehört in die Antwort an den Menschen.

**Energieberater.exe muss geschlossen sein.** Eine laufende Instanz hält den Container im
Speicher und macht den Schreibvorgang beim nächsten Speichern rückgängig.

---

### `set_hottgenroth_cad_bindung` — Variante bearbeitbar machen (Recht `hottgenroth:schreiben`)

Nimmt einer Sanierungsvariante die Bindung an das HottCAD-Modell — oder gibt sie ihr zurück.

| Feld | Typ | Bedeutung |
|---|---|---|
| `projekt` | string | **Pflicht.** Namensteil, Projektnummer oder GUID. |
| `variante` | string | **Pflicht.** Der **Name** der Variante, aus `get_hottgenroth_sanierungsvarianten`. Nicht die Nummer. |
| `richtung` | enum | `loesen` (Vorgabe) macht bearbeitbar, `setzen` bindet wieder an. |
| `probelauf` | boolean | `true` sagt nur, was stehen würde. **Damit anfangen.** |

**Das Symptom.** In der Variante steht „Diese Ansicht ist rein informativ und dient zur
Übersicht", und Flächen, Maße oder Bauteilzuordnung lassen sich nicht ändern. Die Software
blendet dort das Panel `PanelCADHinweis` ein: die Geometrie gehört der Zeichnung.

**Woran es hängt, ist ein Feld:** `TableZusatz.ProjektPfad3D` im Container. Steht dort
`Art=CAD`, ist die Variante gebunden; ist es leer, ist sie frei. Gemessen am 04.10.2026 an
einem Projekt mit drei Varianten — Ist-Zustand und die aus dem Modell erzeugte trugen den
Wert, eine von Hand angelegte nicht, und genau die ließ sich bearbeiten. Alles andere war
gleich: `ProjektGesperrt` leer, `PROJEKT_ART`/`ProjAnl_Art`/`ProjAnl_Erfass` identisch,
`VarianteID` bei beiden gesetzt, `Sperre=1` auf allen Hüllflächen. Von 116 Feldern in
`TableProjekt` unterschieden sich zwei, und keines davon war ein Schalter.

**Es gibt etwas auf.** Eine gelöste Variante **folgt dem Modell nicht mehr**. Ändert der
Berater später die Zeichnung, wandert die Änderung nicht mehr hinein — sie muss von Hand
nachgezogen werden. Das ist die Entscheidung eines Menschen, keine Aufräumarbeit: **vorher
fragen und diesen Preis dabei nennen.** Rückgängig macht es derselbe Aufruf mit
`richtung: setzen`; der Wert wird dann von einer noch gebundenen Variante übernommen, nicht
erfunden.

**Über den Namen, nicht über die Nummer** — anders als `set_hottgenroth_heizung`, und mit
Grund: `PROJEKT_ID` ist flüchtig. Werden Varianten gelöscht, vergibt die Software die Nummern
neu; dasselbe Paket trug am 03.10.2026 die 12 und am 04.10. die 3. Ein Auftrag mit einer
gemerkten Nummer träfe lautlos die falsche Variante. Nimm den Namen Zeichen für Zeichen aus
`get_hottgenroth_sanierungsvarianten` — die Software kürzt lange Namen im Container ab.

**Den Ist-Zustand gibt es hier nicht.** Er ist das Modell selbst; ihn zu lösen beträfe das
ganze Projekt. Der Auftrag weist ihn ab.

**Die Software muss geschlossen sein.** Sie hält den Container im Speicher und schreibt ihren
Stand beim Schließen zurück. Läuft sie, wird der Auftrag abgewiesen statt still überschrieben
— und ein Fenster zu heißt nicht Prozess beendet. Den geänderten Stand liest sie erst beim
nächsten Start.

**Nur eine Tabelle wird angefasst.** Der Arbeitsplatz prüft erst jede Tabelle des Containers
Satz für Satz gegen die Satzzahl im Kopf, baut dann **nur** `TableZusatz` neu auf und tauscht
im ZIP nur diesen Eintrag. Innerhalb der Tabelle reisen alle übrigen Felder als Rohbytes mit,
auch der BinaryFormatter-Graph in `Kernel18599V5`. Vor dem Schreiben liegt eine Sicherung des
ganzen Containers im Arbeitsordner, und nach dem Schreiben wird aus der Datenbank
zurückgelesen, nicht aus dem Speicher. Der Arbeitsordner bleibt nach einem echten Lauf
stehen — er ist der Rückweg; nach einem Probelauf wird er aufgeräumt.

### `import_hottgenroth_bilder` — Bilder in die Bilderverwaltung (Recht `hottgenroth:schreiben`)

Legt Fotos im Projekt an — mit **Funktion**, Name und Beschreibung. Die Funktion entscheidet,
wo das Bild im Fahrplan erscheint.

| Feld | Typ | Bedeutung |
|---|---|---|
| `projekt` | string | **Pflicht.** Namensteil, Projektnummer oder GUID. |
| `bilder` | array | **Pflicht.** 1 bis 20 Bilder, in der Reihenfolge, in der sie angelegt werden. |
| `ersetzen` | boolean | Einen belegten Platz neu belegen, statt das Bild abzulehnen. Überschreibt das Bild, das dort liegt. |
| `vorschau` | boolean | Nur prüfen, was geschähe. Der Auftrag läuft trotzdem auf dem Arbeitsplatz — er schreibt nur nicht. |

Je Eintrag in `bilder`:

| Feld | Typ | Bedeutung |
|---|---|---|
| `schluessel` | string | **Pflicht.** Aus der Antwort von `POST /api/mcp/dateien`. |
| `funktion` | enum | **Pflicht.** `titelbild`, `foto_heute`, `ansicht`, `unterlage`, `zonierung`, `systemgrenze` oder `unterschrift`. |
| `name` | string | **Pflicht.** Der Bildtitel, wie er gedruckt wird — kein Dateiname. |
| `beschreibung` | string | Die Bildunterschrift. Wird gedruckt. |
| `bildquelle` | string | Urheber, falls das Bild nicht vom Berater stammt. |
| `reihenfolge` | integer | Platz innerhalb der Funktion. Weglassen heißt: nächster freier. |

**Die Bytes reisen am Werkzeugaufruf vorbei** (Regel HA-04): jedes Bild zuerst an
`POST /api/mcp/dateien` (Feld `datei`, multipart, JPEG oder PNG, bis 40 MB), dann den
`schluessel` hier angeben. Der Endpunkt öffnet jedes Bild, bevor er es ablegt — eine Datei,
die nur so heißt, kommt nicht durch.

**Die vier Funktionen und wo sie landen:**

| `funktion` | `XimMediaType` | im iSFP | Anzahl |
|---|---|---|---|
| `titelbild` | 10 | `fotos/titel` | genau 1 |
| `foto_heute` | 12 | `fotos/fotoHeute/item` | üblicherweise 4 |
| `ansicht` | 13 | `fotos/ansichten/item` | beliebig |
| `unterlage` | 1 | — (nur beim Projekt) | beliebig |
| `zonierung` | 17 | — (nur beim Projekt, Zonierung nach DIN V 18599) | beliebig |
| `systemgrenze` | 18 | — (nur beim Projekt, thermische Hülle) | beliebig |
| `unterschrift` | 11 | — (Berichte der Software) | genau 1 |

In der Oberfläche steht der **Bildname** in `LongDesc`, die **Beschreibung** in `InfoDesc`,
das **Copyright** in `MediaCopyright` und die **Quelle** in `MediaLink` (`Hsetu.Modules.Media`,
`MediaElement`). `ShortDesc` zeigt die Oberfläche nicht — ein Bild, das nur dort einen Namen
trägt, erscheint ohne Bildnamen. Das Werkzeug schreibt den Namen deshalb in beide.

**Ein Bild ohne Funktion erscheint nirgends.** In der Oberfläche lässt sich ein Foto ohne
Zuordnung ablegen (`XimMediaType` 0); es liegt dann im Projekt und in keinem Fahrplan. Bei
Klenke lagen am 27.09.2026 zwei solche Bilder. Das Schema kennt deshalb keine freie Zahl und
keinen Vorgabewert.

**Die Beschreibung wird gedruckt.** Sie steht als Bildunterschrift im Fahrplan, und die
Druckanwendung bemängelt zu kurze. Nicht „Fassade", sondern „Verputzte Außenwand ohne
Dämmung, Carport an der Giebelseite". Der Auftrag nennt in der Antwort jedes Bild, das ohne
Text kommt — technisch erzwungen ist sie nicht.

**Belegte Plätze werden abgelehnt, nicht überschrieben.** Liegt auf `foto_heute` Platz 1
schon ein Bild, meldet der Arbeitsplatz das und legt dieses eine nicht an; die übrigen laufen
durch. Erst `ersetzen` belegt neu. Zwei Bilder desselben Aufrufs auf denselben Platz lehnt
schon das Werkzeug ab, bevor der Auftrag entsteht.

**Die Bilder gehen nicht in die iSFP-XML** — siehe Regel HA-12. Sie liegen in `PrMedia`, und
die Software setzt sie erst ein, wenn sie die `.mSFPprojekt` für die Druckanwendung erzeugt.
Dass in `iSFP2.xml` ein leerer Foto-Stream steht, ist der Normalzustand.

**`Energieberater.exe` muss geschlossen sein.** Eine laufende Instanz hält den Projektstand im
Speicher und macht den Import beim nächsten Speichern rückgängig. Der Auftrag bricht dann mit
einer Meldung ab, die die PID nennt.

**Danach zwei Schritte:**

1. `get_vorgang` mit der `vorgang_id` — dort steht, welche Bilder angelegt und welche
   abgelehnt wurden.
2. Den Menschen bitten, das Projekt **und die iSFP-Maske** einmal zu öffnen und zu speichern.
   Erst dadurch übernimmt die Maske die Bilder in ihre Bildliste.

**`geschrieben` ist belastbar.** Der Auftrag trägt `meta.schreibt_ab` und nennt damit den
einen Schritt, der das Projekt verändert. Alles davor — Ordner anlegen, Skript und Bilder
holen, Manifest ablegen — arbeitet im TEMP des Beraters und wird danach weggeräumt.

### `get_vorgang` — was aus einem Auftrag wurde (Recht `hottgenroth:lesen`)

Jedes schreibende Werkzeug hier stellt einen Auftrag und **wartet nicht**. Dieses
beantwortet, was daraus geworden ist — und vor allem die eine Frage, die über die nächste
Handlung entscheidet: **ist schon etwas geschrieben worden?**

| Feld | Typ | Bedeutung |
|---|---|---|
| `vorgang_id` | integer | Die Nummer aus der Antwort des anstoßenden Werkzeugs. Weglassen zeigt die letzten eigenen Vorgänge. |
| `projekt` | string | Schränkt die Liste auf ein Projekt ein. Nur ohne `vorgang_id` sinnvoll. |
| `protokoll` | boolean | Den Schrittverlauf mitliefern. Vorgabe `false`. |

**`geschrieben` ist das Feld, auf das es ankommt.** Die schreibenden Werkzeuge dieses
Bereichs sind alle nicht wiederholbar, und löschen geht über die Schnittstelle nicht:

| Wert | Was zu tun ist |
|---|---|
| `false` | Der Auftrag brach ab, **bevor** er etwas verändert hat. Erneut aufrufen ist gefahrlos, sobald die Ursache weg ist. |
| `"ungewiss"` | Er brach ab, **nachdem** er zu schreiben begann. **Nicht wiederholen** — erst nachsehen, was im Projekt steht. |
| `true` | Durchgelaufen. |

**`dateien`** listet, was der Auftrag in die fs-app geladen hat — die `.sqproj` eines
Exports, IFC und Grundrisse eines Modellexports — je mit `datei`, `art`, `groesse_mb`,
`link`, `gueltig_bis` und `seite`. Der **`link` funktioniert ohne Anmeldung**: er ist
signiert und läuft nach 72 Stunden ab (`hottgenroth.sqproj_export.link_stunden`). Das ist der
Link für den Menschen — zum Herunterladen, Weitergeben, auch auf dem Handy. Jeder Aufruf von
`get_vorgang` stellt einen frischen aus; ein abgelaufener ist also kein Fehler, sondern ein
Grund, noch einmal zu fragen. `seite` ist die Exporte-Seite der fs-app für wer dort
angemeldet ist. **`export_fehlt`** steht bei einem erledigten
`create_hottcad_projekt`, dessen Export nicht angekommen ist: das Projekt ist angelegt, die
Datei holt `export_hottgenroth_projekt` nach.

Das ist belegt, nicht geraten: der Server weiß beim Bauen der Schrittliste, ab welchem
Schritt geschrieben wird, und der Agent meldet, welchen er erreicht hat. Fehlt eine der
beiden Zahlen, steht dort `"ungewiss"` — nie ein Vorgabewert.

**`zustand`** ist die andere Achse: `wartet_auf_arbeitsplatz`, `wartet_auf_wiederholung`,
`wird_ausgefuehrt`, `erledigt`, `fehlgeschlagen`, `abgebrochen`. `erledigt` heißt **nicht**
„im Spiegel angekommen“ — das entscheidet erst `refresh_hottgenroth_components`.

**`diagnose`** steht bei einem Fehlschlag da und nennt, was auf dem Rechner los war:
`offene_programme` mit Name, **Fenstertitel** und `seit`, dazu `verwaist`. Der Fenstertitel
ist der Beweis für den Menschen — „Änderungen speichern?“ ist etwas anderes als ein bloß
offenes Programm.

Dazu: `schritt` (Nummer, von, Name), `frist_bis` (steht das in der Vergangenheit und der
Zustand ist `wird_ausgefuehrt`, hängt der Auftrag), `versuch`, `problem`, `was`, `link`.

**Nicht in der Antwort**: die Nutzlast und das Rohergebnis. Dort stehen SQL mit
eingesetzter Projekt-GUID, Dateischlüssel der Ablage, Kundennamen und bis zu achtzig
`element_uid`. Gezählt wird, nicht gezeigt.

Erreichbar sind ausschließlich Vorgänge des **eigenen** Arbeitsplatzes. Ein fremder und
ein nicht vorhandener Vorgang geben dieselbe Antwort `vorgang_unbekannt` — sonst verriete
Hochzählen, welche Nummern es anderswo gibt.

---

## Fehlercodes

| Code | Bedeutung | Nächster Schritt |
|---|---|---|
| `zugang_ohne_benutzer` | Das Token gehört keinem Menschen, oder es gibt ihn nicht mehr | Zugang mit `--user=<id>` neu ausstellen lassen |
| `kein_arbeitsplatz` | Dem Benutzer ist kein Arbeitsplatz zugeordnet | Agent einmal anmelden (`--anmelden`) **und** einmal laufen lassen (`--once`) — die Zuordnung entsteht erst beim Registrieren. Stand prüfen mit `php artisan hottgenroth:besitzer` |
| `projekt_unbekannt` | Kein eigenes Projekt passt zur Suche | Aus der mitgelieferten Liste wählen |
| `projekt_mehrdeutig` | Mehrere eigene Projekte passen | Genauer benennen oder die GUID verwenden |
| `vorgang_unbekannt` | Diesen Vorgang gibt es auf deinem Arbeitsplatz nicht | Eine Nummer aus der mitgelieferten Liste nehmen |
| `flaeche_fremd` | Eine `element_uid` gehört nicht zu diesem Projekt | Flächen aus `get_hottgenroth_components` mit `flaechen_einzeln: true` nehmen |
| `flaeche_doppelt` | Zwei Bauteile sollen dieselbe Fläche bekommen | Je Fläche genau ein Bauteil |
| `lage_passt_nicht` | Bauteilart und Lage der Fläche passen nicht zusammen | Anderes Bauteil oder andere Fläche |
| `bauteil_ohne_u_wert` | Weder Schichten noch U-Wert | Treffer wählen, der eines von beidem führt; `get_component_details` zeigt es |
| `u_wert_mehrdeutig` | Schichtlos und mit mehreren U-Werten (`1,30 / 1,13`) | Treffer mit **einem** U-Wert wählen — gemittelt wird nichts |
| `u_wert_unplausibel` | Der U-Wert liegt außerhalb 0,05 bis 10 W/(m²K) | Verrutschte Kommastelle im Katalog; berichtigen lassen |
| `fenster_ohne_g_wert` | Fenster ohne Gesamtenergiedurchlassgrad | Fenstertreffer mit g-Wert wählen — **keine Vorgabe setzen**, sonst fallen die solaren Gewinne auf null |
| `g_wert_unplausibel` / `rahmenanteil_unplausibel` | g über 1, oder Rahmenanteil unter 1 % bzw. über 95 % | Im Katalog steht vermutlich ein Prozentwert bzw. ein Anteil statt Prozent |
| `bauteilart_ohne_weg` | Wärmebrücke o. Ä. — kein Flächenbauteil | Anderen Treffer wählen |
| `zu_viele_bauteile` / `zu_viele_flaechen` | Mehr als 8 bzw. 80 je Aufruf | In mehreren Aufrufen, jeden einzeln prüfen |
| `varianten_vorhanden` | *(entfallen am 01.10.2026 — Varianten werden angehängt, Regel HA-13)* | Es wurde **nichts** geschrieben. Die vorhandenen muss ein Mensch in der Software löschen — sie tragen Arbeit, die im Fahrplan nicht steht |
| `sanierungsplan_fehlt` | Zum FS-Projekt ist kein Fahrplan gespeichert | Erst `save_sanierungsplan`, und den Plan vorher dem Menschen vorlegen |
| `paket_ohne_schreibbare_massnahme` | Ein Paket führt nur Umfeldmaßnahmen | Das Paket in `pakete` auslassen, oder ihm in der fs-app eine Bauteil- oder Anlagenmaßnahme geben |
| `keine_pakete_gewaehlt` | Die genannten Paketnummern gibt es im Plan nicht | Nummern aus `get_sanierungsplan` nehmen |
| `fs_projekt_ohne_bauteile` | Am FS-Projekt hängt kein Katalog-Bauteil | Erst `add_component_to_project`, oder `zuordnungen` angeben |
| `projekt_ohne_guid` | Das Projekt trägt keine gültige GUID, der Abruf lässt sich nicht stellen | Projekt über `/admin/hottgenroth` neu einlesen lassen |
| `bindung_unbrauchbar` | Variantenname leer, der Ist-Zustand gemeint, oder eine Richtung, die es nicht gibt | Den Namen Zeichen für Zeichen aus `get_hottgenroth_sanierungsvarianten` nehmen; es wurde **nichts** geschrieben |
| `datei_unbekannt` | Der Schlüssel zeigt auf keine hochgeladene .sqproj | Datei erst an `POST /api/mcp/dateien` schicken und den `schluessel` aus der Antwort verwenden |
| `datei_fehlt` / `datei_doppelt` | Weder `drive_datei` noch `datei` — oder beide | Genau eines übergeben |
| `drive_datei_unbekannt` | ID, Link oder Name findet in Drive nichts, die Datei liegt im Papierkorb, oder die Firmenverbindung darf sie nicht sehen | Link bzw. genauen Namen prüfen; eine Datei im privaten Ordner muss erst in den Kundenordner |
| `drive_datei_mehrdeutig` | Den Namen gibt es mehrmals in Drive | Den Menschen anhand von Ordner und Datum wählen lassen, dann die `id` übergeben |
| `drive_datei_unbrauchbar` | Keine .sqproj, ein Google-Format, über 40 MB, leer oder keine SQLite-Datei | Einen echten Export der Software wählen; eingestellt wurde nichts |
| `drive_download_unvollstaendig` | Bytezahl oder MD5 stimmen nicht mit Drive überein | Einmal erneut aufrufen; hält es an, melden |
| `drive_nicht_verbunden` | Die Drive-Verbindung der App steht nicht | Admin verbindet unter `/admin/drive` neu; bis dahin der Upload-Weg |
| `drive_fehler` / `ablage_fehlgeschlagen` | Drive lehnte ab bzw. die Ablage schrieb nicht | Später erneut; hält es an, melden |
| `gruppe_fehlt` | Kein Gruppenname beim Import | Projektreferenz des Kunden als `gruppe` übergeben |
| `flaechen_nicht_moeglich` | `create_hottcad_projekt` bekam ein Bauteil mit `element_uids` — ein neues Projekt hat noch keine Flächen | Ohne Flächen angeben; zuweisen danach mit `add_components` |
| `vorlage_fehlt` | Für `create_hottcad_projekt` ist keine Basisvorlage hinterlegt | Ein Admin lädt sie unter `/admin/hottgenroth` hoch; dem Menschen sagen |
| `kunde_fehlt` | Am Zoho-Projekt hängt kein Kunde mit Nachnamen | Im CRM den Lookup `Kunde` setzen, dann erneut |
| `objektadresse_fehlt` | Am Zoho-Projekt fehlen Straße oder Ort in den Gebäudedaten | Gebäudedaten im CRM ergänzen — eine Adresse wird nicht geraten |
| `arbeitsplatz_mehrdeutig` | Dem Benutzer gehören mehrere Arbeitsplätze | Einen der genannten Namen als `arbeitsplatz` übergeben |
| `arbeitsplatz_unbekannt` | Kein eigener Arbeitsplatz passt zum Namen | Aus der mitgelieferten Liste wählen |
| `bauteil_unbrauchbar` | Art, Lage, lambda oder `dicke_cm` sind nicht tragfähig | Die Angabe berichtigen; es wurde nichts geschrieben |
| `kein_schreibrecht` | Dem Zugang fehlt `hottgenroth:schreiben` | Von Hand vergeben: `php artisan mcp:token rechte <id> --hottgenroth-schreiben` |

Alle vier sind **fachliche** Ergebnisse: sie kommen mit `isError: false` und tragen die
Liste bzw. den nächsten Schritt gleich mit (Regel MW-01).

---

## Für Entwickler

Die Werkzeugnamen stehen nur in den Klassen unter `app/Ai/Tools/Hottgenroth/`. Der Bereich
ist in `App\Ai\ToolRegistry` als `BEREICH_HOTTGENROTH` registriert.

```
php artisan ai:tools                 # alle Werkzeuge als Markdown
php artisan test --filter=Hottgenroth
```

Die Eigentümerprüfung liegt bewusst **in** `GetHottgenrothComponentsTool::arbeitsplaetze()`
und nicht in einem eigenen Dienst — bei einer Aufrufstelle wäre das ein Service mit einem
Kunden. **Kommt ein zweites Werkzeug in diesen Bereich, gehört sie herausgezogen**, sonst
wächst genau das Muster verteilter `where('user_id', …)`, das anderswo schon Ärger gemacht
hat.
