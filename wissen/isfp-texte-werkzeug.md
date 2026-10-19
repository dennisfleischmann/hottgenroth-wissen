---
name: isfp-texte-werkzeug
description: "isfp-texte-fuellen.ps1 befüllt einen iSFP aus den eigenen Textbausteinen — Quelle sind Container und XML, Ziel ist PrMedia.iSFP2.xml"
metadata:
  type: project
---

`isfp-werkzeug/isfp-texte-fuellen.ps1` (+ `zuordnung.json`), erprobt am 26.09.2026
an Klenke (V4DZX): 7 Ausführungen, 9 Skizzen, 5 Paketnamen, 10 MB geschrieben,
Gegenprobe bestanden.

    .\isfp-texte-fuellen.ps1 -Projekt 'Klenke'              # Vorschau
    .\isfp-texte-fuellen.ps1 -Projekt 'Klenke' -Schreiben

**Zwei Quellen, weil eine nicht reicht.** Hüllflächen aus `eberater.zip`
(`TableHuellfl.SANBEZ` je Variante), **Anlagentechnik aus der `iSFP2.xml`**
(`massnahmenpakete/item/anlagen`). Im Container steht sie nicht:
`TableAnlage.Beschr_Heiz` ist die alte DIN-4701-10-Beschreibung und bleibt auf dem
Ist-Zustand stehen, auch wenn nach DIN 18599 längst eine Wärmepumpe rechnet — daran
habe ich mich einmal getäuscht. Varianten sind kumulativ, genommen wird je Paket nur
der **Zuwachs** gegenüber dem Vorgänger.

**Geschrieben wird `PrMedia.iSFP2.xml`** ([[isfp-speicherstand-prmedia]]), zusätzlich
eine `.mSFPprojekt`-Datei für „Datendatei einlesen …". Vorher Sicherung mit SHA-256,
nachher Gegenprobe aus der Datenbank; Energie.exe muss zu sein.

**Zwei Fallen, beide gemessen:**
- Der Container schreibt **ohne Umlaute** („Haustuer", „Aussenwand", „Geruest").
  Ohne Entumlautung auf beiden Seiten trifft die Regel nicht — kostete 4 von 5.
- Die Bildvorlagen sind bis 10 MB groß; ohne Verkleinerung wird die XML 21 MB, mehr
  als jeder echte Export. `-MaxBildKante` (Standard 1200) verkleinert **nur im
  Speicher**, die Dateien bleiben unberührt.

**Was das Werkzeug nicht kann:** ein Paket ohne Maßnahme im Rechenmodell bleibt leer.
Bei Klenke traf das MP2 (PV steht nirgends: `selbstgenutztPvVorhanden=false`) und die
Lüftung in MP5 (`LEK_FREI`, WRG 0). Das ist keine Lücke im Werkzeug, sondern im Modell.

Verwandt: [[isfp-textbausteine-format]] · [[isfp-texte-bauteilbezug]] · [[isfp-drei-stufen]]
