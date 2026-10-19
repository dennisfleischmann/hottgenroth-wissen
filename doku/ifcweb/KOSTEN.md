# Warum der Assistent teuer war — und was daran zu ändern ist

Stand 23.08.2026. Alle Zahlen hier sind **gemessen**, nicht geschätzt: die
Token-Angaben stammen aus dem `usage`-Feld der API oder aus `count_tokens`, die
Preise aus der Liste. Wo etwas gerechnet ist, steht es dabei.

Geschrieben, weil an einem Tag rund 25 USD zusammenkamen und die Frage „wofür
eigentlich" eine belastbare Antwort verdient.

---

## Die kurze Antwort

**Nicht das Arbeiten ist teuer, sondern das Anfangen.**

Bei einem gemessenen Lauf mit zwei SQL-Abfragen sah die Rechnung so aus:

| Posten | Token | Anteil |
|---|---|---|
| Systemprompt + Werkzeuge, geschrieben | 35.860 | 49 % |
| dieselben, gelesen | 35.860 | 49 % |
| Werkzeugergebnis | 722 | 1 % |
| Auftrag + Antwort | ~1.100 | 1,5 % |

**Die eigentliche Arbeit waren 1.800 Token. 97,5 % war Rüstzeit.**

Daraus folgt alles Weitere:

```
1 Frage in einer Sitzung      $0,24    alles Rüstzeit
12 Fragen in EINER Sitzung    $0,35    $0,03 je Frage
12 Fragen in 12 Sitzungen     $2,90    $0,24 je Frage — achtmal so teuer
```

Wer für jede Kleinigkeit ein neues Gespräch öffnet, bezahlt zwölfmal den
Aufbau. Genau das ist am 22./23.08. beim Entwickeln passiert: bei jedem Test
ein frischer Lauf.

---

## Wo das Geld hingeht

Der feste Anteil, der bei jedem Zug gelesen und je Sitzung einmal geschrieben
wird — nach allen Verbesserungen vom 23.08.:

| Bestandteil | Token | Anteil |
|---|---|---|
| **Werkzeuge (32 Schemata)** | **15.975** | **44 %** |
| system.md | 5.840 | 16 % |
| Gedächtnisverzeichnis | 5.466 | 15 % |
| WISSEN.md | 2.790 | 8 % |
| referenz/hsetu-decompiled.md | 2.515 | 7 % |
| Fertigkeits-Verzeichnis | 1.924 | 5 % |
| beispiele/README.md | 891 | 2 % |
| **zusammen** | **35.935** | |

Vorher waren es 58.430 — die Fertigkeiten lagen vollständig im Prompt.

Die drei Ausgabewerkzeuge `modell_rendern`, `ifc_exportieren` und
`grundriss_exportieren` sind allein **4.461 Token**, weil jeder ihrer 10–18
Parameter beschrieben ist. Eine Kubatur braucht keines davon.

---

## Was schon gemacht ist

| Maßnahme | Wirkung, gemessen |
|---|---|
| **Prompt-Caching** eingeschaltet | 83 % auf den festen Anteil |
| **Sonnet 5** statt Opus 5 | $0,634 → $0,396 beim selben Auftrag, dazu halbe Laufzeit |
| **Fertigkeiten auf Zuruf** (`fertigkeit_lesen`) | 58.430 → 35.935 Token, $0,396 → $0,254 |
| **Projektliste ohne Modell** (`GET /api/projekte`) | $0,63 → $0,00, 820 ms |
| **Schleifenbremse** (3× derselbe Aufruf) | hätte 0,90 von 1,00 USD gespart |
| **Kostenbremse je Projekt** | $5 Obergrenze, $1 je Lauf, greift mitten im Lauf |

Derselbe Auftrag über den Tag:

```
Opus 5, alles im Prompt      $0,634   14 s
Sonnet 5, alles im Prompt    $0,396    7 s
Sonnet 5, Verzeichnis        $0,254    7 s
```

---

## Was noch offen ist, nach Wirkung sortiert

### 1. Hochgeladene Pläne — der größte ungelöste Posten

Eine PDF von 928 KB sind **37.484 Token**, gemessen. Sie liegt im Gespräch und
wird bei **jedem Zug** als frische Eingabe bezahlt. Über 40 Züge sind das rund
**4,50 USD allein für dieses eine Dokument** (gerechnet, nicht gemessen).

Zwei Wege:

**a) Aufnahmelauf.** Ein Lauf liest die Pläne einmal und legt strukturierte
Befunde ab (`befund_ablegen`). Alle weiteren Läufe bekommen die Befunde
(1–2k Token) statt der PDFs. Dazu ein Werkzeug `unterlage_ansehen(seite)`, mit
dem gezielt nachgeschlagen werden kann. **Die Ablage dafür steht bereits**
(`src/befunde.ts`, drei Werkzeuge) — sie ist nur noch nie benutzt worden.

