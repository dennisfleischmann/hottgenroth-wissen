# Konzept: Bauteile aus einer .sqproj auswählen und ins Projekt kopieren

Heute kennt die Oberfläche unter `/admin/hottgenroth` genau einen Weg für eine
`.sqproj`: **ganz oder gar nicht**. Die Datei wird als komplettes neues Projekt
importiert (`project.import`).

Was fehlt, ist der kleine Schritt: *„Aus diesem Projekt hätte ich gern diese
fünf Bauteile — in mein laufendes Projekt, sonst nichts."* Jede alte `.sqproj`
ist ein fertiger, geprüfter Bauteilkatalog; im Ordner `Downloads` liegen davon
zwei Dutzend. Dieses Konzept beschreibt, wie daraus eine Auswahl wird.

Grundlagen zum Datenmodell: [`bauteile/docs/hottgenroth-bauteil-sql.md`](../../bauteile/docs/hottgenroth-bauteil-sql.md).

> **Stand 09.08.2026 — die tragende Annahme dieses Entwurfs ist widerlegt.**
>
> Die *lesende* Hälfte ist gebaut: `bauteile.export` holt den Bauteilbestand an
> den Server, `/admin/hottgenroth/bauteile` zeigt ihn (siehe
> [README, „Bauteilbestand einsammeln"](../README.md#bauteilbestand-einsammeln)).
> Die Auswahlliste aus Abschnitt 5/7 kann damit aus dem Spiegel kommen, statt die
> `.sqproj` erneut zu parsen.
>
> Der *schreibende* Teil — Abschnitt 2, „kopieren statt nachbauen" — steht
> dagegen auf einer Annahme, die sich als falsch erwiesen hat. Die Dekompilierung
> der Software zeigt: sie schreibt ihre Zeilen nicht, sie **serialisiert ihr
> Objektmodell**. Zeilen sind ein Nebenprodukt. Ein zeilenweiser Kopiervorgang
> erzeugt deshalb einen Bestand, den das Modell so nie erzeugt hätte — beim
> Projekt-Import gemessen: gleiche Bauteile, gleiche Geometrie bis aufs Byte,
> aber fremde Varianten-Wurzeln und ein leeres HottCAD-Modell.
>
> Für `bauteile.copy` heißt das: vor dem Bau erst prüfen, ob die Software eine
> API zum Übernehmen von Katalogbauteilen hat, und diese über
> [`hsetu.bridge`](../README.md#hsetubridge) aufrufen — so wie es der
> Projekt-Import jetzt tut. Der dekompilierte Bestand liegt unter
> `C:\Projekte_Dev\hsetu-decompiled`; Ansatzpunkt sind die `Tc*`-Modelle in
> `Hsetu.Model.Tim` und die Katalog-Helfer in `Hsetu.Model.Xim`.
>
> Abschnitt 4 (GUID-Weißliste) bleibt gültig und hat sich bestätigt: `VariantRoot`
> ist genau die Falle, die dort beschrieben ist.

---

## 1. Was in einer .sqproj tatsächlich steckt

Gemessen an `strackerjan.sqproj` (15 MB, 686 Tabellen, davon 73 gefüllt):

| | |
|---|---|
| Bauteile (`TcBasis.ElementType = 2`) | **82** |
| davon **ohne** Schichten — U-Wert direkt eingetragen | **62** |
| davon mit Schichten | 20 |
| davon inhomogen (Gefache über `…LayerSection`) | 8 |
| verschiedene Bauteile nach Abzug der Variantenkopien | **16** |
| Variantenpräfixe | `VAR Fenster / HT`, `VAR Heizung`, `VAR Dach / PV`, `VAR Keller`, `VAR Fassade / Lüftung` |
| Kategorien (`GroupType`) | Wand 12, Tür 24, Fenster 20, Boden/Decke 12, Dach 14 |

Zwei Zahlen daraus bestimmen den ganzen Entwurf:

**62 von 82 Bauteilen haben keine Schichten.** Im iSFP-Bestand ist das der
Regelfall — der Berater trägt einen U-Wert ein („1919–1948 Massive
Konstruktion", U = 1,3), keinen Aufbau. Ein Weg, der Bauteile aus Schichten
*nachrechnet*, kann diese 62 überhaupt nicht abbilden.

**16 statt 82.** Die Software legt je Sanierungsvariante eine vollständige Kopie
jedes Bauteils an, erkennbar am Namenspräfix. Eine Auswahlliste, die alle 82
zeigt, ist unbrauchbar — sie muss auf die 16 zusammenfalten.

---

## 2. Die Entscheidung: kopieren statt nachbauen

Es gibt zwei Wege, ein Bauteil in ein anderes Projekt zu bekommen.

**Weg A — nachbauen** über den vorhandenen Baustein `bauteile.import`: Schichten
auslesen, als JSON schicken, U-Wert neu rechnen, Zeilen frisch schreiben.

**Weg B — kopieren**: die Zeilen des Bauteils 1:1 übernehmen, nur die GUIDs neu
vergeben und den Projektbezug umhängen.

Weg A scheidet aus, und zwar messbar. Von den 82 Bauteilen der Beispieldatei
könnte er **12** abbilden: die 62 ohne Schichten fallen weg (nichts zu rechnen),
von den verbleibenden 20 nochmal die 8 inhomogenen (Gefache kennt der Writer
nicht). Dazu kommt: ein Fensterbauteil trägt `FractionOfFrame`, `GValue`,
`ShadingCoefficient`, `FrameOI3UId`, `GlazingOI3UId` — Felder, für die die
`bauteile.import`-Nutzlast keine Entsprechung hat. Und es führt
`SyncVersion = 1.3.5.4`, während `BauteilWriter` fest `1.3.1.5` schreibt.

Weg B kennt diese Unterschiede gar nicht erst. Er überträgt, was dasteht — und
ist damit **typunabhängig**: Wand, Fenster, Dach, Gefach, U-Wert-Direkteingabe
laufen durch denselben Code. Genau das ist auch das Argument gegen „später mal
den Writer erweitern": jeder neue Bauteiltyp wäre wieder Arbeit, beim Kopieren
nie.

`bauteile.import` bleibt daneben bestehen. Es bleibt der richtige Weg, wenn ein
Bauteil **neu erfunden** wird (aus einer Schichtliste, aus Revit, aus einem
Regelsatz). Kopieren ist der Weg, wenn es **schon existiert**.

---

## 3. Kopierumfang: was zu einem Bauteil gehört

Fünf Tabellen, alle über `BasisUId` bzw. `DimensionUId` erreichbar:

```
TcBasis                     1 Zeile    212 Spalten   Identität, Typ, Name
  └─ TcBuildingElementDimension
                            1 Zeile    157 Spalten   U, R, d, ElementMeta, Fensterwerte
       ├─ …DimensionLayerSection
                            0..n       34 Spalten    Gefach-Abschnitte
       └─ …DimensionLayer   0..n       104 Spalten   Schichten
TcCatalogContents           1 Zeile     40 Spalten   Baum-Eintrag = Sichtbarkeit
```

Mehr nicht. `TcMaterial` ist in der Datei leer — Materialien stehen als Freitext
plus Kennwerte in der Schichtzeile, nicht als Verweis. Es gibt also keine
Abhängigkeit, die mitgezogen werden müsste.

Ein Bauteil kostet damit typischerweise 3–20 Zeilen. Der ganze Kopiervorgang
ist eine Transaktion von Sekunden, nicht von Minuten wie der Projekt-Import
(dort: 73 Tabellen, mehrere tausend Zeilen).

---

## 4. GUIDs: Weißliste statt Rundumschlag

Hier liegt der einzige echte Fallstrick, und er unterscheidet sich von dem, was
`ProjectImporter` tut.

Beim Projekt-Import wird **jede** Spalte vom Typ `uniqueidentifier` neu vergeben.
Das ist dort richtig: die Datei bringt ein geschlossenes Universum mit, alles
darin darf neue Namen bekommen. Beim Kopieren eines einzelnen Bauteils stimmt
das nicht mehr — die Zeilen verweisen nach außen, und zwar in drei Richtungen:

| Richtung | Beispielspalten | Behandlung |
|---|---|---|
| **nach innen** (kopierter Teilgraph) | `UId`, `GId`, `BasisUId`, `DimensionUId`, `LayerSectionUId` | neu vergeben, stabil gemappt |
| **auf das Zielprojekt** | `ProjectUId`, `TIMUId`, `CatalogUId`, `CatalogContentUId` | **überschreiben** mit den Werten des Ziels |
| **auf globale Kataloge** | `FrameOI3UId`, `GlazingOI3UId`, `MaterialUId` | **unangetastet lassen** |

Die dritte Zeile ist die wichtige. `FrameOI3UId` und `GlazingOI3UId` zeigen auf
LCA-Datensätze, die nicht im Projekt liegen, sondern in der geräteweiten
TIM-Datenbank. Wer sie mitmappt, zerschneidet den Verweis still — das Bauteil
sieht danach normal aus und hat keine Ökobilanzdaten mehr.

Konsequenz für die Umsetzung: **eine ausdrückliche Liste der zu mappenden
Spalten**, keine Typregel. Lieber eine Spalte zu wenig gemappt (dann zeigt sie
noch auf die Quelle, was auffällt) als eine zu viel (dann zeigt sie ins Leere,
was nicht auffällt).

Zwei Sonderfälle:

- **`VariantRoot` ist Text, kein `uniqueidentifier`** — enthält aber eine GUID,
  und zwar dieselbe wie `GId` derselben Zeile (in allen 82 geprüften Zeilen).
  Eine Typregel würde die Spalte übersehen. Sie muss mit derselben Zuordnung
  umgeschrieben werden, in geschweiften Klammern, wie die Quelle sie schreibt.
- **Die Null-GUID `AAAAAAAA-…` bleibt immer stehen.** Sie heißt „keine
  Referenz". `ProjectImporter.MappeGuid` macht das bereits richtig; die
  Kopierlogik muss dieselbe Regel führen.

Alles andere — Sentinels (`-987654321,99`, `-999`, `1899-12-30`), `SyncMeta`,
`SyncVersion`, `ElementMeta`, `SortNum` im Katalogbaum — wird **wörtlich
übernommen**. Nicht interpretieren, nicht neu berechnen. `RValue` steht bei
schichtlosen Bauteilen auf `+987654321,99`, also dem Sentinel *ohne* Vorzeichen;
wer solche Werte „repariert", macht sie kaputt.

---

## 5. Arbeitsteilung: Server liest, Agent schreibt

```
  Browser                     Laravel (fortrabbit)              Arbeitsplatz
  ────────                    ────────────────────              ────────────
  1 .sqproj hochladen  ──────▶ beim Upload einmal mit
                               PDO SQLite lesen, Bauteil-
                               liste speichern (~16 KB)
  2 Liste, gefiltert   ◀────── JSON, sofort — kein Agent
  3 auswählen, Ziel-
    projekt wählen,
    „Kopieren"         ──────▶ Auftrag anlegen:
                               http.download + bauteile.copy
                               (nur die BasisUIds)
                                        ──── Poll ────▶  Datei laden,
                                                         Zeilen kopieren,
                               Verlauf ◀────────────     Transaktion
  4 Fortschritt        ◀──────
```

Der entscheidende Zug ist Schritt 1: **die Auswahlliste entsteht am Server, nicht
am Arbeitsplatz.** Eine `.sqproj` ist eine SQLite-Datei, PHP kann sie mit
`pdo_sqlite` direkt lesen — dieselbe Erweiterung, die die Testsuite ohnehin
braucht. Damit ist die Liste sofort da, statt über eine Poll-Runde von 15
Sekunden zu gehen. Der Agent kommt erst ins Spiel, wenn wirklich geschrieben
wird.

Gelesen wird zum Zeitpunkt des Uploads, aus dem temporären Pfad
(`$datei->getRealPath()`), **bevor** die Datei auf die Disk wandert. In
Produktion liegt sie danach in der Object Storage; sie von dort nur zum
Auflisten wieder zu holen, wäre 15 MB Transfer für 16 KB Ergebnis.

Vorschlag für die Ablage der Liste: eine Tabelle `hottgenroth_sqproj_bauteile`
(`upload_key`, `basis_uid`, `name`, `basis_name`, `variante`, `group_type`,
`usage_type`, `u_wert`, `dicke`, `schichten`, `inhomogen`) plus
`hottgenroth_sqproj_dateien` für die Datei selbst. Die Bauteilliste ist dann
nebenbei die Grundlage der Bibliothek aus Abschnitt 10.

---

## 6. Neuer Baustein: `bauteile.copy`

Der einzige Client-Code, der geschrieben werden muss. Vertrag:

```json
{ "use": "bauteile.copy", "with": {
    "source":     { "path": "{{ datei.path }}" },
    "target":     "{{ projekt_guid }}",
    "basisUIds":  ["{78511872-0d29-4ae4-b6b3-6e61a6729865}", "…"],
    "prefix":     "",
    "onDuplicate":"abort",
    "dryRun":     false,
    "database":   "HsetuPrjData" }}
```

| Feld | Bedeutung |
|---|---|
| `source.path` / `source.url` | die `.sqproj`, wie bei `project.import` |
| `source.project` | **statt** einer Datei: eine Projekt-GUID in derselben Datenbank (siehe Abschnitt 9) |
| `target` | Projekt-GUID oder eindeutiges Namensfragment, wie bei `bauteile.import` |
| `basisUIds` | Auswahl. Leer = alle Bauteile der Quelle |
| `prefix` | Namenspräfix, z. B. `"VAR Fassade: "` |
| `onDuplicate` | `abort` (Vorgabe), `skip`, `rename` (` (2)` anhängen) |
| `dryRun` | Transaktion am Ende zurückrollen |

Rückgabe je Bauteil: `name`, `basis_guid` (der **neue**), `group_type`,
`u_wert`, `zeilen`. Insgesamt `count`, `skipped`, `dry_run`.

Ablauf im Baustein:

1. Ziel auflösen → `TcCatalog.UId` + `TIMUId`, `TcCatalogContent.UId` des
   Ordners mit `CatalogContainerType = 6`. Fehlt der Katalog, sauber abbrechen
   („Projekt in der Software einmal öffnen und speichern") — die Prüfung steht
   schon in `BauteilWriter.LiesKatalogAsync` und ist wiederverwendbar.
2. Quelle öffnen (SQLite lesend oder dieselbe SQL-Verbindung).
3. Je gewähltem `BasisUId` den Teilgraph lesen: Basis, Dimension, Sections,
   Layer, Katalogeintrag.
4. Namen bilden, Dubletten nach `onDuplicate` behandeln.
5. GUIDs nach Abschnitt 4 abbilden, Projektbezug überschreiben.
6. In **einer** Transaktion über alle Bauteile schreiben; bei `dryRun` zurückrollen.

Wiederverwendbar aus dem Bestand: `SqprojReader` (Lesen), `SchemaCatalog`
(Spaltentypen, echte Primärschlüssel), `ProjectImporter.KonvertiereWert`
(SQLite → SQL Server, schwach typisiert → Zieltyp) und `MappeGuid` (stabile
Zuordnung). Der neue Code ist im Wesentlichen die Auswahlabfrage und die
Spalten-Weißliste — geschätzt 250–350 Zeilen in einer Klasse
`Hottgenroth/BauteilCopier.cs`.

Reihenfolge beim Schreiben: Basis → Dimension → Sections → Layer →
Katalogeintrag. Der Katalogeintrag zuletzt, weil er der Sichtbarkeitsschalter
ist: bricht etwas vorher ab, existiert kein halb sichtbares Bauteil.

---

## 7. Oberfläche

Eine zweite Karte auf `/admin/hottgenroth`, unter „Projekt importieren":
**„Bauteile aus einem Projekt übernehmen"**. Bootstrap + fetch wie der Rest der
Seite, kein neues Frontend-Bündel.

```
┌─ Bauteile aus einem Projekt übernehmen ──────────────────────────────┐
│ Quelle   [ Datei wählen … .sqproj ]  oder  [ zuletzt hochgeladen ▾ ] │
│                                                                      │
│ ▸ 16 Bauteile gefunden (82 inkl. Variantenkopien)                    │
│   Variante: [ Ist-Zustand ▾ ]   Kategorie: [ alle ▾ ]   [ Suche … ]  │
│   ┌────────────────────────────────────────────────────────────────┐ │
│   │ ☑ Außenwand 1919–1948, zweischalig      Wand/außen  U 1,30  –  │ │
│   │ ☑ Sparrendach 10 cm Dämmung             Dach/außen  U 0,32  ⌗  │ │
│   │ ☐ Kellerdecke unbeheizt                 Boden/Kell. U 0,90  ▤3 │ │
│   │ ☐ Kunststofffenster Isolierverglasung   Fenster     U 3,00  –  │ │
│   └────────────────────────────────────────────────────────────────┘ │
│         ▤n = n Schichten   ⌗ = inhomogen (Gefach)   – = U-Wert direkt │
│                                                                      │
│ Arbeitsplatz [ Dennis ▾ ]   Zielprojekt [ Werner Grotz ▾ ] [↻]       │
│ Namenspräfix [                    ]   ☐ Probelauf                    │
│                                          [ 2 Bauteile kopieren ]     │
└──────────────────────────────────────────────────────────────────────┘
```

Vier Dinge, die die Liste leisten muss:

- **Variantenkopien zusammenfalten.** Nach `^VAR [^:]+: ` gruppieren, den Rest
  als Basisnamen führen, die Variante als Filter anbieten. Sonst stehen 82
  Zeilen da, von denen 66 Dubletten sind.
- **Typ als Klartext**, nicht als Zahlenpaar: die Zuordnung `GroupType` ×
  `UsageType` → „Wand gegen außen" steht fertig in
  [`hottgenroth-bauteil-sql.md`, Abschnitt 6](../../bauteile/docs/hottgenroth-bauteil-sql.md).
- **U-Wert zeigen.** Das ist die Spalte, nach der ausgewählt wird.
- **Kennzeichnen, was drinsteckt** — Schichten, Gefach oder nur ein U-Wert. Das
  ist der Unterschied zwischen „damit kann ich weiterarbeiten" und „das ist eine
  Zahl".

**Zielprojekt.** Die Projektliste liegt auf dem Arbeitsplatz, nicht am Server.
Zwei Stufen:

1. *Sofort machbar:* Freitextfeld. `bauteile.copy` löst ein Namensfragment
   genauso auf wie `bauteile.import` und bricht bei Mehrdeutigkeit ab.
2. *Besser:* Knopf „↻", der einen `sql.query`-Auftrag stellt
   (`SELECT UUID, LongDesc FROM PrProject ORDER BY LongDesc`) und das Ergebnis
   am Agent zwischenspeichert (`hottgenroth_agents.projects_cache`,
   `projects_synced_at`). Danach ein echtes Auswahlfeld. Kostet eine Poll-Runde,
   aber nur einmal.

Serverseitig kommen dazu: `POST /api/admin/hottgenroth/sqproj` (Upload +
Auflistung), `GET …/sqproj/{id}/bauteile` (Liste, gefiltert),
`POST …/sqproj/{id}/kopieren` (Auftrag anlegen). Alles in
`HottgenrothTaskController` neben `store()`.

---

## 8. Der erzeugte Auftrag

```json
{
  "steps": [
    { "name": "Quelldatei laden",
      "use": "http.download",
      "with": { "url": "files/uploads/strackerjan-20260808-131502-3Tzi2Y.sqproj" },
      "register": "quelle" },

    { "name": "2 Bauteile kopieren",
      "use": "bauteile.copy",
      "with": {
        "source": { "path": "{{ quelle.path }}" },
        "target": "{{ projekt }}",
        "basisUIds": ["{78511872-…}", "{2d9e4993-…}"],
        "onDuplicate": "abort",
        "dryRun": false,
        "database": "HsetuPrjData" },
      "register": "kopie" },

    { "name": "Gegenprobe",
      "use": "sql.query",
      "with": { "sql": "SELECT COUNT(*) FROM TcCatalogContents WHERE ProjectUId = '…' AND BasisUId IN (…)" },
      "register": "probe" },

    { "name": "Muss 2 sein",
      "use": "assert",
      "with": { "that": "{{ probe.scalar }}", "equals": "2" } }
  ]
}
```

Bemerkenswert: bis auf `bauteile.copy` ist daran nichts neu. Der Auftragstyp
entsteht als Zusammenstellung — genau die Eigenschaft, für die die Step-Engine
gebaut wurde.

---

## 9. Dieselbe Mechanik ohne Datei: Projekt → Projekt

Setzt man statt `source.path` ein `source.project` mit einer Projekt-GUID, liest
der Baustein die Quellzeilen aus derselben SQL-Verbindung statt aus SQLite.
Alles andere bleibt gleich — dieselbe Weißliste, dieselbe Zuordnung, dieselbe
Transaktion.

Damit fällt ohne Zusatzarbeit ab:

- **Bauteile aus einem beliebigen Projekt der Arbeitsstation übernehmen**, ohne
  vorher zu exportieren.
- **Variante befüllen**: dasselbe Projekt als Quelle *und* Ziel, mit
  `prefix: "VAR Fassade: "`. Das ist genau das, was die Namen im Bestand nahelegen.
- **Nach „Meine Bauteile"**: Ziel `HsetuUsrData`, `ProjectUId` = Null-GUID statt
  Projekt-GUID. Ein Bauteil, das dort liegt, steht in jedem künftigen Projekt
  zur Verfügung. Der Weg ist in
  [`insert-bauteil-meine.sql`](../../bauteile/tools/insert-bauteil-meine.sql)
  vorgezeichnet, seit den letzten Korrekturen aber nicht erneut getestet.

Der Auswahl-Dialog braucht dafür nur eine zweite Quellart; die Liste kommt dann
über `sql.query` statt aus der hochgeladenen Datei.

---

## 10. Ausbaustufe: Bauteilbibliothek über alle Projekte

Wenn jede hochgeladene `.sqproj` beim Upload ohnehin ausgelesen wird, entsteht
der Index von selbst. Zwei Dutzend alte Projektdateien ergeben grob
20 × 16 ≈ **300 geprüfte Bauteile**, durchsuchbar nach Typ, U-Wert-Band und
Baualtersklasse.

Der Schritt dorthin ist klein — dieselbe Tabelle, ein zusätzlicher Einleseweg
(„Ordner mit .sqproj-Dateien einlesen") und eine Suchmaske. Erst dann steht die
eigentliche Frage: **Dublettenerkennung**. „Außenwand 1919–1948" kommt in jedem
zweiten Projekt vor, mal identisch, mal leicht abweichend. Ein Fingerabdruck aus
`GroupType`, `UsageType`, gerundetem U-Wert und der Schichtfolge (λ, d je
Schicht) würde das erschlagen — offen, ob er in der Praxis trägt.

Das ist bewusst eine spätere Stufe. Der Nutzen aus Abschnitt 1–8 hängt nicht
daran.

---

## 11. Was ausdrücklich nicht dazugehört

**Die Zuweisung ans Gebäude.** Ein kopiertes Bauteil liegt im Katalog. Es ist
damit *keine* verbaute Wand — dafür wären `TcElementReference` und die
`BmElement*`-Tabellen zuständig (in der Beispieldatei: 115 `BmElement`-Zeilen,
57 davon Wände). Diese Verknüpfung ist noch nicht analysiert und gehört in einen
eigenen Schritt. Die Oberfläche sollte das benennen, statt es offenzulassen:
*„Die Bauteile stehen anschließend im Katalog des Projekts. Die Zuordnung zu
Wänden und Fenstern erfolgt in der Software."*

**Geometrie, Zonen, Anlagentechnik.** Alles, was `project.import` mitbringt.
Wer ein ganzes Projekt will, nimmt weiter den Projekt-Import.

**Der Materialkatalog.** Bleibt unangetastet — Schichten tragen ihre Kennwerte
selbst.

---

## 12. Stolpersteine

- **Software schließen, danach neu starten.** Der Katalog wird beim Laden
  gelesen. Ohne Neustart erscheint nichts; bei laufender Software werden
  `UPDATE`s zurückgeschrieben. `agent.diagnose` meldet `software_laeuft` — der
  Auftrag sollte das voranstellen und bei laufender Software abbrechen, statt es
  zu versuchen.
- **Namensdubletten.** Innerhalb eines Projekts ist der Name faktisch der
  Schlüssel für den Menschen. `onDuplicate: "abort"` als Vorgabe, damit sich
  nichts still ansammelt.
- **`GId` ≠ `UId` in der Quelle.** `BauteilWriter` setzt beim Neuanlegen
  `GId = UId`; in gewachsenen Projekten ist `GId` etwas anderes (die
  Variantenwurzel). Beim Kopieren gilt: mappen, nicht gleichsetzen.
- **`SortNum` im Katalogbaum** (Werte wie 9, 380, 599) bestimmt die Position in
  der Liste und ist offenbar aus dem Typ abgeleitet. Wörtlich übernehmen —
  eigene Werte zu erfinden sortiert das Bauteil an eine unerwartete Stelle.
- **Die Datei ist eine Momentaufnahme.** Ein Bauteil aus einer `.sqproj` von 2024
  trägt die Kennwerte von 2024. Für den Bestand richtig, für aktuelle
  Anforderungen unter Umständen nicht.
- **`pdo_sqlite` in Produktion.** Lokal vorhanden (PHP 8.4). Vor der Umsetzung
  auf fortrabbit prüfen — ohne die Erweiterung fällt die serverseitige
  Auflistung aus und müsste über einen `sql.query`-Umweg am Agent laufen.

---

## 13. Umsetzung in vier Schritten

| # | Schritt | Wo | Prüfbar durch |
|---|---|---|---|
| 1 | `BauteilCopier` + Baustein `bauteile.copy` | `hottgenroth-agent/src/…/Hottgenroth/`, `Steps/Primitives/` | `--payload-file` mit einem Bauteil, `dryRun: true`, dann echt; Bauteil in der Software prüfen |
| 2 | Upload + Auflistung serverseitig | `HottgenrothTaskController`, neue Migration | Liste im Browser gegen die Zahlen aus Abschnitt 1 |
| 3 | Auswahlkarte in der Oberfläche | `resources/views/admin/hottgenroth.blade.php` | Auswahl → Auftrag → Bauteil im Zielprojekt |
| 4 | Projektliste je Arbeitsplatz zwischenspeichern | Agent-Modell + `sql.query`-Auftrag | Auswahlfeld statt Freitext |

Schritt 1 ist für sich nutzbar — über die Kommandozeile
(`php artisan hottgenroth:task add --payload-file=…`) lässt sich damit sofort
kopieren, bevor eine einzige Zeile Oberfläche existiert. Das ist auch die
Reihenfolge, in der sich Fehler am billigsten finden lassen.

---

## 14. Offene Punkte

- **Varianten.** In der geprüften Datei sind sie *nur* am Namenspräfix erkennbar:
  `PrVariant` und `TcDimensionVariant` sind leer, `VariantRoot` trägt je Zeile
  die eigene `GId`. Ob die Software Varianten anderswo verknüpft — und ob ein
  kopiertes Bauteil deshalb in einer Variante fehlt — ist nicht geprüft. Der
  Trace-Zyklus aus
  [`hottgenroth-bauteil-sql.md`, Abschnitt 10](../../bauteile/docs/hottgenroth-bauteil-sql.md)
  beantwortet das: in der Software ein Bauteil in eine Variante kopieren und
  mitschneiden.
- **`ContentLevel`** steht in der Beispieldatei auf `5`, in der Doku auf `7`.
  Beim Kopieren egal (der Ordner wird nicht angelegt), beim Anlegen eines neuen
  Ordners nicht.
- **Fenster mit LCA-Bezug** (`FrameOI3UId`, `GlazingOI3UId`): dass die Ziel-TIM-
  Datenbank dieselben GUIDs führt, ist plausibel, aber unbelegt. Ein
  Fensterbauteil sollte im ersten Durchgang bewusst mitkopiert und in der
  Software auf seine Ökobilanzdaten hin angesehen werden.
