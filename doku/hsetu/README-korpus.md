# HSETU-Software — dekompiliert

Quelltext aller HSETU-Installationen dieser Maschine, erzeugt mit `ilspycmd`.
Zweck: Herstellung von Interoperabilität für den eigenen Import (§69e UrhG).
**Nicht weitergeben, nicht ins Repository legen.**

Der erste Lauf am 09.08.2026 umfasste nur `Energieberater2022`. Der zweite deckt alle
21 Produkte ab — `C:\Program Files\HSETU`, `C:\Program Files (x86)\HSETU` und
`C:\ProgramData\HSETU`.

Eine `.cs` je Assembly statt der ilspycmd-Projektstruktur: für die Suche über den
Gesamtbestand ist eine Datei je Modul handlicher als zehntausende Einzeldateien.

## Was hier liegt

| Ordner / Datei | Inhalt |
|---|---|
| `eigen/` | Hsetu-, Hstac-, Hott-Module — die Fachlogik |
| `fremd/` | DevExpress und andere Fremdbibliotheken |
| `ressourcen/` | Satelliten-Assemblies (`*.resources`), nur Übersetzungen |
| `api/`, `api-fremd/` | je Modul die öffentliche Schnittstelle als Text |
| `API-UEBERSICHT.md` | **hier anfangen** — was die Software kann, nach Aufgaben geordnet |
| `MODULE.md` | Modulkatalog: was jede Bibliothek tut, wie die Software gebaut ist |
| `MODULE-ALLE.md` | alle 511 Module mit Zahlen, maschinell erzeugt |
| `DIN18599-ANLAGENTECHNIK.md` | wo die Anlagentechnik liegt und wie man sie setzt |
| `SANIERUNGSVARIANTEN.md` | wie Varianten entstehen, wie man eine **anlegt** und ein Bauteil „saniert" — dazu das `.BDExit`-Format vollständig |
| `steckbriefe.csv`, `steckbriefe.txt` | je Modul Attribute, Namensräume, Abhängigkeiten |
| `index.csv` | jede eindeutige Assembly: Zieldatei, Version, Fundorte |
| `vorkommen.csv` | jede Binärdatei der Installationen: Hash, Produkt, Einstufung |
| `api-typen.csv`, `api-mitglieder.csv` | Schnittstellenindex der Fachlogik, durchsuchbar |
| `api-typen-fremd.csv`, `api-mitglieder-fremd.csv` | dasselbe für die Fremdbibliotheken |
| `nativ-nicht-dekompilierbar.txt` | native Binärdateien, u. a. `Energie.exe` (289 MB) |
| `fortschritt.log`, `fortschritt-teil*.log` | Protokolle der Läufe |

**Zahlen:** 19.992 Binärdateien in den Installationen, davon 6.265 verwaltet und
13.727 nativ. Nach Deduplizierung über SHA-256 bleiben **3.901 eindeutige Assemblies**
— 1.538 eigene, 1.362 fremde, 1.001 Satelliten.

Die Oberfläche steckt im nativen Teil, die Fachlogik in `eigen/` — der interessante
Teil liegt also vollständig vor: 511 Modulnamen, 33.009 öffentliche Typen,
358.866 öffentliche Mitglieder. Die Fremdbibliotheken sind ebenfalls indiziert
(584 Module, 68.957 Typen, 612.875 Mitglieder), aber getrennt gehalten.

**Vollständig heißt hier: alles, was als .NET-Assembly vorliegt.** 6.494 native
Binärdateien bleiben außen vor — `Energie.exe` (289 MB), die Lizenzmodule, die
Druck- und Grafikbibliotheken. Dafür bräuchte es ein anderes Werkzeug.

## Wegweiser

Die Software ist Delphi, nach .NET übersetzt: Typen heißen `TDal…`, `TModel…`, `TFW…`,
jede Klasse trägt eine `MetaClass`. Zielframework ist **.NET Framework 4.8, x64**; die
Assembly-Version `6.6.8` entspricht dem `mod`-Feld im `SyncMeta` der Datenbankzeilen.

| Modul | wofür |
|---|---|
| `Hsetu.FW.ModelHelper` | Projektverwaltung, Im-/Export, Geometrie, Rechenschritte |
| `Hsetu.FW.ModelHelper.SQLite` | `.sqproj` lesen und schreiben — `TFWSQLiteProjectImporter` / `…Exporter` |
| `Hsetu.Model.Bim` | Gebäudemodell: `BmElement`, Wände, Fenster, Geschosse |
| `Hsetu.Model.Xim` | Modellkern, Referenz-Helfer (`TModelGEOReferenceHelper`) |
| `Hsetu.Model.Tim` | Technische Anlagen und Katalogdaten |
| `Hsetu.Model.Prm`, `.Prj` | Projektmodell, Medien |
| `Hsetu.Model.Dal.*` | Datenzugriff je Domäne, `…Ado` für SQL Server |
| `Hsetu.ConstructionCatalog.BL` | Bauteilkatalog — Konstruktionen, Schichten, Materialien |
| `Hsetu.Cad.Persistence` | CAD-Dokument als Stream, binär oder XML |

