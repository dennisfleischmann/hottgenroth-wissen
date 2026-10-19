---
name: projektexport-api
description: Ein Projekt als .sqproj aus der LocalDB exportieren — TFWMgrProjectExport.Export ist ein Einzeiler; die Desktop-Variante ist eine Falle
metadata: 
  node_type: memory
  type: reference
  originSessionId: fdf1bab8-40f6-4105-b941-4da9f0cf12f2
  modified: 2026-10-01T15:46:37.021Z
---

Ein Projekt von außen als `.sqproj` herausschreiben geht über **einen** Aufruf
(`Hsetu.FW.Manager.ImExport.TFWMgrProjectExport`):

```csharp
new TFWSQLiteProjectExporter(prmProject,
    TFWDalDatabaseEnvironment.Instance.ProjectDatabase, dateiname).Execute();
```

Die Quellseite ist also **nicht** selbst zu bauen — sie ist das Singleton
`TFWDalDatabaseEnvironment.Instance.ProjectDatabase`. Damit ist der Export eine
Nutzlast für die Brücke (`hottgenroth-agent/bridge`), kein neues Programm:
`new` / `call` / `$ref` reichen. Siehe [[auftraege-mit-shell-run]].

**Zwei Fallen.**

`TFWDesktopSQLiteProjectExporter` sieht nach dem fertigen Weg aus und ist keiner:
sein `Execute()` ist **leer**. Die Arbeit steckt in `BuildPrmAndPrj()`, das nur
ein Objektmodell im Speicher aufbaut und keine Datei schreibt. Die Klasse ist ein
Baustein, kein Einstiegspunkt.

Der Weg über `TFWMgrMaster.Initialize()` ruft nach dem Setzen von
`ProjectDatabase` ein `UpgradeSchema()` — das **schreibt** in die
Projektdatenbank. Wer an einem Rettungsstand arbeitet, darf da nicht durch,
sondern baut die Quellseite wie `TFWDesktopSQLiteProjectImExporter.BuildDalsAndProvider()`:
`TFWDatabaseConfigHelper(TFWDatabaseSettings.Settings.ProjectData).BuildDalDatabaseProviderParam()`
→ `TFWDesktopDalsAndProviderHelper().Build(param, dctProject)` → `.Open()`.

Nicht verwechseln mit dem Import: der ist **kein** Kopiervorgang, siehe
`hottgenroth-agent/bridge/README.md`. Und `Energie.exe` kann das nicht —
[[energie-exe-aufrufparameter]].
