# IFC-Modell und Grundrisse aus einem Projekt

Ein Projekt liegt in der LocalDB eines Arbeitsplatzes. Der Server kann es nicht
lesen — er kann nur einen Auftrag stellen. Dieser Weg macht daraus Dateien, die
auf dem Server liegen und sich dort herunterladen lassen, auch wenn der
Arbeitsplatz längst aus ist.

```
Oberfläche  /admin/hottgenroth/exporte  →  Auftrag projekt.export
                                              │
Arbeitsplatz   Skripte holen  →  Export-Projekt.ps1  →  manifest.json
                                              │  http.upload (liest das Manifest)
Server         hottgenroth_exporte  +  <file_root>/exporte/<projekt-guid>/
                                              │
Oberfläche     Liste, Vorschau, Download
```

## Was entsteht

Je Lauf, abgelegt unter `art` in der Tabelle `hottgenroth_exporte`:

| art | Datei | Inhalt |
|---|---|---|
| `ifc` | `<Projekt>.ifc` | vollständiges Gebäude, IFC4 |
| `ifc-huelle` | `<Projekt>-nur-Huelle.ifc` | nur die thermische Hülle |
| `grundriss` | `<Projekt>-Grundriss-<Ebene>.dxf` | Geschossgrundriss, DXF R12 |
| `vorschau` | `<Projekt>-Grundriss-<Ebene>.png` | Bild desselben Grundrisses |
| `manifest` | `manifest.json` | was der Lauf gefunden hat |

Die Ebenen leitet `Export-Projekt.ps1` aus den Raumnamen und `BmElementStorey`
ab; geschnitten wird 1,00 m über der jeweiligen Rohdecke.

## Die Skripte kommen vom Server

`GET /api/hottgenroth/agent/files/skripte/<name>.ps1` liefert die Datei direkt
aus `hottgenroth-agent/tools/` im Repository. Der Auftrag holt sie bei jedem
Lauf frisch. Eine Korrektur am Exporter wirkt damit ab dem nächsten Deploy auf
allen Arbeitsplätzen, ohne den Agent neu auszurollen.

**Kein Veröffentlichungsschritt.** Es gab einmal einen (`hottgenroth:skripte`,
in `composer.json` unter `post-install-cmd` eingehängt). Er funktionierte, war
aber eine zweite Wahrheit: derselbe Inhalt an zwei Orten, verbunden durch einen
Schritt, der bei jedem Deploy laufen muss. Läuft er einmal nicht, ist das
ausgelieferte Skript still veraltet, und der Fehler zeigt sich erst im
erzeugten Grundriss — an einer Stelle, an der niemand die Ursache vermutet.

Aus dem Repository gelesen kann der ausgelieferte Stand vom ausgerollten nicht
mehr abweichen.

Was der Server ausliefert, lässt sich nachsehen:

```powershell
$k = @{ Authorization = "Bearer <HOTTGENROTH_AGENT_TOKEN>" }
Invoke-WebRequest "https://<app>/api/hottgenroth/agent/files/skripte/Export-Grundriss.ps1" -Headers $k
```

## Warum `http.upload` das Manifest selbst liest

Wie viele Grundrisse entstehen, hängt an der Zahl der Geschosse — die kennt der
Server beim Zusammenstellen des Auftrags nicht. Er kann also keine Kette von
Upload-Schritten vorbauen. Deshalb bekommt der Baustein den Pfad des Manifests
und lädt jede darin genannte Datei hoch:

```json
{ "use": "http.upload",
  "with": { "manifest": "…\\manifest.json", "projectGuid": "…", "projectName": "…" } }
```

Eine einzelne Datei geht weiterhin über `path` statt `manifest`.

Die Auftragsnummer muss dabei niemand mitgeben: der Baustein nimmt sie aus dem
Ausführungskontext (`StepContext.TaskId`). Ohne sie ließe sich später nicht mehr
sagen, aus welchem Lauf eine Datei stammt.

Ein PowerShell-Aufruf wäre hier der falsche Weg gewesen — `shell.run` sieht
weder Token noch Agent-Schlüssel, der Upload hätte 401 bekommen.

## Ablage in Produktion

`HOTTGENROTH_STORAGE_DISK=s3` setzen. Auf fortrabbits Platte wäre der Export
nach dem nächsten Deploy weg, und die Web-Knoten teilen sie ohnehin nicht.

## Nachprüfen

`Test-Ifc.ps1` liest ein erzeugtes IFC zurück und hält es gegen die Datenbank —
Bauteilzahl, Raumzahl, Nettofläche, Hüllfläche, Ausdehnung:

```powershell
.\tools\Test-Ifc.ps1 -ProjectGuid <GUID> -Ifc <pfad zur ifc>
```

Das prüft die Übereinstimmung mit den Daten, nicht die Schemakonformität. Für
die bräuchte es einen externen Validator (IfcOpenShell, buildingSMART).
