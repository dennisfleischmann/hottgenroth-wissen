---
name: prproject-name-steht-in-longdesc
description: "Der Projektname steht in PrProject.LongDesc, nicht in ShortDesc — ShortDesc trägt die Projekt-/Kundennummer und ist bei über der Hälfte der Projekte leer"
metadata:
  type: project
  stand: gemessen
---

In `PrProject` trägt **`LongDesc`** den Projektnamen. `ShortDesc` ist etwas anderes: dort steht die **Projekt- bzw. Kundennummer** (`P 39596`, `159JW`, `10010`, `260076`) — bei 57 von 102 Projekten leer und in **keinem** der 45 gefüllten Fälle gleich `LongDesc`. Zum Suchen nach einem Namen taugt `ShortDesc` deshalb nicht; als Nummernfeld ist es intakt.

Der Schlüssel heißt **`UUID`** und ist in `PrProject`, `BmRoom`, `BmZone` und `BmElement` jeweils PRIMARY KEY. Die Fremdschlüssel in `BmRoom`, `BmZone`, `BmElement` heißen **`ProjectUUID`** (doppeltes U). Eine Spalte `Id` (int) existiert in allen vier Tabellen, ist aber **nicht** der Schlüssel; `Name`, `UId` und `ProjectUId` gibt es in keiner der vier Tabellen.

Projekt anhand eines Namensausschnitts finden:

```sql
SELECT UUID, LongDesc FROM PrProject WHERE LongDesc LIKE '%Test0001%'
```

Nebenbefund: Namen sind **nicht eindeutig** — 6 Namen sind mehrfach vergeben, davon betroffen sind 17 der 102 Projekte; Spitzenreiter ist `Jan Malte Strackerjan_iSFP` mit 7 Vorkommen. Nur 91 der 102 Namen sind eindeutig. Bei Schreibvorgängen deshalb immer über die UUID gehen, nie über den Namen.

**Beleg:** Ausgezählt auf `(localdb)\HSETU`, Datenbank `HsetuPrjData`; Nachmessung am 2026-08-21 bestätigt dieselben Zahlen. `SELECT COUNT(*), SUM(CASE WHEN ShortDesc IS NULL OR LTRIM(RTRIM(ShortDesc))='' THEN 1 ELSE 0 END), SUM(... LongDesc ...) FROM PrProject` → **102 Projekte, 57 mit leerem ShortDesc, 0 mit leerem LongDesc**. „Test0001" steht in LongDesc (UUID `2c5ac804-0dcc-4560-88a7-7b8827ff69f8`), ShortDesc ist dort leer; `WHERE ShortDesc LIKE '%Test0001%'` liefert null Zeilen. Der Join über `ProjectUUID` löst restlos auf: BmRoom 1624/1624, BmZone 436/436, BmElement 39191/39191 Zeilen zugeordnet. Namensverteilung und die 45 gefüllten `ShortDesc`-Werte ebenfalls ausgezählt (0 Übereinstimmungen mit `LongDesc`).

**Nicht gemessen:** Die Deutung von `ShortDesc` als „Projekt-/Kundennummer" ist aus den 45 gefüllten Werten gelesen, nicht aus einer Schemaregel oder Prüfbedingung — ein Projekt könnte dort etwas anderes eintragen. Ebenso ungemessen ist die Handlungsregel am Schluss (bei mehrdeutigem Namen die UUID erfragen); sie folgt aus den Zahlen, ist aber nicht selbst erprobt. Das Datum der Erstmessung ist nicht mehr rekonstruierbar, nur die Nachmessung vom 2026-08-21.

**Why:** Geratene Spaltennamen kosten hier jedes Mal zwei bis drei Fehlversuche: `Name`, `UId`, `ProjectUId` klingen richtig und existieren alle nicht, und `Id` existiert zwar, führt aber am Schlüssel vorbei. Schlimmer ist die stille Variante — eine Suche über `ShortDesc` liefert einfach null Zeilen und sieht aus wie „Projekt gibt es nicht", obwohl es da ist. Da 17 Projekte sich ihren Namen mit einem anderen teilen, ist auch ein Treffer noch kein Beweis, dass es der richtige ist.

**How to apply:** Projekte über `LongDesc LIKE` suchen, über `UUID` verknüpfen, Fremdschlüssel `ProjectUUID`. `ShortDesc` nur abfragen, wenn eine Projekt- oder Kundennummer gesucht ist — und damit rechnen, dass sie fehlt. Vor jedem Schreibvorgang die UUID festhalten; liefert die Namenssuche mehr als eine Zeile, die UUID erfragen statt die erste Zeile zu nehmen.
