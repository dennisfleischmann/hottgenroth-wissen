---
name: varianten-nummer-ist-fluechtig
description: "Die PROJEKT_ID einer Sanierungsvariante wird beim Löschen anderer Varianten neu vergeben — Varianten immer über den Namen adressieren, und es gibt zwei Zahlen, die beide „Variante\" heißen"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 634a2411-a32e-41c2-8ecf-cb250ec3dc7c
  modified: 2026-10-04T13:08:15.187Z
---

**`PROJEKT_ID` einer Sanierungsvariante ist keine stabile Kennung.** Werden
Varianten gelöscht, vergibt die Software die Nummern neu: dasselbe Maßnahmenpaket
im Projekt V4DZX trug am **03.10.2026 die 12** und am **04.10.2026 die 3**,
nachdem fünf Varianten entfernt worden waren.

Ein Auftrag, der eine gemerkte Nummer mitbringt, trifft danach **lautlos die
falsche Variante** — jede Nummer ist für sich gültig, es gibt keine Fehlermeldung.
Dieselbe Lehre wie bei [[container-ergebnisse-gehoeren-der-software]] (`HUELL_ID`),
nur eine Ebene höher.

**Deshalb: über `VarianteBez`, den Namen.** Er ändert sich nur, wenn ihn jemand
ändert. Aber Zeichen für Zeichen aus `get_hottgenroth_sanierungsvarianten`
übernehmen — die Software **kürzt** lange Namen im Container ab: aus
„MP6 EH 85 – Kundenziel (aus Ist-Zustand)" wird
„MP6 EH 85 – Kundenziel (aus Ist-Zus".

**Und es gibt zwei Zahlen, die beide „Variante" heißen**, die nicht
übereinstimmen:

| Quelle | Bedeutung |
|---|---|
| `get_hottgenroth_sanierungsvarianten` → `nummer` | Position, 0 = Ist-Zustand |
| Container `TableProjekt.PROJEKT_ID` / `TableZusatz.PROJ_ID` | die echte, flüchtige Kennung |

`set_hottgenroth_heizung` nimmt noch eine Nummer entgegen — das ist die ältere
Bauart und trägt dieses Risiko. `set_hottgenroth_cad_bindung` nimmt den Namen
(Regel HA-14).

**How to apply:** Eine Variantennummer nie über einen Arbeitsschritt hinweg
merken; zwischen zwei Aufrufen kann jemand in der Software aufgeräumt haben.
Verwandt: [[cad-bindung-sperrt-die-variante]],
[[varianteid-verweist-auf-ist-zustand]], [[varianten-sind-schnappschuesse]].
