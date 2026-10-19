---
name: isfp-textbausteine-format
description: "Die eigenen iSFP-Textbausteine sind schlichte Klartextdateien mit Bauteilgruppen als Überschrift — zwei Trennkonventionen, nicht eine"
metadata:
  type: reference
---

`Texte_iSFP_*.txt` — liest die iSFP-Maske über „Eigene abgespeicherten Text einlesen".
Live unter `%APPDATA%\HSETU\EnergieberaterPlaner\Projektdaten\iSFP\`, die gepflegte
Fassung liegt im Drive und als Arbeitskopie unter `isfp-werkzeug/`.

**UTF-8 mit BOM, nur LF.** Kopfzeile `Eigene Texte zum iSFP`, dann Leerzeile. `¶`
(U+00B6) ist der Zeilenumbruch *im* Text, `¶¶` der Absatz.

**Zwei Konventionen, je nach Datei — beide müssen gelesen werden:**

| Datei | Gruppentrenner | `-  -  -` bedeutet |
|---|---|---|
| `Kompo_Beschreibung`, `Kompo_ZuBeachten` | `-  -  -` | nächste **Gruppe** |
| `Kompo_AusfuehrungKurz`, `Das_bringt_es` | Leerzeile | nächste **Variante** in derselben Gruppe |

Die Gruppenüberschrift ist die **Bauteilkategorie** (`AUßENWAND`, `DACH`,
`OBERSTE GESCHOSSDECKE`, `HEIZUNGSAUSTAUSCH`, …). Ein Baustein beginnt mit
`Name - ` — dieses Präfix landet mit im iSFP-Text und ist dort der einzige Hinweis,
welcher Baustein benutzt wurde ([[isfp-texte-bauteilbezug]]).

**Fallen:** an zwei Stellen ist der Trenner tabuliert (`-⇥-⇥-`), es gibt verstreute
Leerzeilen mitten in Gruppen, und die Namen in `Beschreibung` und `ZuBeachten`
stimmen nur zu 35 von 46 überein (`Vorhangfassade (Gaube)` gegen `(Gauben)`,
`Kellerwand Innendämmung` gegen `Kellerinnenwand`). Ein Leser muss beides aushalten;
die Paarung gehört in eine Tabelle, nicht in einen Namensvergleich —
`isfp-werkzeug/zuordnung.json`.

**How to apply:** Vor jeder Änderung sichern und danach gegenparsen (Gruppenzahl,
Bausteinzahl je Gruppe, BOM, CRLF-frei). `das_bringt_es` ist auf **400 Zeichen**
gedeckelt; bei Paketen über mehrere Gruppen in Paketreihenfolge zusammenführen,
Doppelte entfernen und bei 400 abbrechen — das lässt Nebenmaßnahmen von selbst weg.
