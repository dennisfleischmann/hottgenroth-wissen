---
name: hsetu-kontaktrollen-import
description: "Warum Projektadresse und Eigentuemer nach dem Bruecken-Import leer sind — zwei Verankerungen derselben Rolle, und welche Wege ausgeschlossen sind"
metadata: 
  node_type: memory
  type: project
  originSessionId: a986d25c-ab5b-450a-b3ef-f892cbe35bc9
  modified: 2026-08-09T20:33:18.997Z
---

Nach einem `.sqproj`-Import ueber die Bruecke sind in der Software die Reiter
**Projektadresse** und **Eigentuemer** leer, obwohl die Kontakte importiert sind.
Am 09.08.2026 vollstaendig geklaert, an Code und LocalDB gemessen.

**Die Ursache: dieselbe Rolle kann zweifach verankert sein.**

- Aus der `.sqproj` kommen Rollen, die am KONTAKT haengen:
  `CmContactRole.ReferenceFromUUID = CmContact.UUID`, `ContactGroupUUID` leer.
  Typen `croOwner(7)` und `croObject(10)`.
- Die Oberflaeche liest aber die Rollen der Projekt-KONTAKTGRUPPE:
  `CIM.ContactGroups.Locate(cgtProject).Roles.Locate(typ)` — `Hsetu.FW.Core.cs:19185`.
- Beim ERSTEN OEFFNEN legt `TFWCIMHelper.PrepareProjectCIM`
  (`Hsetu.FW.ModelHelper.cs:38043`) fuenf leere Gruppenrollen an: croDesigner(4),
  croBuilder(5), croPersonOfContact(6), croOwner(7), croObject(10). Die
  Oberflaeche liest genau diese leeren. Deshalb sieht es nach Datenverlust aus,
  obwohl nichts fehlt.

**Ausgeschlossene Wege — nicht erneut versuchen:**

1. Den vierten Konstruktorparameter von `TFWSQLiteProjectImporter` (globale
   Kontakte) setzen. Er ist der An/Aus-Schalter fuer `ConvertContacts`, aber der
   Konverter LOESCHT die projektlokalen Kontakte und legt sie nicht im zentralen
   Adressbuch an, solange `FAppCIM` nicht geladen ist. Zweimal gemessen, beide
   Male 0 Kontakte danach. `GetDalsAndProvider` kennt ausserdem nur `dctProject`
   und liefert fuer jeden anderen Typ null — der Provider muss ueber
   `TFWDesktopDatabaseSettingsRegistry.AppCimData` +
   `TFWDatabaseConfigHelper` + `TFWDesktopDalsAndProviderHelper.Build` gebaut
   werden.
2. `PostLoadAction` benutzen. Das `TModelProject` lebt nur innerhalb von
   `TFWProjectImporter.Execute()`, und die Bruecke kann keine Delegaten bauen.

**Der gangbare Weg** (verifiziert, noch nicht erprobt): ein zweiter Durchgang
nach dem Import, rein additiv. Vorbild ist die private Methode
`ProjectIntegratedCommands.AttachContact` (`Hsetu.FW.Core.cs:19174`):

    contact = new TModelContact(cim, cim)     // reiner Traeger, nicht einfuegen
    contact.Identifier = <CmContact.UUID>
    rolle = cim.ContactGroups.Locate(cgtProject).Roles.Locate(<typ>)
    rolle.Contact = contact
    rolle.MergeDALObject()

Beim Merge werden vom Traeger nur `Identifier` und `Name` gelesen
(`Hsetu.Model.Cim.cs:6617`). Voraussetzung: die Gruppenrolle existiert bereits,
das Projekt wurde also einmal geoeffnet. Existiert sie nicht, muss zusaetzlich
eine eigene `TFWContactFactory` verdrahtet werden — wie es fuer
`TFWPrmProjectFactory` schon geschieht.

Siehe [[hottgenroth-agent-testaufbau]] fuer das Ausfuehren einzelner
Bruecken-Auftraege ueber `hsetu-bridge.exe --job`.
