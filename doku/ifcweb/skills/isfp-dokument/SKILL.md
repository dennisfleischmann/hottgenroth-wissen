---
name: isfp-dokument
description: Das iSFP-Dokument selbst - Massnahmen, U-Werte Ist und Ziel, Investitions- und Sowieso-Kosten, Foerderung, BAFA-Nummern. Ausloeser - Sanierungsfahrplan, iSFP, Massnahmenpaket, Kosten, BAFA, Foerderung, Uwert Ziel.
erprobungsstand: gefunden-nicht-vermessen
---

**Stand:** Der Ablageort ist **gefunden**, der Inhalt **nicht vermessen**. Lesen
ist unbedenklich. **Schreibe hier nicht**, bevor der Messzyklus gelaufen ist —
welches Feld die Software woraus ableitet, ist offen.

## Wo es liegt

Als XML-Blob in `PrMedia`, gegen ein veröffentlichtes XSD:

```
<iSFP-Projekt XSDVersion="2020-02-07">
  <software_name>Energieberater</software_name>
  <bafa_berater_nr>…</bafa_berater_nr>
  <bafa_vorgangs_nr>…</bafa_vorgangs_nr>
  <rechtsGrundlage>RGL_GEG2024</rechtsGrundlage>
  <enev_verfahren>EV_DIN18599</enev_verfahren>
  <eigentuemer>…</eigentuemer>
```

In dieser Datenbank führen **12 Projekte** ein solches XML, 61 KB bis 7,3 MB. Der
Eigentümer im XML ist der Kontakt des Projekts — dass er woanders wohnt als die
Liegenschaft, ist normal und kein Fehler.

Enthalten sind unter anderem, je Bauteil beziehungsweise Maßnahme: `uwert_ist`,
`uwert_ziel`, `maxUwert_kfw`, `maxUwert_enev`, `flaeche` · `investitionsKosten`,
`sowiesoKosten`, `foerderung` · `prinzipskizzen`, `zu_beachten`,
`erlaeuterung_sanierungsvorschlag_nicht_moeglich` · Energieträger mit
`primaer_faktor`, `co2_faktor`, `deckung`.

## Was als Nächstes zu klären ist

1. Ist das XML **Quelle oder Ausgabe**? Rechnet die Software daraus, oder schreibt
   sie es beim Erzeugen des Fahrplans aus dem 18599-Modell heraus? Davon hängt
   alles ab — bei Ausgabe wäre Hineinschreiben wirkungslos.
2. Wie hängen `uwert_ziel` und `investitionsKosten` mit den Sanierungsvarianten in
   der `eberater.zip` zusammen? Dort steht `SANK_ZAHL` und `SANKOSTEN_*`.
3. Trägt das XML einen Zeitstempel, der zum letzten Speichern passt, oder bleibt
   es stehen, bis der Fahrplan neu erzeugt wird?

Der Zyklus dafür steht in `skills/messen/SKILL.md`: einen Schritt im Fahrplan
ändern, speichern, vergleichen. `Snapshot-Projekt.ps1` legt die PrMedia-Blobs
schon als Dateien ab — der Blob-Hash im Vergleich zeigt sofort, ob das XML
mitgeschrieben wurde.