Alles Weitere in [`API-UEBERSICHT.md`](API-UEBERSICHT.md) (nach Aufgaben) und
[`MODULE.md`](MODULE.md) (nach Bibliotheken).

Drei Dinge, die man vorab wissen sollte und die dort belegt sind: der Kern ist
**cross-kompiliertes Delphi** (31 Module tragen `__Global`), daneben steht ein
**C#-Neubau** in den `.CS`-Modulen, und die **DIN-18599-Bilanz rechnet nicht
Hottgenroth**, sondern ein zugekaufter Kern des Fraunhofer-IBP
(`Hsetu.EbCalc.IbpKernel`).

Daraus folgt eine Falle, die eine eigene Datei bekommen hat: die **Anlagentechnik
der DIN-18599-Rechnung steht nicht in der Datenbank**, sondern als serialisierter
Objektgraph in einem Medienobjekt. Die `Pm*`-Tabellen sehen passend aus und sind
leer. Siehe [`DIN18599-ANLAGENTECHNIK.md`](DIN18599-ANLAGENTECHNIK.md).

Dasselbe noch einmal, anders verpackt: die **Sanierungsvarianten** des
Energieberaters liegen in einem zweiten Medienanhang, `eberater.zip`, als
BDE-Tabellen aus der Delphi-Zeit — siehe
[`SANIERUNGSVARIANTEN.md`](SANIERUNGSVARIANTEN.md). Wer Projektdaten sucht und in den
SQL-Tabellen nichts findet, sollte **immer zuerst in `PrMedia` sehen**.

## Zwei Erkenntnisse, die alles erklären

**1. Der `.sqproj`-Import ist kein Kopiervorgang.** `TFWProjectImporter.Execute()`
lädt die Datei in das Objektmodell, kopiert die Modellobjekte, fügt sie als **neue**
Objekte ein und lässt einen Serializer die Zeilen schreiben:

```csharp
LoadPrmAndPrj();                                    // LoadDeep = true
TModelProject tModelProject = CopyModelProject(…);
tModelProject.Insert();                             // neue Identitäten
tFWDalImporter.Execute();                           // TModelDatabaseImporter + Serializer
tModelProject.MergeDALObject();
```

Die Zeilen sind ein Nebenprodukt des Modells. Deshalb heißt Zeilengleichheit nicht
Verwendbarkeit: die Exportdatei ist dafür gemacht, durch diesen Importer zu laufen,
nicht direkt zurückgeschrieben zu werden. Das erklärt auch, warum `VariantRoot` nach
einem Software-Import anders aussieht — das Modell vergibt den Wert beim `Insert()`.

**2. Ungültige Verweise verschwinden wortlos.** Dasselbe Muster an mehreren Stellen:

```csharp
FGEOHelper.RawData = GeoDesc;  FGEOHelper.Valdidate();   // Tippfehler im Original
if (FGEOHelper.IsValid) { FGEOHelper.SetData(); }        // sonst: nichts
```

Kein Fehler, keine Meldung. Der GEO-Prüfer selbst ist allerdings großzügig —
`FElement != null && IsNotEmpty(FRawData)` —, Geometrie wird also angenommen,
solange `BmElement.GeoDesc` gefüllt ist.

## Suchen

```powershell
# Wo taucht ein Tabellenname auf?
Select-String -Path eigen\*.cs -Pattern 'XmProjectContent' -List

# Welche Klasse steckt hinter einem Typnamen?
Import-Csv api-typen.csv | Where-Object Typ -match 'ProjectImporter'

# Was kann eine Klasse?
Import-Csv api-mitglieder.csv | Where-Object Typ -eq 'TFWSQLiteProjectImporter'

# In welchen Produkten liegt eine Assembly?
Import-Csv index.csv | Where-Object Name -eq 'Hsetu.Model.Bim' | Select-Object Produkte
```

Gleicher Modulname bei anderem Inhalt: die erste Fassung heißt `<Name>.cs`, jede
weitere `<Name>~<hash8>.cs`. Welche aus welchem Produkt stammt, steht in `index.csv`.

## Neu erzeugen

```powershell
werkzeuge\dekompiliere-alles.ps1                 # Inventar, Plan, 8 Arbeiter
werkzeuge\dekompiliere-alles.ps1 -AusInventar    # ohne erneutes Hashen (~15 min schneller)
werkzeuge\dekompiliere-alles.ps1 -NurPlanen      # nur planen, nichts dekompilieren
werkzeuge\lies-api.ps1                           # api/ und die Index-CSVs neu bauen
```

Der Lauf ist wiederaufnehmbar: fertige Zieldateien werden übersprungen, geschrieben
wird erst in `.teil` und dann umbenannt. Fehlgeschlagene Aufrufe hinterlassen eine
`.err`-Datei neben dem Ziel.
