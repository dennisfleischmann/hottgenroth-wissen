---
name: projekt-aus-vorlage-importieren
description: "Ein neues Hottgenroth-Projekt entsteht aus bauteile/vorlagen/Vorlage-Leeres-Projekt.sqproj — Name VOR dem Import in der Datei setzen, Brücke lokal aufrufen"
metadata: 
  node_type: memory
  type: project
  originSessionId: 362c3451-a7e4-47c0-8bf2-9b304d829d3a
  modified: 2026-08-23T20:21:21.993Z
---

Ein neues Projekt von außen anzulegen ist erprobt — der Weg geht über die
**Vorlage**, nicht über `PrProject`-INSERTs. Damit ist die alte Einschränkung
aus [[asana-auftrag-kubatur]] („Projekthülle entsteht in der Oberfläche")
gegenstandslos.

**Der Ablauf, am 23.08.2026 an XWSKQ_Holger Hoffmann gelaufen:**

1. `bauteile/vorlagen/Vorlage-Leeres-Projekt.sqproj` kopieren (7,7 MB, SQLite;
   enthält 2 Geschosse, 12 Bauteile, Satteldach — eine bewohnbare Hülle, kein
   leeres Gerüst).
2. **Den Namen in der Kopie setzen, vor dem Import**: `PrProject.LongDesc` und
   `XmProject.LongDesc`. Der Importer trägt ihn dann durch. Danach umzubenennen
   heißt, zwei Tabellen in der Ziel-DB zu treffen, von denen die Oberfläche nur
   `XmProject` liest.
3. Brücke lokal aufrufen — **ohne Agent, ohne Server**:
   `hottgenroth-agent/bridge/bin/hsetu-bridge.exe --job <nutzlast.json>`.
   Die Nutzlast baut `App\Services\HottgenrothBrueckenImport::auftragFuerLokaleDatei()`;
   die Klasse hat keine Laravel-Abhängigkeit, `require` der Datei genügt.
   Aus dem Auftrag nur das `with` des `hsetu.bridge`-Schritts nehmen.

**Vorher `Test-SoftwareLaeuft.ps1`.** EEBerater lief; `CloseMainWindow()` mit
6 s Wartezeit reicht, hartes `Stop-Process` war nicht nötig. Siehe
[[energie-exe-verwaiste-instanz]].

**Die Kontaktschritte des Dienstes sind bei der Vorlage überflüssig** — sie hat
keine Kontakte (`CmContact` leer). Sie anzuhängen schriebe leere Rollen; die
Software legt ihren Standardsatz beim ersten Öffnen selbst an. Siehe
[[hsetu-kontaktrollen-import]].

Zurück kommt die Gruppen-GUID; das Projekt findet man darüber:
`XmProject.GroupUUID = <GruppenGuid> AND PrProject.VariantType = 2`.
