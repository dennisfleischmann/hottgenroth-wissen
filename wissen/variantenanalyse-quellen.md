---
name: variantenanalyse-quellen
description: "Alle Varianten eines Projekts prüfen: wo Anlagenkosten, Wirtschaftlichkeitszeilen und Energiebilanz liegen — und wie man eine nicht neu gerechnete Variante erkennt (gleiche Eingaben, andere Ergebnisse)"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 3b8ba9ad-6502-45d2-9054-c195f5d8b740
  modified: 2026-09-15T19:27:34.939Z
---

Für eine vollständige Variantenanalyse reichen die Hüllflächen nicht. Die übrigen
Quellen im Container ([[energieberater-sanierungsvarianten]]):

| Was | Wo |
|---|---|
| Anlagenmaßnahmen mit Kosten | `TableAnlage.InvestKostenText` — `Bezeichnung\|Invest\|Invest_EE\|Betrieb` je Zeile |
| alle iSFP-Wirtschaftlichkeitszeilen | `TableProjekt.Wirtschaft` — `Bez\|Invest\|Lebensdauer\|Sowieso\|…\|EE\|…\|Kennz\|Bauteil\|Fläche` |
| Energiebilanz je Variante | `TableResult.EBilanz` (Schlüssel=Wert): `Q_Prim`, `Q_End`, `A_n`, `H_T`, `Q_p_RefGeb`, `H_T_RefGeb`, `EE_Anteil_BEG`, `Q_Verl_Heiz_d`, `Q_Verl_Wass_d` |
| Verluste je Strang | `TableHeizung` / `TableWasser` (`VerteilQ`, `Erz1AZ` = Aufwandszahl, bei WP ≈ 1/JAZ) |

**Förderung hat zwei Eingabestellen, beide im Energieberater** (belegt aus den DFM in
`Energie.exe`):

1. Variante: Dialog `TForm_Foerderung` „Mögliche Förderzuschüsse aus den
   Förderprogrammen“, ein „Förderzuschuss“ je Variante (`NumEd_Foerderung1…10`), liest
   `QueryZusatz` → `TableZusatz.Foerderung` (Float). Fußnote im Dialog: bei der
   BAFA-Vor-Ort-Beratung nicht berücksichtigt. **Im Programm kaum zu finden:** der Knopf
   „Förderungen *“ in „Ausdruck-Optionen Vor-Ort-Beratung“ steht im DFM auf
   `Visible = False`; derselbe Dialog öffnet über „Maßnahmenkombinationen“ (gleicher
   `OnClick`). Für den iSFP ist er belanglos.
2. iSFP-Maske `TFormAusdr_iSFP20`, **Reiter „Kosten“** (intern `TabSheet_Wirtschaft`,
   vom Nutzer so gefunden): links je Paket
   `NumEdit_Invest_n`, `NumEdit_Instand_n`, `ChBox_FoerderMoegl_n`, `NumEdit_Foerder_n`
   (Hint: „Förderbetrag (geldwerter Vorteil) erfasst werden“), dazu
   `NumEdit_Foerderbetrag_san` für die Sanierung in einem Zug (Hint: Förderung einer
   **Komplettsanierung auf EH-Niveau** — nicht die Summe der Paketförderungen, obwohl der
   Knopf „<- Summe“ genau das einträgt). Rechts optional „Detaillierte
   Kostendarstellung“ je Position (Invest/Sowieso/Förderung → `einzelPositionen`), Knopf
   „aus Wirtschaftlichkeit“ übernimmt die Variantenkosten. Alles Eingabefelder, kein
   `ReadOnly`.

Die Maske speichert **nicht in den Container**: ihre Texte und Beträge finden sich in
keiner der 9 Tabellen und in keiner SQL-Textspalte, sondern nur als XML — Autosicherung
`%APPDATA%\HSETU\EnergieberaterPlaner\AutoSicherungISFP\*_AS_/_MS_*.mSFPprojekt` und
`PrMedia.iSFP2.xml`. Invest und Sowieso kommen aus den Varianten (`Wirtschaft`-Zeilen,
je Position auf 100 € gerundet), der Förderbetrag nicht. Der Container speichert die
energiebedingten Mehrkosten, die XML die Sowieso-Kosten.

**Für den iSFP zählt nur der Reiter Kosten.** Jede Kosten- und Förderangabe in der
`iSFP2.xml` gehört zu einem Feld dieses Reiters; die Variantenkosten sind nur
Vorbelegung. Wer dort direkt einträgt, hat zwei auseinanderlaufende Stände — und
unsere Werkzeuge (`zeige-massnahmen.ps1`, Kostentool-Abgleich) lesen die Varianten.

Die spezifischen iSFP-Werte beziehen sich auf **`A_n`** (GEG-Nutzfläche), nicht auf
A_NGF oder Wohnfläche.

**Veraltete Ergebnisse erkennen:** `ibp-flach.exe` auf den `Kernel18599V5` zweier
Varianten, Monatswerte und Objektkennungen herausfiltern, `Compare-Object`. Sind die
Eingaben gleich, die Ergebnisse in `TableWasser`/`TableHeizung` aber nicht, ist eine
Variante nicht neu gerechnet worden. Die gespeicherten Ergebniszahlen allein zeigen
das nicht.

**Why:** Am 15.09.2026 bei Baumöhl so gefunden: MP2 wies 1.484 kWh
Warmwasser-Verteilverlust aus, MP3 5.403 kWh, bei wortgleichen Eingaben. Außerdem
widersprachen sich Modell und Kostentext zweimal (Lüftung zentral gegen „dezentral
5 Anlagen“, PV 11,8 gegen 10 kWp). Das fällt nur auf, wenn man beide Quellen
nebeneinanderlegt.

`enumHydraulicBalance`: 0 = kein Abgleich, 2 = mit (belegt im Beschreibungstext von
`Hsetu.EbCalc.IbpKernel`). Container während der Arbeit neu holen: der Nutzer speichert
oft mit, und `container.ps1` zeigt den Stand in der Datenbank.
