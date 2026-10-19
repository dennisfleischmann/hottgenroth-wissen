# Modulkatalog — was jede Bibliothek tut

Stand 09.08.2026. Grundlage: die 511 kanonischen Module in `eigen/`, ausgewertet mit
`werkzeuge\steckbriefe.ps1`.

Die vollständige Liste **aller** Module mit Zahlen steht in
[`MODULE-ALLE.md`](MODULE-ALLE.md) — maschinell erzeugt, ohne Ausnahme. Hier stehen
die Beschreibungen.

## Woher die Angaben stammen

Drei Quellen, absichtlich unterscheidbar gehalten:

| Kennzeichnung | Herkunft | Verlässlichkeit |
|---|---|---|
| „Selbstauskunft" | `AssemblyDescription` der DLL | Hottgenroths eigener Text — 113 von 511 Modulen haben einen |
| Zahlen | gezählt aus `api-typen.csv` / `api-mitglieder.csv` | exakt, aber mechanisch: was ILSpy als `public` ausgibt |
| Fließtext ohne Quellenangabe | gelesen im dekompilierten Code | geprüft, aber nicht ausgeführt |

Wo ich ein Modul **nicht** gelesen habe, steht das da. Ein erfundener Zweck wäre
schlimmer als eine Lücke: er sieht aus wie Wissen.

---

## 1. Wie die Software gebaut ist

Drei Bauweisen liegen übereinander, und man sieht ihnen das Alter an.

**Der Kern ist Delphi, nach .NET übersetzt.** 31 Module tragen den Typ
`public static class __Global` — den Abdruck einer Delphi-Unit, deren globale
Prozeduren beim Cross-Compile zu einer Klasse werden. Es sind genau die untersten
Schichten: `Hsetu.Model.Core`, `.Xim`, `.Tim`, `.Bim`, `.Prm`, `.Pdm`, `.Geometry`,
`.Lib`, die Provider, dazu `Hsetu.FW.BO`, `.Calculations`, `.ModelHelper`,
`.Standard`, `Hsetu.Print*` und `Hsetu.Sim.Core*`. Daran erkennt man auch die
Typnamen wieder: `TDal…`, `TModel…`, `TFW…`, das führende `T` ist Delphi-Konvention.

**Daneben steht ein C#-Neubau.** Module mit dem Zusatz `.CS` — `Hsetu.FW.BO.CS`,
`.Calculations.CS`, `.ModelHelper.CS`, `.Mapper.CS`, `.Results.CS`, `.Standard.CS` —
enthalten **kein** `__Global`. Sie sind von Hand in C# geschrieben und liegen neben
dem cross-kompilierten Original gleichen Namens. Wer eine Funktion sucht, findet sie
deshalb womöglich zweimal, in zwei Fassungen unterschiedlichen Alters.

**Obendrauf WPF mit Prism.** Alles mit `.View`, `.ViewModel`, `.Module`, `.BL`
gehört zur Oberflächenschicht: MEF/Prism-Module, DevExpress-Steuerelemente,
MVVM. Die eigentliche Oberfläche der Anwendung steckt allerdings im **nativen**
`Energie.exe` — was hier an WPF liegt, sind die neueren, zugekauften oder neu
gebauten Teilfenster.

**Zwei Zeitalter in den DAL-Versionen.** Die Selbstauskünfte nennen eine
DAL-Version: die meisten Datenzugriffsmodule stehen auf **17.3**, `Lim` und `Tsm`
(Lizenz und Ticketsystem) auf **12.9**. Die Assembly-Version ist durchgängig
`6.6.8.301`; `Hsetu.Print.Interface` fällt mit `5.12.1.301` heraus.

### Die Schichtung

Woraus sie sich ergibt: wie oft ein Modul von anderen per `using` eingebunden wird.

| Modul | wird von … Modulen genutzt | Rolle |
|---|---:|---|
| `Hsetu.Model.Core` | 195 | das Fundament — DAL-Basisklassen, Meta, Schema |
| `Hsetu.Model.Prj` | 118 | Projektdaten |
| `Hsetu.Model.Tim` | 80 | Katalog- und Produktdaten |
| `Hsetu.FW.ModelHelper` | 74 | Fachliche Helfer über dem Modell |
| `Hsetu.Model.Bim` | 74 | Gebäudemodell |
| `Hsetu.FW.Core` | 68 | Anwendungsrahmen |
| `Hsetu.Model.Lib` | 59 | Basisbibliothek (Streams, Hashes, Krypto) |
| `Hsetu.FW.Standard` | 50 | Standardwerte, Konstanten |
| `Hsetu.WPF.Core` | 49 | Styles und Steuerelemente |
| `Hsetu.Model.Sim` | 48 | Standortdaten |

