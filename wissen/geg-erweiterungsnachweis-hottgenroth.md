---
name: geg-erweiterungsnachweis-hottgenroth
description: "Der § 51-GEG-Erweiterungsnachweis (Anbau/Aufstockung, H_T' ≤ 1,2× Referenz) steckt im Energieberater hinter zwei Häkchen im Zonen-Dialog, die noch 'EnEV §9 Abs.5' heißen"
metadata:
  node_type: memory
  type: reference
  originSessionId: 1a6696d9-821f-4695-ae5a-8fd830bdb698
  modified: 2026-10-14T08:44:11.669Z
---

Für die Erweiterung eines Wohngebäudes ohne neuen Wärmeerzeuger (§ 51 GEG,
H_T' des neuen Gebäudeteils ≤ 1,2 × Referenzgebäude) hat der Energieberater
einen eingebauten Nachweisweg — **die Beschriftung stammt noch aus der EnEV**:

- **Zone → Reiter „Nutzung"** (klassisch `TForm18599_Zonen`) bzw. **„Allgemein"**
  (`TFrame18599_ZonenV5`), direkt neben der Gruppe „Sommerlicher Wärmeschutz"
  ([[sommerlicher-waermeschutz-bestaetigen]]):
  - `ChBox_IsBuildingWithExtensionAccordingEnEVArticle9Chapter5` —
    „Gebäude mit Anbau EnEV §9 Abs.5" (Gebäude-Schalter)
  - `ChBox_IsExtensionZoneAccordingEnEVArticle9Chapter5` —
    „Zone ist Erweiterung > 50 m² nach EnEV §9 Abs.5" (je Zone)

**Was der GEG20-Kernel daraus macht** (`IBP18599kernelGEG20.cs`): Ist der
Gebäude-Schalter gesetzt, bekommen alle **nicht** markierten Zonen
`bSkipThisZoneForCalculation… = true` und fallen komplett aus der Bilanz —
in Ist- UND Referenzgebäude. Gerechnet wird nur die Erweiterungszone, und
`fH_T_max = Round(1,2 × H_T'_Referenz, 1)` (Zeile ~3993). Das IST § 51 GEG,
nur die Feldnamen blieben EnEV. Folge: ein Projekt kann nicht gleichzeitig
Ganzhaus-Bilanz und Erweiterungsnachweis tragen — der Schalter vergiftet alles andere.

**Modellierung:** nur die neuen beheizten Räume als Zone erfassen (oder
Zwei-Zonen-Modell, Bestandszone wird ohnehin übersprungen). Trennflächen zum
beheizten Bestand **nicht** als Hüllfläche aufnehmen. Anlagentechnik plausibel
füllen, damit die 18599-Bilanz durchläuft — für die Anforderung zählt nur H_T'.
Ausdruck: `GEG-Nachweis-EPass18599.rtf` (H_T' vorhanden vs. max; PE-Werte
erscheinen mit, sind aber nicht die Anforderung).

**Automatisierbar:** beide Flags liegen im IBP-Blob
(`InputEnEV.bIsBuildingWithExtensionAccordingEnEVArticle9Chapter5`,
`Zones[..].InputForEnEV.bIsExtensionAccordingEnEVArticle9Chapter5`) —
per [[ibp-sammlungen-schreiben]]-Werkzeugkette setzbar; für Einzelfälle ist
der Klickweg schneller.

**Hebel wenn's knapp wird:** Referenz rechnet fest mit ΔU_WB 0,05, der
Ist-Zuschlag (pauschal 0,10) geht 1:1 ein — der Wärmebrückenzuschlag ist der
einzige Hebel, der voll durchschlägt ([[ht-strich-referenz-wandert-mit]]).
Grenzwert immer ablesen, nie selbst nachbauen.
