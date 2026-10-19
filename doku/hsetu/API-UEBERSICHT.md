# Was die Software kann — Übersicht über die Schnittstelle

Stand 09.08.2026. Grundlage: die dekompilierten Module unter `eigen/`, ausgelesen mit
`werkzeuge\lies-api.ps1`.

**511 kanonische Module, 33.009 öffentliche Typen, 358.866 öffentliche Mitglieder**
(218.317 Methoden, 126.563 Eigenschaften, 13.986 Enum-Werte).

Eine Liste aller Funktionen wäre bei dieser Größe unbrauchbar. Diese Datei ordnet den
Bestand nach Aufgaben und nennt je Aufgabe die Einstiegspunkte. Der vollständige
Bestand liegt maschinenlesbar daneben:

| Datei | Inhalt |
|---|---|
| `api\<Modul>.api.txt` | je Modul: Namensräume, Typen, öffentliche Mitglieder |
| `api-typen.csv` | jeder öffentliche Typ — Modul, Namensraum, Art, Deklaration |
| `api-mitglieder.csv` | jedes öffentliche Mitglied — Modul, Typ, Art, Deklaration |
| `api-fremd\`, `api-typen-fremd.csv`, `api-mitglieder-fremd.csv` | dasselbe für die Fremdbibliotheken |
| `index.csv` | jede eindeutige Assembly — Zieldatei, Version, Fundorte |
| `vorkommen.csv` | jede Binärdatei der Installationen — Hash, Produkt, Einstufung |
| [`MODULE.md`](MODULE.md) | derselbe Bestand nach **Bibliotheken** statt nach Aufgaben |
| [`DIN18599-ANLAGENTECHNIK.md`](DIN18599-ANLAGENTECHNIK.md) | wo die Anlagentechnik liegt (nicht in SQL) und wie man sie setzt |

Der Fremdanteil ist getrennt gehalten, weil er den eigenen erdrückt: 584 Module mit
**68.957 Typen und 612.875 Mitgliedern** — doppelt so viel wie die Fachlogik, und
für die Frage „was kann die Software" fast nie die Antwort. Wer eine
DevExpress-Signatur sucht, sucht dort; alles andere steht unten.

```powershell
# Wo steckt ein Typ?
Import-Csv api-typen.csv | Where-Object Typ -match 'ProjectImporter'

# Was kann eine Klasse?
Import-Csv api-mitglieder.csv | Where-Object Typ -eq 'TFWSQLiteProjectImporter'

