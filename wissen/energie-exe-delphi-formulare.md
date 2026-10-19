---
name: energie-exe-delphi-formulare
description: "Energie.exe trägt die Delphi-Formulare im Klartext — Steuerelementnamen, Hints und Captions sind mit grep -a lesbar und verraten, welches Eingabefeld ein XML-Feld füllt"
metadata:
  node_type: memory
  type: reference
  originSessionId: 4f0538bd-ca70-49d8-9f49-7c802c435628
  modified: 2026-09-12T03:32:25.937Z
---

Der .NET-Teil des Energieberaters ist dekompiliert ([[hsetu-dekompilierter-korpus]]),
**die Oberfläche der Energieberatung ist es nicht** — sie steckt in
`C:\Program Files\HSETU\Energieberater2022\Energie.exe`, 299 MB Delphi.

Trotzdem ist sie lesbar: die **DFM-Ressourcen liegen unkomprimiert als ASCII** darin
(CP1252, nicht UTF-16 — deshalb trifft ein gewöhnliches `grep -a`, und ein
UTF-16-Muster trifft nichts). Zu finden sind:

- **Steuerelementnamen** in Blöcken, gruppiert nach Formular und Reiter
  (`TabSheet_Anlagentechnik`, `CheckBox_RegenNutz_Hz_1` … `_5`, `Edit_Art_Hz_4`)
- **`Hint`- und `Caption`-Texte** direkt beim Element — oft wortgleich mit der
  Dokumentation im Austauschschema, was die Zuordnung Feld → XML-Tag beweist
- **ComboBox-Einträge** als Aufzählung (`Fensterlüftung`, `Abluftanlage - ungeregelt`, …)

Die Namenskonvention verrät die Spalten: **ohne Suffix = erste Spalte**, `_1` … `_5`
die weiteren. Wer wissen will, ob ein Wert je Zustand getrennt eingegeben wird oder
nur einmal, zählt die Elemente.

**Why:** So ist ohne Klicken und ohne Rückfrage entscheidbar, ob ein Wert im
Programm **eingegeben** oder **gerechnet** wird — der Unterschied zwischen
„Eingabefehler" und „Softwarefehler". Genau so wurde
[[isfp-regenerativ-haekchen]] geklärt.

**How to apply:**

```bash
exe="/c/Program Files/HSETU/Energieberater2022/Energie.exe"
grep -a -o -b "Suchbegriff" "$exe" | head          # Byte-Offsets holen
dd if="$exe" bs=1 skip=<offset-200> count=20000 2>/dev/null \
  | tr -c '[:print:]äöüÄÖÜß\n' '\n' | grep -v '^$'  # Umgebung lesbar machen
```

Rückwärts ab dem Offset lesen, nicht nur vorwärts — das Formular steht davor.