Praktische Folge: wer `Hsetu.Model.Core` lädt, lädt fast nichts mit; wer ein
`.ViewModel`-Modul lädt, zieht die halbe Anwendung nach. Für Zugriffe über die
Brücke ist die untere Hälfte der Tabelle die interessante.

---

## 2. Die Namenssystematik

Ohne sie ist der Bestand nicht lesbar. Drei Muster:

**Drei-Buchstaben-Modelle.** Jede Fachdomäne hat ein eigenes Modell-Modul
`Hsetu.Model.<XXX>` und dazu Datenzugriffsmodule `Hsetu.Model.Dal.<XXX>.<Provider>`.
Die Kürzel sind nirgends erklärt; die folgende Zuordnung ist aus den enthaltenen
Klassen erschlossen und über die Selbstauskünfte gegengeprüft:

| Kürzel | Bedeutung (erschlossen) | Belegende Klassen |
|---|---|---|
| **BIM** | Gebäude | `TDalBuildingData`, `TDalBuildingBIMData` |
| **TIM** | Katalog- und Produktdaten — hier liegen die **Bauteile** | `TDalCatalogData`, `TDalCatalogAccessoryBasisData`; DB-Tabellen `Tc…` |
| **PIM** | Anlagentechnik (Wärmeerzeuger, BHKW, Wärmepumpe) | `TDalAirSourceData`, `TDalBlockTypeThermalPowerStationData` |
| **NIM** | Netze (Rohr-, Abgas-, Luftnetze) | `TDalChimneyNetData`, `TDalChimneyNetDraftRegulatorData` |
| **EIM** | Elektro (Speicher, Leitungen, Verbraucher) | `TDalBatteryStorageData`, `TDalElectricalCableData` |
| **CIM** | Kontakte und Adressen | `TDalAddressData`, `TDalContactData`, `TDalBankAccountData` |
| **SIM** | Standort (Kataster, Ort, Klima-Bezug) | `TDalCadasterData`, `TDalCityData`, `TDalContinentData` |
| **FIM** | Kaufmännisches, Termine, Vorgänge | `TDalFinancialData`, `TDalFinancialAppointmentData` |
| **ECM** | Wirtschaftlichkeitsberechnung | `TDalEconomicCalculationData`, `TDalEconomicComponentData` |
| **FMM** | Anlagen/Betriebsmittel (Facility) | `TDalFacilityData`, `TDalFacilityElementData` |
| **GIM** | Grafik und Schemata (Modul `Model.Graphic`) | `TDalGraphicComponentData`, `TDalGraphicGIMData` |
| **PDM** | Nutzungs- und Lastprofile | `TDalProfileData`, `TDalProfileBatteryStorageData` |
| **PRM** | Projektverwaltung (Container, Gruppen) | `TDalPrmComponentData`, `TDalPrmReportData` |
| **PRJ** | Projektinhalte | `TDalProjectData`, `TDalProjectGroupData`, `TDalProjectJournalData` |
| **LIM** | Lizenzen | `TDalLicenseUserDataSetMapper`, `TModelLicense` |
| **TSM** | Ticketsystem | `TDalTicketSystemTSMDataSetMapper`, `TModelTicket` |
| **XIM** | die Klammer über allem — Verweise zwischen Domänen | `TModelComponentCatalogReference`, `TModelGEOReferenceHelper` |

**Provider-Endungen.** `Hsetu.Model.Dal.<XXX>.Ado` spricht SQL Server (die
LocalDB der Arbeitsplätze), `.Xml` liest und schreibt XML, `.SQLite` bedient die
`.sqproj`-Dateien. Dieselben Daten, drei Wege — deshalb ist ein Projektexport eine
`.sqproj` und der Projektbestand eine SQL-Server-Datenbank.

**`.CS`** heißt: C#-Neubau neben dem cross-kompilierten Delphi-Modul gleichen
Namens (siehe oben). **`.Interfaces` / `.Abstractions`** sind reine
Vertragsmodule ohne Logik. **`.BL`** ist Geschäftslogik, **`.AL`** Anwendungslogik.

