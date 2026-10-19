---
name: isfp-pilcrow-nicht-in-die-xml
description: "Das ¶ der Textbausteine ist nur eine Dateikonvention — in der iSFP-XML wird es wörtlich angezeigt und muss vorher umgewandelt werden"
metadata:
  type: reference
---

In `Texte_iSFP_*.txt` steht **¶** (U+00B6) für den Zeilenumbruch, weil dort ein
Baustein auf einer Zeile stehen muss ([[isfp-textbausteine-format]]). Die Maske
wandelt es beim Einfügen um. **Wer den Text direkt in die `iSFP2.xml` schreibt,
muss das selbst tun** — sonst steht das Zeichen im gedruckten Fahrplan.

Am 26.09.2026 so passiert: die Ausgangssituation bei Klenke kam mit
`…gliedern lassen: Bauliche Hülle:¶- Bodenplatte – nachträgliche Dämmung¶…`
in der Maske an. Dennis hat es von Hand entfernt.

**In 39 echten Exporten kommt ¶ null mal vor.** Stattdessen:

| Feld | Umbruch |
|---|---|
| `ausfuehrung[].beschreibung`, `.zu_beachten` | `<br>` |
| `anschreiben`, `ausgangsSituationFuerSanierung`, `schritte`, `das_bringt_es`, `techDoku/*`, `nutzereinfluss/*` | echter Zeilenumbruch (LF) |
| `nutzerHinweise`, `heizungsOptimierung` | beides gemischt, beides trägt |

**How to apply:** Beim Schreiben ¶ ersetzen — `<br>` in den beiden RichText-Feldern
der Ausführung, sonst LF. `¶¶` wird zum Absatz, also `<br><br>` bzw. zwei LF.
Gegenprobe: in der fertigen XML darf `¶` nicht mehr vorkommen.
