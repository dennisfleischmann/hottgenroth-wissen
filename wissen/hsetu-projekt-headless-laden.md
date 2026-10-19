---
name: hsetu-projekt-headless-laden
description: Ein HSETU-Projekt ohne Oberflaeche vollstaendig ins Objektmodell laden - der Weg ueber TFWProjectEnvironment
metadata: 
  node_type: memory
  type: reference
  originSessionId: da0215b4-d437-4ebb-9c3d-60a23ed95a70
  modified: 2026-08-16T07:33:16.925Z
---

**Der Schluessel heisst `TFWProjectEnvironment`.** Damit laesst sich ein Projekt
ohne laufende Oberflaeche vollstaendig ins Objektmodell laden — Gebaeude,
Geschosse, Raeume, Bauteile, Geometrie. Das ist die Grundlage fuer *jeden*
Aufruf der Hottgenroth-Rechenkerne von aussen, nicht nur fuer den
[[hottcad-eigener-ifc-export]].

Ablauf ueber die Bruecke (`hsetu-bridge.exe`), erprobt an zwei Projekten:

    1  new TFWDesktopDalHelper
         .GetDalsAndProvider(dctProject)  -> z
         z.DalDatabaseProvider.Open()
    2  TFWDalCoreListHelper.Instance
         .FillDalCoreListContainer / …Building / …Graphic / …Site  (je einzeln!)
    3  TFWDalDatabaseEnvironment.Instance.ProjectDatabase
         .DalCoreList = z.DalCoreList ; .DalDatabaseProvider = z.DalDatabaseProvider
    4  TFWProjectManager.Instance.ModelProjectFactory
         .GetModelProjectGroup() .Identifier = <PrProject.GroupUUID> .LoadDALObject()
         mgruppe.Projects.LoadDALObjects(true)      <- sonst Count = 0
         .GetCurrentModelProjectFromModelProjectGroup(mgruppe)  -> TModelProject
    5  new TFWProjectDomain                         (Hsetu.FW.ModelHelper.Environment.Core)
       new TFWProjectEnvironment(z, bereich)        (…Environment.Project)
         .Project = modell
         .Options.LoadBIM/LoadSIM/LoadGIM/LoadGeometry = true
         .Initialize(true)
    6  bereich.BIM / .SIM / .GIM  sind jetzt gefuellt

**Ohne Schritt 5 laedt jeder Ladeauftrag die ganze Datenbank.** Gemessen: 99
Gebaeude, 366 Geschosse, 1624 Raeume, 13.559 Bauteile statt 1/4/22/199. Die
Ladeaufgaben (`TFWBuildingLoaderTask` & Co.) kennen keinen Projektfilter — den
zieht erst die Projektumgebung ein. Wer sie umgeht, bekommt Folgefehler, die
nach etwas anderem aussehen (`ArgumentException: Ein Element mit dem gleichen
Schluessel wurde bereits hinzugefuegt`).

**Die einzige Kennung von aussen ist die Projekt-UUID.** Die Modellgruppe steht
als `PrProject.GroupUUID` daneben — nicht in `XmProjectGroup`, das ist die
Prm-Seite. Jede Gruppe enthaelt genau ein Projekt (geprueft ueber die ganze
Datenbank), die Auswahl ist also eindeutig. **Container-UUIDs braucht man
nicht**: die Umgebung baut BIM, SIM und GIM selbst auf.

**Container-Typen.** `PrXim.ContainerType` ist `TModelContainerType`, 0-basiert:
mxtNone 0, mxtPRJ 1, **mxtBIM 2**, mxtCIM 3, **mxtSIM 4**, mxtPDM 5, mxtTIM 6,
mxtPIM 7, mxtNIM 8, mxtEIM 9, mxtECM 10, mxtFIM 11, mxtGEO 12, mxtPRM 13,
mxtAIM 14, mxtDIM 15, mxtFMM 16, **mxtGIM 17**, mxtTSM 18, mxtLIM 19.

**Wo nachschlagen.** Der Schnittstellenindex je Baugruppe liegt als
`api/<Baugruppe>.api.txt` unter [[hsetu-dekompilierter-korpus]] — grep dort
statt im Quelltext, das ist Minuten schneller. **Der IFC-Exporter fehlt im
Korpus**, er wohnt in `Common Files\HSETU\HottCAD3D`.

Der Weg ist **rein lesend** (nachgemessen: Bauteilzahl und Huellflaeche
unveraendert). Vgl. [[wirkungsprobe-statt-selbstpruefung]].