**b) Gesprächs-Cache.** Wurde am 22.08. versucht und hat eine **Endlosschleife**
verursacht: `setMessagesParams` ersetzt die Nachrichtenliste, der Mutator baute
ein neues Array, und der Runner hängte die Werkzeugergebnisse ans alte. Das
Modell sah seine eigenen Ergebnisse nie und fragte siebzehnmal dasselbe. Kosten:
1 USD. Die Warnung steht ausführlich in `src/lauf.ts`. Wer es erneut versucht,
muss die vorhandene Liste **an Ort und Stelle** ändern und mit mehreren
Werkzeugaufrufen prüfen — der Fehler zeigt sich erst ab dem zweiten Zug.

Weg (a) ist der sichere und nutzt, was schon da ist.

### 2. Werkzeugbeschreibungen kürzen — 44 % des Überbaus

Jedes Werkzeug hat einen ausführlichen Zweck und je Parameter einen Satz; das
sind im Schnitt 500 Token je Werkzeug. Die Hälfte ginge ohne Substanzverlust.
Risikoarm, ohne Datenbank, ohne Modellaufruf zu prüfen.

### 3. Werkzeugprofil je Lauf

Nicht alle 32 Werkzeuge werden immer gebraucht. Ein festes Profil je Lauf,
gewählt **vor** dem Cache, spart etwa 4.500 Token. Wichtig: fest je Lauf, nicht
zur Laufzeit gewechselt — Laufzeit-Eingriffe haben hier zweimal etwas
zerbrochen.

### 4. Weniger Züge: Modell plant, Skripte zeichnen

Heute zeichnet das Modell Schritt für Schritt (~40 Züge für ein Gebäude). Wenn
es stattdessen einen geprüften Bauplan als JSON erzeugt, den deterministische
Skripte ausführen, und danach nur das Ergebnis prüft, sind es 8–12 Züge. Jeder
gesparte Zug spart Cache-Lesen, Ausgabe und Verlaufszuwachs.

### 5. Alles Feste raus aus dem Modell

`GET /api/projekte` war der Anfang und hat sofort $0,63 auf $0,00 gebracht.
Dieselbe Kategorie: Projekt-Ist-Stand, Bauteillisten, Exporte, Statusabfragen.

> **Regel: Wo nichts zu entscheiden ist, kein Modell.**

---

## Was NICHT das Problem war

- **Die Ausgabe.** 285–600 Token je Lauf. Bei Sonnet $0,004–0,009.
- **Der Gesprächsverlauf.** Über zwölf Züge 264 Token — unter einem Cent.
- **Das Modell an sich.** Der Wechsel auf Sonnet brachte 38 %, das Kürzen des
  Überbaus brachte mehr.

---

## Zwei Fehler, die Geld gekostet haben

Beide gehen auf die Entwicklung, nicht auf den Betrieb:

1. **Kein Caching bis zum 22.08.** Alle Prüfstandsläufe davor zahlten den vollen
   Preis für 56.850 Token je Zug. Bei ~20 Läufen war das der größte Einzelposten
   des Tages.
2. **Die Endlosschleife** (siehe oben), 1 USD.

Dazu kommt, was keine Verschwendung war, aber teuer aussieht: die
Prüfstandsläufe selbst. Sie sind die einzige Möglichkeit zu wissen, ob der
Assistent noch tut, was er soll.

---

## Wenn du später weitermachst

**Der Zustand ist arbeitsfähig.** Alle Prüfungen laufen grün:

```
npm run pruefen            Typen
npm run pruefe-pruefungen  29 Prüfungen, ohne Datenbank, ohne API
npm run pruefe-wissen      Widersprüche im Wissensbestand
npm run web                Oberfläche auf 127.0.0.1:4711
```

Einstellbar über `.env`:

```
ISFP_MODELL=claude-sonnet-5
ISFP_AUFWAND=medium
ISFP_BUDGET=5          Obergrenze je Projekt
ISFP_LAUFGRENZE=1      Obergrenze je einzelnem Lauf
```

**Der wirksamste Hebel kostet keine Zeile Code:** ein iSFP ist EINE Sitzung, nicht
eine Sitzung je Frage. Dafür gibt es „Sitzung fortsetzen" — die Ablage unter
`sitzungen/` überdauert den Neustart, und seit dem 23.08. auch einen
abgebrochenen Lauf.

**Was ungemessen bleibt:** ob Sonnet die Geometrie so trifft wie Opus. Der
Prüfstand hat dafür 16 Aufträge; vier davon (`02`, `11`, `12`, `13`) betreffen
das Rechnen. Sie sind nie auf Sonnet gelaufen. Solange das so ist, ist die
Umstellung eine Kostenentscheidung mit offenem Ausgang — keine erprobte
Verbesserung.
