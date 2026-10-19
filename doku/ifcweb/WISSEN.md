# Wissensbestand — wo was liegt

Diese Datei ist der Einstieg. Wer neu dazukommt — eine neue Sitzung, ein Agent,
ein Mensch — liest zuerst hier und weiß danach, wo alles steht.

Der Anlass: Wissen hing zu lange an einer laufenden Sitzung. Was in einer
Unterhaltung gelernt wurde, war nach deren Ende weg, wenn es nicht vorher an
einen der vier Orte unten geschrieben wurde.

---

## Die vier Orte und ihre Rollen

| Ort | Was dort steht | Verbindlichkeit |
|---|---|---|
| `bauteile/docs/*.md` | **Das Datenmodell.** Welche Tabelle, welche Spalte, welcher Sentinel, welche Aufzählung. Prosa mit Zahlen. | Quelle für *warum* |
| `bauteile/tools/*.ps1` | **Die Umsetzung.** Jedes Werkzeug trägt seine Regel im Kopfkommentar, samt der Messung, aus der sie stammt. | Quelle für *wie* |
| `sanierungsfahrplan-agent/beispiele/` | **Die Belegfälle.** Exakte Zeichnungen eines Modells, das in der Software nachweislich richtig aussah. | Quelle für *dass es stimmt* |
| `sanierungsfahrplan-agent/skills/` | **Die Handlungsanweisungen.** Was der Agent tun soll, welche Angaben er vorher braucht, welche Fallen es gibt. | Quelle für *was tun* |

Dazu `gedaechtnis/` — **das gemeinsame Gedächtnis.** Kein Archiv mehr: der Agent
liest daraus mit `wissen_lesen` und `wissen_suchen` und schreibt mit
`wissen_merken` hinein. Der **Index** (`MEMORY.md`) steht im Systemprompt, die
Einträge werden auf Abruf geholt — alle 36 wären 88 000 Zeichen und würden ihn
verdreifachen.

Jeder Eintrag trägt einen **Stand**: `gemessen`, `gerechnet` oder `geschlossen`.
Das Feld ist Pflicht und lässt sich nicht umgehen. Es ist die Lehre aus dem
teuersten Irrtum dieser Arbeit: die Behauptung, Räume ließen sich nicht anlegen,
war `geschlossen`, wurde als Tatsache notiert und wochenlang zitiert.

Das lokale `~/.claude/…/memory/` ist die Arbeitskopie der Sitzungen. Abgleichen:

```powershell
Copy-Item "$env:USERPROFILE\.claude\projects\c--Projekte-Dev-energieberatung\memory\*.md" `
          "C:\Projekte_Dev\energieberatung\sanierungsfahrplan-agent\gedaechtnis\" -Force
```

---

## Die Lernschleife

Wissen entsteht hier nicht durch Nachdenken, sondern durch Messen. Der Ablauf,
der sich bewährt hat, und der Grund für jeden Schritt:

1. **Messen statt raten.** Aufzählungswerte, Attributnamen, Pflichtfelder werden
   am Bestand ausgezählt (`Anzahl über alle Projekte`), nicht hergeleitet. Wo der
   Bestand nichts hergibt, muss ein Mensch es einmal in der Oberfläche bauen.
2. **Schreiben, mit Probelauf davor.** Vorher sichern, `Assert-SoftwareZu`.
3. **Selbst prüfen.** `Snapshot-Projekt.ps1` + `Diff-Snapshot.ps1` — nur die
   beabsichtigten Zeilen dürfen sich geändert haben.
4. **Wirkungsprobe in der Software.** Zeilen in der Datenbank beweisen nichts.
   Das Pultdach stand sauber in allen Spalten und ergab trotzdem keine Fläche.
5. **Erst danach festhalten** — Doku, Werkzeug-Kopfkommentar, Skill.
6. **Belegfall exportieren.** `Export-Referenzfall.ps1`. Ohne Bestätigung kein
   Referenzfall; der Parameter ist Pflicht.
7. **Committen.**
8. **Rückblick, wenn etwas schiefging** — nach `skills/fehlerbilder/SKILL.md`.
   Nicht die Einzelheit (die steht im Datenmodell), sondern **der Denkfehler**:
   was geglaubt, was tatsächlich, woran aufgefallen.

Schritt 6 bis 8 sind die, die lange gefehlt haben.

**Und wenn eine alte Aussage widerlegt wird: überall streichen.** Die
Behauptung, Räume ließen sich nicht anlegen, stand an fünf Orten und wurde
wochenlang zitiert, nachdem sie längst widerlegt war. Eine Korrektur an nur
einer Stelle ist keine Korrektur.

---

## Was heute geht

Der belastbare Stand steht in zwei Dateien und wird **dort** fortgeschrieben,
nicht hier:

- `skills/daecher/SKILL.md` — Dächer, mit `erprobungsstand:` im Kopf
- `gedaechtnis/hottgenroth-dachtypen-stand.md` — Liste „kann ich / kann ich noch nicht"

Jeder Skill trägt ein Feld `erprobungsstand:`. Die Stufen bedeuten:

| Stufe | heißt |
|---|---|
| `erprobt` | mehrfach gelaufen, Ergebnis in der Software gesehen |
| `geschrieben-und-gegengeprueft` | geschrieben, Zeilen verglichen, Wirkung bestätigt |
| `teilweise-gemessen` | Datenmodell verstanden, nie geschrieben |
| `gefunden-nicht-vermessen` | weiß, wo es liegt, mehr nicht |
| `teils-widerlegt` | enthält Aussagen, die sich als falsch erwiesen haben |

**Der Unterschied zwischen „gerechnet" und „in der Software gesehen" ist der
wichtigste in diesem Bestand.** Er wird überall mitgeführt, weil er schon
zweimal den Unterschied zwischen richtig und falsch gemacht hat.

---

## Die harten Regeln

Kurzfassung; ausführlich in `bauteile/docs/`.

- **Die Zeichnung ist die Quelle**, nicht die Tabelle. `BmData.ClassValue` mit
  `LongDesc='CADXMLData'` trägt das Modell; Flächen, Volumen und Umrisse rechnet
  HottCAD daraus. Abgeleitetes nie von Hand pflegen.
- **Was nicht in der Zeichnung steht, existiert für die Oberfläche nicht.** Zwei
  Geschosse standen korrekt in `BmFloor` und wurden trotzdem nicht angezeigt.
- **Keine Hottgenroth-Anwendung darf offen sein**, sonst wird jede Änderung beim
  Beenden still verworfen. Der EE-Berater läuft als `EEBerater`, nicht als
  `Energie`. Ein Probelauf ist davon ausgenommen — er schreibt nichts.
- **Zeilen kopieren statt zusammensetzen.** Ein neues Bauteil entsteht als
  Spalte-für-Spalte-Kopie eines vorhandenen desselben Projekts. Dann stimmen
  auch die Spalten, die niemand kennt.
- **Löschen ist die einzige Aktion, die sich nicht durch Neuschreiben beheben
  lässt.** Vorher sichern.
