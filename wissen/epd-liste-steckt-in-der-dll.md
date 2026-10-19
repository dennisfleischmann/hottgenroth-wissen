---
name: epd-liste-steckt-in-der-dll
description: Die EPD-Auswahlliste der Ökobilanz liegt als eingebettete CSV in Hsetu.EcoBilancing.LCA.DataAccess.EPD.dll, nicht in der LocalDB
metadata:
  type: reference
---

Die Liste hinter der Spalte „EPD-Zuordnung" (ECO-CAD, Ökobilanz → Baustoffe kombiniert)
kommt **nicht** aus der Datenbank und **nicht** aus dem Netz, sondern aus String-Ressourcen
in `C:\Program Files\HSETU\ECO-CADPlaner\Hsetu.EcoBilancing.LCA.DataAccess.EPD.dll`:
`OBD_2020_II` (ÖKOBAUDAT), `BBSR_RLCA_EcoCad_2_*` + `BBSR_*_EnergyUse_*` (QNG),
`Baustoffkonfigurationen_OBD_2020_II` (Nutzungsdauer je UUID).

Herausholen: `ilspycmd -p -o <ziel> <dll>` → eine `…Properties.Resources.resx`, die CSVs
stehen darin als `<data><value>`. Trennzeichen `;`, keine Anführungszeichen.

**Warum wichtig:** ohne das sucht man in `(localdb)\HSETU` oder bei oekobaudat.de —
beides falsch, die Software ist beim Zuordnen offline.

**So anwenden:** welcher Bestand aktiv ist, entscheidet die Seite „Einstellungen"
(`DatabaseEntriesRepositoryChooser`). ÖKOBAUDAT 2020 II hat 994 UUIDs, davon sind
**947 auswählbar** — `ObdItemValidator` wirft alles weg, dessen Bezugseinheit nicht
kg/m3/qm/m/pcs./a/MJ ist. BBSR: 388 Baustoffe in allen Fassungen gleich (v1.0–v1.3
unterscheiden sich nur in Zahlen), dazu 10 (bis v1.2) bzw. 18 (v1.3) Energie-Prozesse.
Verwandt: [[hsetu-dekompilierter-korpus]].