---

## 3. Die Familien im Einzelnen

### Hsetu.Model — das Datenmodell (63 Module, 17.967 Typen)

Die größte Familie und die unterste Schicht. Aufbau je Domäne immer gleich: ein
Modell-Modul mit den Objekten, ein oder mehrere DAL-Module je Speicherform.

Die tragenden Stücke:

- **`Hsetu.Model.Core`** (1.487 Typen, *„Allgemeine Modell-Klassen / DAL-Klassen"*) —
  das Fundament. Enthält die Basisklassen des Datenzugriffs (`Hsetu.Model.Dal.Core`),
  die Metabeschreibung (`.Dal.Meta`), das Schema (`.Dal.Schema`), Import-Grundlagen
  (`.Dal.Import`), Konfiguration (`.Dal.Config`), Protokollierung
  (`Hsetu.Model.Logging`) und die Rechenkern-Basis (`Hsetu.Model.Calc.Core`).
  Jede Modellklasse der Software trägt eine `MetaClass` — von hier.
- **`Hsetu.Model.Xim`** (3.425 Typen, 17,8 MB — das größte Einzelmodul) — die
  Verweisschicht zwischen den Domänen. Hier liegen die Katalogverweise
  (`TModelComponentCatalogReference`, `TModelBuildingElementCatalogReference`) und
  `TModelGEOReferenceHelper`, über den Geometrie an Bauteile gebunden wird. Deckt
  außerdem `Dal.Dim` (Textbausteine, Kategorien, Medien), `Dal.Mim` (Medien,
  PropertySets, technische Daten) und `Dal.PropertySets` ab.
- **`Hsetu.Model.Tim`** (3.452 Typen, 12,7 MB) — Katalog- und Produktdaten mit
  Untergliederung nach `Building`, `Plant`, `Control`, `Electrical`, `Economic`,
  `Facility`, `Mounting`, `EPD`, `I18N`. **Für uns das wichtigste Modell**: die
  Bauteile eines Projekts sind TIM-Katalogeinträge (`TcBasis`,
  `TcBuildingElementDimension`, `…Layer`, `…LayerSection`).
- **`Hsetu.Model.Bim`** (489 Typen) — Gebäude: Wände, Fenster, Geschosse,
  `BmElement`. Mit `Bim.Template` (Vorlagen) und `Bim.Helpers`.
- **`Hsetu.Model.Prm` / `.Prj`** — Projektverwaltung und Projektinhalt. `Prm` liefert
  `TPrmProject`, `TPrmProjectGroup` und die Fabriken, über die der Import läuft;
  `Prj` die Projektdaten samt Journal.
- **`Hsetu.Model.Tim.VDI3805`** (632 Typen) und **`.VDI3805.Helper`** — Produktdaten
  nach VDI 3805, dem Austauschstandard der TGA-Branche. Der Grund, warum „VDI3805"
  mit 8.540 Treffern das häufigste Normkürzel im ganzen Bestand ist.
- **`Hsetu.Model.Geometry`** (*„Allgemeine Geometrieklassen"*) und
  **`Hsetu.Model.Dal.Geometry.Ado`** — Geometrie und ihre Ablage; hier sitzt die
  Serialisierung, an der ungültige Verweise wortlos verschwinden.
- **`Hsetu.Model.Lib`** (*„Bibliothek Modellklassen"*) — die Grundschicht darunter:
  `TMemoryStream`, `TLibMD5`, `TLibRC4`, Hash- und Krypto-Konstanten. Delphi-Erbe in
  Reinform.
- **`Hsetu.Model.Dal.Provider*`** — die Provider: `.Ado`, `.SqlServer`, `.SQLite`,
  `.App.SQLite`, `.Xml`, `.Json`, `.Config`. Hier liegen `TModelDatabaseImporter`,
  `TModelDatabaseExporter` und die Serializer-Familie.
- **`Hsetu.Model.Dal.Resource`** (*„Schemabeschreibungen DAL-Zugriffschicht"*,
  15 MB) — die Schemabeschreibungen selbst, größtenteils generierte Tabellen.

Die übrigen Model-Module folgen dem Schema aus Abschnitt 2 und stehen vollständig in
[`MODULE-ALLE.md`](MODULE-ALLE.md).

### Hsetu.FW — das Rahmenwerk (23 Module, 3.628 Typen)

*Selbstauskunft durchgängig: „HSETU Framework".* Die Schicht zwischen Datenmodell
und Anwendung.

- **`Hsetu.FW.ModelHelper`** (633 Typen) — das fachliche Arbeitspferd. Gegliedert in
  `Building` (Gebäudehelfer), `Calculation` mit den Unterbereichen `Building`,
  `Catalog`, `Heatload`, `Plant`, dazu `Catalog`, `Project`, `Dal`, `Converter`,
  `Utils`. Hier stehen `TFWProjectImporter`/`TFWProjectExporter`,
  `TFWDalImporter`/`TFWDalExporter`, die Geometriekörper (`TRectangle`, `TCuboid`,
  `THippedRoofVolume` …), `TGeometryParser`/`TGeometrySerializer`, die Raum- und
  Zonenhelfer (`TRoomHelper`, `TZoneHelper`, `TFloorHelper`) und rund achtzig
  `TCalcStep…`-Klassen für Heizlast und Stücklisten.
- **`Hsetu.FW.ModelHelper.SQLite`** — `.sqproj` lesen und schreiben:
  `TFWSQLiteProjectImporter` / `…Exporter`, `TFWSQLiteDalProviderHelper`.
- **`Hsetu.FW.ModelHelper.Desktop`** — dieselben Aufgaben mit den Einstellungen des
  Arbeitsplatzes: `TFWDesktopDalHelper` (Zieldatenbank aus der Registry),
  `TFWDesktopSQLiteProjectImporter`.
- **`Hsetu.FW.Core`** (585 Typen) — Anwendungsrahmen: `ServiceLocator`,
  `CommandManager`, `I18NTranslator`, `AppEnvironment`, dazu Assistenten (`Wizard`),
  Baumstrukturen (`Tree`), Zustände (`States`), Textbausteine
  (`Services.TextModulesModule`), Wärmebrückendienste und der Startbildschirm.
  Enthält außerdem `PrmProjectCopyHelper` und `DuplicateModelProjectCommand`.
- **`Hsetu.FW.BO`** / **`.BO.CS`** (310 / 374 Typen) — die Geschäftsobjekte, die die
  Oberfläche bewegt: Katalog, Anlage, Netz, Elektro, Wirtschaftlichkeit, Grafik-
  Schemata, dazu die `…State`-Singletons, in denen der Bearbeitungszustand hängt.
- **`Hsetu.FW.Calculations`** / **`.CS`** (236 / 361 Typen) — die Rechenverfahren.
  Der C#-Teil ist nach Themen gegliedert: `ConstructionCatalog.UValue` und
  `.Diffusion` (U-Wert, Tauwasser), `Building`, `Economic` (Wirtschaftlichkeit mit
  eigenen Schritt-, Rechner- und Optionsklassen), `HeatPump` (mit
  Referenztabellen und Validierung), `Net.Gas` (Gasnetz mit Navigator, Visitor und
  Tabellen), `Ventilation` und `DIN1946BB3` (Lüftungskonzept), `Vdi3781`,
  `AirCompound`, `NonResidentialVentilation`, `ElectricPlant`.
- **`Hsetu.FW.Mapper`** / **`.CS`**, **`Hsetu.FW.Results`** / **`.CS`**,
  **`Hsetu.FW.Standard`** / **`.CS`** — Abbildung zwischen Modell und Geschäftsobjekt,
  Ergebnisstrukturen, Standardwerte. Jeweils Delphi-Original plus C#-Neubau.
- **`Hsetu.FW.Application.Mef`**, **`.Manager`**, **`.Services`**,
  **`.Abstractions`**, **`.IPC`**, **`.Logging.Sinks`**, **`.BO.Sync`**,
  **`.Core.Gui`** — Zusammenbau der Anwendung, Prozesskommunikation, Protokollziele,
  Synchronisierung.

### Hsetu.Sim — Simulation (184 Module, 2.161 Typen)

Die zahlreichste, aber nicht die größte Familie: sehr viele sehr kleine Module, weil
jede Teilfunktion eigene `.Interfaces`-, `.ViewModels`- und `.Module`-Assemblies
bekommt. Der Rechenkern steckt in wenigen:

- **`Hsetu.Sim.Core`** und **`.Core.PS`** (184 Typen, Anlagensimulation),
  **`.Core.BS`** (Gebäudesimulation), **`.Core.PV`** (Photovoltaik),
  **`.Core.Solver`**, **`.Core.CoupledSimulation`**, **`.Core.Climate`**,
  **`.Core.ElectricCar`** — alle cross-kompiliert.
- **`Hsetu.Sim.MathUtils`**, **`.Climate.Epw`** (Wetterdaten im EPW-Format),
  **`.CsvImporter`**, **`.Variants`**, **`.Experiments`**, **`.EconomicEfficiency`**,
  **`.Printing`** — Werkzeuge drumherum.

Die restlichen ~160 sind Oberflächen- und Vertragsmodule je Teilfunktion. Ich habe
sie nicht einzeln gelesen; ihre Zahlen stehen in [`MODULE-ALLE.md`](MODULE-ALLE.md).

### Hsetu.EcoBilancing — Ökobilanz (63 Module, 1.826 Typen)

Lebenszyklusanalyse und DGNB-Zertifizierung, sauber geschichtet:
`LCA.BL` / `.BL.Interfaces` (Geschäftslogik, 338 Typen allein in den Verträgen),
`LCA.ViewModel` / `.Interfaces`, `Views`, `PrintModule.*` (eigenes Druckmodul mit
Excel-Ausgabe, `DgnbExporter`), `Module`. Auch hier: viele kleine Module, ein großer
Kern.

### Hsetu.Cad und Hstac — Zeichnung und Geometrie (11 + 12 Module)

- **`Hsetu.Cad.Core`** (141 Typen) — CAD-Kern mit Berechnungs-Zwischenspeicher
  (`CalculationCache`), `MGraphSerializer`.
- **`Hsetu.Cad.Heating`** (5 MB) und **`Hsetu.Cad.Water`** (3 MB) — Heizungs- und
  Sanitärzeichnung.
- **`Hsetu.Cad.Persistence`** — CAD-Dokument als Strom, binär oder XML.
- **`Hstac.*`** — eine Familie mit durchgängig **deutschen** Namensräumen und damit
  erkennbar anderer Herkunft: `Asp.Base` (*„Stellt die grundlegenden Mechanismen der
  Asp-Struktur zur Verfügung"*), `Asp.Geometry`, `Asp.Strichplaninterpretation`,
  `Asp.Tesselierung`, `Asp.Volumenbausteine`, `Geometry.Base`, `Maths`,
  `Persistierung`, `Logging`, `GemeinsameSchicht.*`. Das ist die Geometrie-Maschine
  hinter HottCAD: Strichpläne deuten, Volumen bilden, tesselieren.

### Bauteilkatalog und Produktauswahl

- **`Hsetu.ConstructionCatalog.BL`** (46 Typen) — die API für Bauteile:
  `ConstructionCatalogLogic`, `LayerConstructionLogic`, `MaterialCatalogLogic`,
  `FrameGlazingCatalogLogic`, `ThermalBridgeLogic`, dazu
  `LoadConstructionsFromSQL` / `LoadMaterialsFromSQL` / `LoadThermalBridgesFromSQL`
  und die Fremdformat-Importe `ImportAllplanCatalogData`, `ImportBimScanCatalogData`.
  Ausführlich in [`API-UEBERSICHT.md`](API-UEBERSICHT.md#4-bauteilkatalog).
- **`.View`, `.ViewModel`, `.ImageGenerator`** — Oberfläche und Bilderzeugung dazu.
- **`Hsetu.CatalogSelection`** (+ `.Wpf` mit 434 Typen, `.HeatPumps`,
  `.InfraredHeaters`, `.Umi`) — Auswahl realer Fabrikate aus den Produktkatalogen.
- **`Hsetu.LayerViewer.*`** (`Asp`, `AspViewer.Wpf`, `GraphicEngine`, `Interfaces`) —
  Darstellung von Schichtaufbauten. Trägt dieselbe „Asp"-Struktur im Namen wie
  `Hstac.Asp.*` und gehört damit zur Geometrieseite, nicht zum Katalog.

### Berechnung außerhalb des Rahmenwerks

- **`Hsetu.EbCalc.IbpKernel`** — *„Nutzt den Kernel des IBP um die DIN18599
  Berechnung auszuführen."* Bemerkenswert: die **DIN-18599-Bilanz rechnet nicht
  Hottgenroth selbst**, sondern ein zugekaufter Kern des Fraunhofer-Instituts für
  Bauphysik. **`Hsetu.EbCalc.Results.IbpKernel`** hält dessen Ergebnisklassen.
  Es ist das **einzige** der 511 Module, das `DIN18599DataModel` einbindet — und es
  liest nur: Blob aus `PrMedia` holen, deserialisieren, rechnen. Wo die
  Anlagentechnik dieser Rechnung liegt und wie man sie setzt, steht in
  [`DIN18599-ANLAGENTECHNIK.md`](DIN18599-ANLAGENTECHNIK.md).
- **`Hsetu.ThermalBridges.*`** (18 Module, 313 Typen) — Wärmebrücken: Katalog,
  Berechnung, Darstellung.
- **`Hsetu.Profiles.*`** (4 Module) — Nutzungsprofile über `Model.Pdm`.
- **`Hsetu.HeatPumpConsultant.*`** (6) und **`Hsetu.HeatPumpCheck.*`** (5) —
  Wärmepumpen-Beratung und -Eignungsprüfung.
- **`Hsetu.Optimus.*`** (5) — Sanierungsoptimierung: `Calculations.BuildingElements`
  mit `Calc`, `Steps` und `Strategies`, dazu `Typology`. Sucht Maßnahmenkombinationen.
- **`Hsetu.Hed`** (426 Typen) — Heizungsauslegung als Oberflächenmodul:
  Heizkörperauswahl und -bemessung (`RadiatorDimensionSelectViewModel`,
  `RadiatorDetailViewModel`), Flächenheizkreise (`CircuitAreaListViewModel`),
  Heizlast (`Hed.Calculation.Heatload`), Katalogzugriff.

### Ausgabe und Druck

- **`Hsetu.Print`** (*„Schicht mit allgemeinen Druckfunktionen"*),
  **`Hsetu.Print.Interface`** (*„Cross compilierte Druckschnittstelle zur Verwendung
  des Report-Druckmoduls und des Formular-Druckmoduls"*), **`Hsetu.Print.RichView`**
  (*„Diese Schicht verwendet per PInvoke RichView als Reportausdruckgenerator"* —
  also eine native Delphi-Komponente über P/Invoke).
- **`Hsetu.Reporting.PrintComponents`** (452 Typen) — die Berichtsbausteine:
  `Base` mit Einstellungen und Bilderzeugung, `Building.Components`, Wrapper für
  Heizlastdaten.
- **`Hsetu.Modules.Report`** — Berichtsmodul der Anwendung.

### Anwendungsmodule (Prism/MEF)

`Hsetu.Modules.*` (9): **`Bom`** (Stückliste, mit Anbindung an *LeanConnect* und
*Kaufmann* — zwei Fremdsysteme mit eigenen Endpunkten), **`Contact`**, **`Media`**,
**`Location`** (+ `.Abstractions`), **`GeometryWizard`**, **`CadRemote`**,
**`Chatbot`**, **`Report`**.

`Hsetu.EnergyConsultant.*` (9) — der Energieberater-Teil selbst: `Core`,
`Application`, `Abstractions`, `Module`, **`BEG`** mit `DataAccess.XML` und
`Printing` (Bundesförderung für effiziente Gebäude), `Printing.Module`,
`CatalogSelection.Module`.

`Hsetu.Assistant.*` (6) — *„Erfassungs-Assistenten für die schnelle und bequeme
Erfassung tabellarischer Gebäude"*: `Application`, `Domain`, `Infrastructure`,
`Framework.Module`.

Dazu einzeln: `Hsetu.BuildingModule.View` / `.ViewModel` (566 / 585 Typen — die
Gebäudeeingabe), `Hsetu.ElectricalModule.*` (6), `Hsetu.EEBerater.Module`,
`Hsetu.Heating.Module`, `Hsetu.EbSim.Remote*` (3, Fernsteuerung der Simulation).

### Lizenz, Aktualisierung, Betrieb

- **`Hsetu.License.*`** (7): `Abstractions`, `Client`, `Client.Desktop`,
  `Workflow.Desktop` und drei Provider — **`Dongle`** (Hardwareschlüssel),
  **`HottgenrothId`** (Konto), **`Local`**. Das eigentliche Prüfmodul
  (`Hsetu.LicClient64.dll`) ist **nativ** und liegt nicht dekompiliert vor.
- **`Hsetu.Update.*`** (4), **`Hsetu.SystemCheck.*`** (3), **`Hsetu.Admin.*`** (4),
  **`Hsetu.Services`**, **`Hsetu.Microservices`**, **`HsetuServicesDataMigrator*`**,
  **`HsetuAppDatabaseUpdate`**.
- **`Hsetu.Http.Proxy`** (*„Schnittstelle zum Auslesen und Speichern von
  Proxy-Einstellungen"*), **`Hsetu.LoginControl.OAuth`** (*„HSETU OAuth2 CLient"*),
  **`Hsetu.Azure.CredentialsProvider.Client`** (*„A packagee to retrieve JSM
  Tokens"* — Jira Service Management), **`Hsetu.ApiClients.Abstractions`**.

### Hilfe, Chat, Sonstiges

**`Hsetu.Helpdesk.Desktop.UI`**, **`Hsetu.HelpdeskShared.*`** (6, darunter ein
RTF- und ein ADF-Parser — *Atlassian Document Format*, passend zum Jira-Bezug oben),
**`HSETUHilfecenter`** (198 Typen), **`Hsetu.HottBot.Client`** (*„A package for using
HottBot Api"*), **`Hsetu.Chatbot.Wpf`**, **`Hsetu.MediaViewer`**,
**`Hsetu.RemoteControl`**, **`Hsetu.WebComponents.*`** (3, *„Base web component"*,
darunter ein `HttpServer`), **`Hsetu.Prism.*`** (3), **`Hsetu.WPF.Core`**
(*„Styles, Controls und Hilfsklassen für WPF-Anwendungen"*), **`Hsetu.Afx*`**,
**`Hsetu.Resources.Images` / `.Videos`** (*„Statische Bild-/Videoressourcen"*).

---

## 4. Die Fremdbibliotheken

584 Module, 68.957 Typen, 612.875 Mitglieder — mehr als die Fachlogik. Sie einzeln zu
beschreiben wäre verschwendete Mühe: es sind zugekaufte Standardbibliotheken, für die
es Herstellerdokumentation gibt. Die Gruppen:

| Gruppe | wofür | Umfang |
|---|---|---|
| **DevExpress** (v17.2 u. a.) | die gesamte Oberfläche: Raster, Diagramme, Ribbon, RichEdit, Berichtswesen, Scheduler | mit Abstand der größte Block |
| **Microsoft/.NET-Erweiterungen** | Roslyn (`Microsoft.CodeAnalysis`), Entity Framework, `Microsoft.Data.SqlClient`, Identity/MSAL | |
| **Prism / MEF** | Modulare Anwendungsstruktur | |
| **Log4Net, Newtonsoft.Json, RestSharp, UnitsNet** | Protokollierung, JSON, HTTP, Einheiten | |
| **SQLite** | `.sqproj`-Dateien | |

Durchsuchbar über `api-fremd\<Modul>.api.txt`, `api-typen-fremd.csv` und
`api-mitglieder-fremd.csv`.

---

## 5. Grenzen dieser Dokumentation

- **Gelesen, nicht ausgeführt.** Außer dem Projektimport
  ([`API-UEBERSICHT.md`](API-UEBERSICHT.md#1-projekte-importieren-exportieren-kopieren))
  ist kein hier beschriebener Aufruf erprobt.
- **Nicht jedes Modul ist gelesen.** Beschrieben sind die tragenden und die fachlich
  interessanten. Die rund 250 Oberflächen- und Vertragsmodule aus `Hsetu.Sim.*` und
  `Hsetu.EcoBilancing.*` sind gezählt, nicht gelesen; das steht an der jeweiligen
  Stelle.
- **Die Kürzel sind erschlossen.** Die Zuordnung in Abschnitt 2 stammt aus den
  enthaltenen Klassen, nicht aus einer Quelle von Hottgenroth. Sie ist belegt, aber
  nicht amtlich.
- **Je Modulname eine Fassung.** Die 998 abweichenden Baustände aus anderen
  Produkten sind dekompiliert (`index.csv`), aber weder indiziert noch beschrieben.
- **Der native Teil fehlt vollständig.** `Energie.exe` (289 MB), das Lizenzmodul,
  die Druck- und Grafikbibliotheken — 6.494 Dateien, für die ilspycmd nichts
  ausrichtet.
