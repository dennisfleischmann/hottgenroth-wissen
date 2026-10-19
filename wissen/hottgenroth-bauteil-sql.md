---
name: hottgenroth-bauteil-sql
description: "Bauteile werden per direktem SQL-INSERT in die Hottgenroth-LocalDB erzeugt — funktioniert, Doku und Skripte im separaten bauteile/-Repo"
metadata: 
  node_type: memory
  type: project
  originSessionId: 34f48bce-04ca-4b23-b304-2aad3d1c1d6b
  modified: 2026-08-09T03:43:55.601Z
---

Bauteile (Wandaufbauten) werden programmatisch in der Hottgenroth-/ETU-Energieberatersoftware
angelegt, ohne die GUI — per direktem `INSERT` in die LocalDB-Instanz `(localdb)\HSETU`
(`HsetuPrjData` = Projekt-Bauteile, `HsetuUsrData` = "Meine Bauteile").

**Funktioniert und ist verifiziert** (06.08.2026, Bauteil `BEISPIEL-Aussenwand-WDVS-16cm`
im Projekt "Jan Malte Strackerjan_iSFP (1)" erschien nach Neustart korrekt im Katalog).

Das Schema ist undokumentiert und wurde per SQL-Trace reverse-engineered: Extended-Events-Session
mitlaufen lassen, Bauteil in der GUI anlegen, Statements + `SELECT *`-Snapshot abgreifen, nachbauen.
Derselbe Zyklus gilt für noch offene Bauteiltypen (Fenster, Dach) und für die Zuweisung ans
Gebäude (`TcElementReference`, `BmElement*`) — beides noch nicht analysiert.

Produktiv läuft das inzwischen über `hottgenroth-agent/` **im Haupt-Repo** (nicht in `bauteile/`):
Laravel stellt Aufgaben ein, ein Windows-Agent auf dem Arbeitsplatz führt sie gegen die lokale
LocalDB aus. Bausteine u. a. `bauteile.import` (Bauteil aus Schichtliste anlegen) und
`project.import` (.sqproj einspielen). Eigene ausführliche README dort.

Doku: `bauteile/docs/hottgenroth-bauteil-sql.md` (vollständig, mit Schnellstart).
Referenzskript: `bauteile/tools/insert-bauteil-strackerjan.sql` — für ein neues Bauteil nur
Projekt-GUID, Name und die Schichttabelle `@L` ändern, der Rest wird generiert.

Die Dumps/Exporte liegen **nicht im Repo**, sondern auf dem Desktop
(`C:\Users\fs-energieberater\Desktop\hottgenroth*.csv|txt`, `bauteil_trace_output.txt`) —
dort zuerst suchen, wenn Referenzdaten gebraucht werden. `bauteil_trace_output.txt` ist
die wichtigste Datei: der mitgeschnittene SQL-Verkehr der Software beim Anlegen eines Bauteils.

Seit der Dekompilierung (09.08.2026) gibt es eine Alternative zum SQL-Weg: die Software
hat eine eigene Katalog-API — siehe [[hsetu-bauteilkatalog-api]]. Der SQL-Weg bleibt
verifiziert und produktiv; die API ist gelesen, aber noch nicht erprobt.

Verortung: `bauteile/` ist ein **eigenes Git-Repo** (.NET-Revit-Add-in `FsGebaeudehuelle`)
innerhalb von `c:\Projekte_Dev\energieberatung\`, im Haupt-Repo nur untracked. Die
Hottgenroth-SQL-Sachen haben nichts mit dem Laravel-Teil des Energieberatung-Projekts zu tun.
