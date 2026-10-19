---
name: verbrauchsfaktor-energiekosten
description: "Der Verbrauchsabgleich sitzt im iSFP-Reiter Kosten hinter „berechnen\"; f_v skaliert nur die Heizung, der Warmwasser-Rest bleibt — und f_v wird nicht gespeichert"
metadata:
  node_type: memory
  type: reference
  originSessionId: 4f0538bd-ca70-49d8-9f49-7c802c435628
  modified: 2026-09-13T13:32:57.501Z
---

Die Frage „wo trage ich den echten Verbrauch meines Kunden ein" beantwortet sich
im **iSFP-Dialog → Reiter Kosten → Spalte Energiekosten → Knopf `berechnen`**.
Dahinter liegt der *Verbrauchsanpassungs- und Energiekosten-Rechner*:

```
Verbrauch = berechneter Bedarf Heizung × f_v  +  Rest (Warmwasser, unbereinigt)
Kosten    = Verbrauch × Arbeitspreis          +  Grundpreis
```

**Der Faktor greift nur auf die Heizung.** Der Warmwasser-„Rest" bleibt
unangetastet — ist er zu hoch angesetzt, muss f_v das über die Heizung
mitkompensieren und rutscht unplausibel tief.

**Die Preise sind brutto.** Gegenprobe: Rechnungs-Arbeitspreis 9,6230 ct netto ×
1,19 = 11,45 ct — genau der Wert im Dialog. Für einen privaten Eigentümer richtig.

**f_v wird nicht mitgespeichert.** Geprüft: kein Feld dafür im Container,
`Verbrauch_kWh` in allen Varianten leer, kein Schlüssel in `LookupData`. Nur das
**Ergebnis** landet im Export (`kennwerte_sfp/verbrauch`). Also notieren und nach
dem Wiederöffnen kontrollieren.

**Der Dialog übernimmt erst beim Fokusverlust.** Jedes Eingabefeld hängt an
`OnExit = NumEdit_Exit`, und der Dialog hat **kein „Übernehmen"**, nur „schließen".
Wer tippt und direkt schließt, verliert die Eingabe — und es sieht aus, als
ließe sich der Wert nicht ändern. **Nach dem Eintippen Tab drücken**, dann
schließen.

**Was gesperrt ist und was nicht:** `Verbrauch` und `Kosten` sind `ReadOnly` —
das sind Ergebnisse, die grauen Spalten. Beschreibbar sind `Grundpreis`,
`Arbeitspreis`, `berechneter Bedarf Heizung`, `Rest` und der Faktor selbst.
Auf dem Reiter Kosten wären die Verbrauchs- und Kostenspalten zwar von Hand
überschreibbar — aber ein getippter Wert dokumentiert seine Herleitung nicht und
überlebt kein `berechnen`. Immer über den Faktor gehen.

**How to apply:** Denselben f_v in **alle sechs Zeilen** eintragen (Ist + MP1–MP5).
Korrigierst du nur „Heute", sinkt der Ist-Verbrauch und die Pakete bleiben auf
Bedarfsniveau — die ausgewiesene Einsparung wird zu klein. Bei Wärmepumpen-Paketen
gehört laut Fußnote die nutzbar gemachte Umweltwärme in die Betrachtung.

**Wann f_v ein Symptom ist, kein Messwert:** Übliche Werte liegen bei 0,6–0,9.
Landest du bei 0,3, rechnet das Modell zu viel, statt dass der Kunde zu wenig
heizt. Dann zuerst die Anlagentechnik prüfen — Warmwasser-Zirkulation,
Leitungslängen und -lage, Dämmstufe unter einer Flächenheizung — und erst danach
abgleichen. Sonst bleiben die Hüllpakete und die Heizlast für die Wärmepumpe
verzerrt, auch wenn die Energiekosten am Ende passen
([[wirkungsprobe-statt-selbstpruefung]]).

Der Ort, an dem die Werte danach liegen: [[isfp-export-pruefen]].