# Volltext über den Quelltext
Select-String -Path eigen\*.cs -Pattern 'class TModelGEOReferenceHelper'
```

## Wie der Bestand aufgebaut ist

| Familie | Typen | Module | wofür |
|---|---:|---:|---|
| `Hsetu.Model.*` | 17.967 | 59 | Domänenmodelle und Datenzugriff — der Kern |
| `Hsetu.FW.*` | 3.628 | 21 | Rahmenwerk: Projektverwaltung, Im-/Export, Berechnungsschritte |
| `Hsetu.Sim.*` | 2.161 | 181 | Simulation (Anlagen, PV, Klima, Solver) |
| `Hsetu.EcoBilancing.*` | 1.826 | 63 | Ökobilanzierung, DGNB |
| `Hsetu.BuildingModule.*` | 1.151 | 2 | Gebäudeeingabe |
| `Hsetu.Reporting.*` | 658 | 6 | Druck und Ausgabe |
| `Hsetu.CatalogSelection.*` | 579 | 5 | Produktauswahl (Wärmepumpen, Infrarot, Umi) |
| `Hsetu.Cad.*` | 502 | 11 | CAD-Kern, Heizung, Sanitär |
| `Hsetu.Assistant.*` | 387 | 6 | Assistenten |
| `Hsetu.HeatPumpConsultant.*` | 315 | 6 | Wärmepumpen-Beratung |
| `Hsetu.ThermalBridges.*` | 313 | 18 | Wärmebrücken |
| `Hsetu.ConstructionCatalog.*` | 255 | 4 | Bauteilkatalog |

Nach Rolle im Namen: 4.535 Katalog-, 1.231 Druck-/Report-, 1.126 Fabrik-, 591 Helfer-,
572 Berechnungs-, 497 Lizenz-, 283 Dienst-, 161 Provider-, 154 Manager-, 55 Serializer-,
38 Exporter- und 27 Importer-Typen.

## 1. Projekte: importieren, exportieren, kopieren

Der am besten untersuchte Bereich — hier läuft der eigene Import.

| Klasse | Modul | Zweck |
|---|---|---|
| `TFWProjectImporter` / `TFWProjectExporter` | `Hsetu.FW.ModelHelper` | Projekt-Im-/Export über das Objektmodell |
| `TFWSQLiteProjectImporter` / `…Exporter` | `Hsetu.FW.ModelHelper.SQLite` | `.sqproj` lesen und schreiben |
| `TFWDesktopSQLiteProjectImporter` / `…Exporter` | `Hsetu.FW.ModelHelper.Desktop` | dieselbe Aufgabe mit Desktop-Einstellungen |
| `TFWDalImporter` / `TFWDalExporter` | `Hsetu.FW.ModelHelper` | Zeilenebene: Serializer schreibt den Bestand |
| `TModelDatabaseImporter` / `…Exporter` | `Hsetu.Model.Dal.Provider` | eine Ebene tiefer, direkt am Provider |
| `TFWProjectCopyHelper`, `TFWPrmProjectCopyHelper` | `Hsetu.FW.ModelHelper` | Projekt kopieren |
| `PrmProjectCopyHelper`, `CopyModelProject` | `Hsetu.FW.Core` | Modellkopie, `ProjectVariantCopyOptions` |
| `DuplicateModelProjectCommand` | `Hsetu.FW.Core` | Projekt duplizieren als Befehl |
| `TFWDesktopDalHelper` | `Hsetu.FW.ModelHelper.Desktop` | Zieldatenbank aus den Einstellungen |
| `TFWProjectManager` | `Hsetu.FW.ModelHelper` | Projektverwaltung, Fabrik für Projektgruppen |

**Verifiziert** (läuft im Auftrag `projekt.import.bruecke`): `TFWDesktopDalHelper.GetDalsAndProvider(dctProject)`
→ `DalDatabaseProvider.Open()` → `TFWProjectManager.Instance` mit `PrmProjectFactory`
(Eigenschaften `PrmProjectManager` und `DalCoreList` selbst setzen!) →
`GetPrmProjectGroup(eInsertContainer)` → `InsertDALObject()` →
`new TFWSQLiteProjectImporter(gruppe, ziel, datei, null)` → `Execute()`.

**Bekannte Sackgassen:** `TFWAdoProjectManager.Instance` wirft ohne Oberfläche eine
`NullReferenceException`. Die Fabrik aus `TFWProjectManager.Instance` ist unverdrahtet.

## 2. Datenzugriff (DAL)

`Hsetu.Model.Dal.*` ist der größte Block: je Domäne ein Modul (`.Bim`, `.Tim`, `.Pim`,
`.Nim`, `.Prm`, `.Prj`, `.Geometry`, `.Resource`, …), jeweils mit `…Ado`-Variante für
SQL Server und `…SQLite`-Variante für die Projektdatei.

- Provider: `Hsetu.Model.Dal.Provider` (`.Ado`, `.SQLite`, `.SqlServer`, `.App.SQLite`, `.Json`, `.Xml`)
- Serializer-Familie: `TModelDatabaseSerializer`, `TModelDatabaseImportSerializer`,
  `TModelDatabaseUpdateSerializer`, `TModelDatabaseDeleteSerializer`,
  `TDalXMLSerializer`, `TPrmJSONPrmSerializer`, `TDalXMLGEOSerializer`
- Jede Modellklasse trägt eine `MetaClass` — darüber laufen Schema und Synchronisierung
  (`SyncMeta`; das `mod`-Feld der Datenbankzeilen entspricht der Assembly-Version, 6.6.8).

## 3. Gebäudemodell und Geometrie

`Hsetu.Model.Bim` (Wände, Fenster, Geschosse) und die Helfer in `Hsetu.FW.ModelHelper`:

- `TFWBIMHelper`, `TFWBuildingHelper`, `TFloorHelper`, `TRoomHelper`, `TZoneHelper`
- `TBuildingComponentHelper`, `TBuildingElementHelper`, `TBuildingElementReferenceHelper`,
  `TBuildingElementCladdingSurfaceHelper`
- Geometriekörper: `TRectangle`, `TTriangle`, `TTrapezoid`, `TCircleSegment`, `TCuboid`,
  `TTrianglePrism`, `TTrapezoidPrism`, `THippedRoofVolume`, `TOtherArea`, `TOtherVolume`
  — alle unter `TGeometryElement` / `TAreaElement` / `TVolumeElement`
- `TGeometryParser`, `TGeometrySerializer`, `TGeometryHelper`, `TCalculationRule`
- `TWalkThroughBuildingStructure` — Durchlauf über die Gebäudestruktur

**Wichtig:** ungültige Geometrieverweise verschwinden wortlos
(`if (FGEOHelper.IsValid) …`, sonst nichts). Der Prüfer selbst ist großzügig:
`FElement != null && IsNotEmpty(FRawData)`.

## 4. Bauteilkatalog

Die Antwort auf die offene Frage aus `hottgenroth-agent\docs\bauteile-uebernehmen.md`:
es gibt eine API, sie liegt in `Hsetu.ConstructionCatalog.BL`.

```csharp
// Hsetu.ConstructionCatalog.BL.Logic
public static class ConstructionCatalogLogic
    public static ObservableCollection<TBOConstructionElement> ListOfProjectConstructions
    public static void InsertNewConstruction()
    public static void AppendNewConstruction()
    public static void CopyConstruction()
    public static void PasteConstruction()
    public static void DeleteConstruction()
    public static int  DeleteAllConstructions()
    public static TBOConstructionElement CreateNewConstruction(int pSortNum, int pCatNr)
    public static TBOConstructionElement CreateNewConstructionElement(
        int pSortNum, int pCatNr, string pCatName,
        TTechDataBuildingElementType elementType,
        TTechDataBuildingElementUsageType usageType,
        TFWConstructionCatalogListType catType)
    public static void CreateListOfCatalogs()
    public static bool IsUserAllowedToPasteCopiedElement()
