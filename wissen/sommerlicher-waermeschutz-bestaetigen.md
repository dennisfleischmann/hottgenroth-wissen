---
name: sommerlicher-waermeschutz-bestaetigen
description: Das Häkchen "Sommerlicher Wärmeschutz nach DIN 4108-2 erfüllt" sitzt im Zonen-Dialog auf dem Reiter Nutzung — und ein zweites, anders gemeintes auf dem Reiter Kühlung
metadata:
  type: reference
---

Im Energieberater (`Energie.exe`) wird der sommerliche Wärmeschutz **in der Zone**
bestätigt, nicht am Gebäude:

- **Zone → Reiter „Nutzung"** (Steuerelement `TabSheetAllgemein`, Caption „Nutzung"; in
  der V5-Oberfläche `TFrame18599_ZonenV5` heißt der Reiter „Allgemein"), Gruppe
  **„Sommerlicher Wärmeschutz"**: Häkchen `ChBox_SummerlyHeatProtection` —
  „Sommerlicher Wärmeschutz nach DIN 4108-2 erfüllt". **Das ist die Bestätigung.**
- Direkt daneben der Knopf `SBtn_SummerlyHeatProtection` („Sommerlicher Wärmeschutz",
  Hint „Sommerlicher Wärmeschutznachweis nach DIN 4108-2") öffnet den eigentlichen
  Nachweis `TForm4108T2_SomWaerm` — **raumweise** für die kritischen Räume, mit
  „Neuen Raum anlegen". Klimazuordnung im eigenen Dialog `TFormKlimaRegion4108T2`
  („Klimaregionen sommerlicher Wärmeschutz – DIN 4108-2").

**Die Falle:** dasselbe Häkchen steht ein zweites Mal auf dem **Reiter Kühlung**
(`ChBox_SummerlyHeatProtection2`), dort unter „Zone wird nicht in Kühlbilanz
berücksichtigt – Sommerlicher Wärmeschutz ist erfüllt / siehe DIN 18599-2 Absch. 6.1.3.3".
Das ist **nicht** der Gebäudenachweis, sondern die Begründung, eine angrenzende ungekühlte
Zone aus der Kühlbilanz zu lassen. Verwechseln heißt: bestätigt an der falschen Stelle.

Ausgabe: Ausdruckdialog `TFormOptiDINBerech` → Häkchen „Sommerlicher Wärmeschutznachweis"
(`ChBoxDruckSommer`); im Energieausweisdialog `TFormEnergieausweis2020` unter
„GEG-Anforderungen ausgeben" das Häkchen `cbSomWaermeschutz`. Vorlage:
`C:\ProgramData\HSETU\Energieberater2022\Textverarbeitung\AusdruckDef\SommerlicheWaermeschutz.rtf`.

Nicht verwechseln mit dem Reiter „Sommerl. Wärmeschutz" in `TForm_OE_ZeusUploadV6/V7` —
das ist der **österreichische** OIB-Weg (Lizenzmodul „Sommerlicher Wärmeschutz Österreich").

**Why:** Wer nur den Nachweisknopf findet, rechnet und bestätigt trotzdem nicht; wer das
Häkchen auf dem Kühlungsreiter setzt, bestätigt etwas anderes.

**How to apply:** Gefunden mit dem Rezept aus [[energie-exe-delphi-formulare]] —
`grep -a -o -b` auf die EXE, Formularzuordnung über die `TPF0`-Marken (jede DFM-Ressource
beginnt damit, Klassenname und Instanzname folgen im Klartext).