```

Daneben: `LayerConstructionLogic` (Schichten: `AppendLayerStructureSingleLayer`,
`InsertLayer`, `ReplaceLayer`, `DeleteLayer`, `SortInverse`, `FindOriginalLayer`),
`MaterialCatalogLogic` (`InsertNewMaterial`, `CopyMaterial`, `PasteMaterial`,
`AppendNewLayer`), `FrameGlazingCatalogLogic` (Fenster: Rahmen und Verglasung),
`ThermalBridgeLogic` (`CopyThermalBridge`, `PasteThermalBridge`).

Lesen ohne Oberfläche:

```csharp
// Hsetu.ConstructionCatalog.BL.Loading
public class LoadConstructionsFromSQL
    public void LoadListOfAllConstructionCatalogs(ObservableCollection<CatalogListElement> pList,
                                                  bool pGlazings = false, bool pFrames = false)
    public void LoadFormSQL(ObservableCollection<TBOConstructionElement> pListe,
                            TFWConstructionCatalogListType pListType, Guid pCatalogGuid)
public class LoadMaterialsFromSQL   // dito für TBOLayer
public class LoadThermalBridgesFromSQL
```

Zusätzlich `FindDefaultConstructionInProject`, `ImportAllplanCatalogData`,
`ImportBimScanCatalogData` (Fremdformate) und `RValueCalcAir` / `FastCalculation`
(U-Wert-Rechnung).

**Vorbehalt:** `ConstructionCatalogLogic` ist statisch und hält Zustand
(`ListOfProjectConstructions`, Zwischenablage für Copy/Paste). Die Klassen stammen aus
der Oberflächenschicht — über die Brücke aufrufbar, aber nicht als zustandsloser Dienst
gebaut. Der belastbarere Weg für Automatisierung führt über `LoadConstructionsFromSQL`
und die `TBO…`-Objekte.

## 5. Berechnung

| Modul | Typen | Inhalt |
|---|---:|---|
| `Hsetu.FW.Calculations` | 236 | Berechnungsrahmen |
| `Hsetu.FW.Calculations.CS` | 361 | Rechenschritte (Netze, Gas, Rohrleitungen) |
| `Hsetu.Sim.Core.PS` | 184 | Anlagensimulation |
| `Hsetu.Sim.Core.BS` | 77 | Gebäudesimulation |
| `Hsetu.Sim.Core.PV` | 69 | Photovoltaik |
| `Hsetu.Sim.Core.Solver` | 8 | Löser |

In `Hsetu.FW.ModelHelper` liegen die Rechenschritte als einzelne Klassen — ein
Schritt-für-Schritt-Muster, das dem der eigenen Step-Engine ähnelt:
`TCalcStepCheckAndAssignSelectedHeatload`, `TCalcStepCorrectRoomHeatload`,
`TCalcStepCheckProfileUsages`, `TCalcRoomCalculation`, `TCalcFloorAreasCalculator`,
`TCalcZoneAreasCalculator`, `TCalcCatalogBomCalculation` (Stückliste) mit rund zwanzig
`TCalcStepPlantBom…`-Erzeugern für Verteiler, Pumpen, Heizkörper, Ventile, Rohrnetz.

Abgedeckte Normen (nach Häufigkeit in Typnamen): **VDI 3805** (8.540 — Produktdaten),
**DIN 18599**, **DIN EN 12831** (Heizlast), **VDI 2078** / **VDI 6007** (Kühllast,
Raumtemperatur), **DIN 4701-10**, **GEG**, **DIN 277**, **DIN 1946**, **VDI 4100**
(Schallschutz), **VDI 4650** (Wärmepumpen), **EN 13501** (Brandschutz), **EN 267**.

## 6. Ausgabe, Katalogauswahl, Fachmodule

- **Druck:** `Hsetu.Reporting.*` (658 Typen), `Hsetu.Reporting.PrintComponents` mit
  `Execute()`-Einstiegen; 1.231 Typen tragen `Report` oder `Print` im Namen.
- **Produktauswahl:** `Hsetu.CatalogSelection` (+ `.HeatPumps`, `.InfraredHeaters`,
  `.Umi`, `.Wpf`) — Auswahl realer Fabrikate.
- **VDI-3805-Export:** `TModelCatalogVDI3805Part03/05/14/16/18/20/21/29/32/35/99Exporter`
  in `Hsetu.Model.Tim.VDI3805.Helper`.
- **Ökobilanz:** `Hsetu.EcoBilancing.*` (1.826 Typen), inkl. `DgnbExporter` nach Excel.
- **Wärmebrücken:** `Hsetu.ThermalBridges.*` (313 Typen, 18 Module).
- **Weitere:** `Hsetu.HeatPumpConsultant`, `Hsetu.Profiles` (Nutzungsprofile),
  `Hsetu.Hed`, `Hsetu.Assistant`, `Hsetu.Sim.CsvImporter`.

## 7. Rahmen und Einstiegspunkte

`Hsetu.FW.Core` trägt die Infrastruktur: `ServiceLocator`, `CommandManager`,
`I18NTranslator`, `AppEnvironment`, `DecimalSettingsState`. Fachlicher Zustand liegt in
`Hsetu.FW.BO` / `Hsetu.FW.BO.CS` als `…State`-Singletons.

**3.883 Typen** haben eine statische `Instance`-Eigenschaft, **128** eine öffentliche
parameterlose `Execute()` / `Run()` / `Start()`. Das sind die natürlichen Ansatzpunkte
für die Brücke — mit der Einschränkung aus Abschnitt 1: ein `Instance` heißt nicht, dass
das Objekt ohne Oberfläche brauchbar verdrahtet ist. Das zeigt sich erst im Versuch.

497 Typen tragen `Lic`/`License` im Namen. Ob die Assemblies beim schreibenden Zugriff
eine gültige Lizenz verlangen, ist weiterhin offen — Reflexion und Lesen laufen.

## Grenzen dieser Übersicht

- **Mechanisch erzeugt.** Typen und Signaturen stammen aus der Einrückungsstruktur der
  ILSpy-Ausgabe, nicht aus einem Parser. Für die Suche taugt das; eine Signatur, auf die
  es ankommt, vorher in `api\<Modul>.api.txt` gegenlesen.
- **Je Modulname eine Fassung.** Ausgewertet sind die 511 kanonischen Dateien. Weitere
  998 Bauvarianten desselben Namens liegen als `<Name>~<hash>.cs` daneben (andere
  Produkte, ältere Stände) und sind hier nicht erfasst.
- **Diese Übersicht beschreibt nur `eigen/`.** Die Fremdbibliotheken sind zwar
  indiziert (`api-fremd\`), aber nicht nach Aufgaben geordnet — dort hilft nur
  die gezielte Suche.
- **Der native Teil fehlt.** Die Oberfläche steckt in `Energie.exe` (289 MB) und 29
  weiteren nativen Dateien; ilspycmd richtet dort nichts aus.
- **Aufrufbar heißt nicht erprobt.** Verifiziert ist bisher allein der Weg aus
  Abschnitt 1. Alles andere ist gelesen, nicht ausgeführt.
