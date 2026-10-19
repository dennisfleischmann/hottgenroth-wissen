# iSFP-Werkzeug

Füllt einen individuellen Sanierungsfahrplan in Hottgenroth, bevor er in die
Druckapplikation geht. Zwei Skripte, ein Ablauf.

## Der Weg eines iSFP

```
Energieberater (Energie.exe)        Sanierungsvarianten rechnen
        │
        ▼
iSFP-Erfassungsmaske                ← hier setzen die Werkzeuge an
        │                             (Speicherstand: PrMedia.iSFP2.xml, MediaType 11)
        ▼
MeinSanierungsfahrplan.exe          Druck; liest dieselbe Datei als .mSFPprojekt
```

Die Maske ist ein Delphi-Formular **innerhalb** von Energie.exe, keine eigene
Anwendung. Ihr Speicherstand ist `PrMedia.iSFP2.xml` — und das ist byte-gleich
mit der `.mSFPprojekt`-Datei, die die Druckapplikation öffnet. Beide Werkzeuge
schreiben dorthin.

## Ablauf

```powershell
cd C:\Projekte_Dev\energieberatung\isfp-werkzeug

# 0. Sanierungsvarianten stehen im Energieberater, iSFP-Maske einmal
#    geöffnet und gespeichert, Energie.exe geschlossen.

# 1. Anlagenkosten in den Container (nur wenn Anlagen im Spiel sind)
.\anlagenkosten-setzen.ps1 -Projekt 'Klenke' -Schreiben

# 2. Texte, Kurzbeschreibungen, Prinzipskizzen
.\isfp-texte-fuellen.ps1   -Projekt 'Klenke'              # Vorschau
.\isfp-texte-fuellen.ps1   -Projekt 'Klenke' -Schreiben

# 3. Stammdaten, Geld, Förderung — und die Prüfliste
.\isfp-fertigstellen.ps1   -Projekt 'Klenke'              # Vorschau
.\isfp-fertigstellen.ps1   -Projekt 'Klenke' -Schreiben

# 4. Was die Prüfliste nennt, in der Maske ergänzen. Dann drucken.

# jederzeit: eine fertige Datei nachprüfen, ohne etwas zu ändern
.\isfp-fertigstellen.ps1 -Datei 'C:\Users\...\Klenke_isfp.mSFPprojekt'

# 5. nach dem Druck: was in der Druckanwendung entstanden ist, zurückholen
.\isfp-fertigstellen.ps1 -Projekt 'Klenke' `
    -Uebernehmen 'C:\Users\...\Klenke_isfp.mSFPprojekt' -Schreiben
```

Schritt 5 ist kein Nachklapp, sondern nötig: **aus der Druckanwendung fließt
nichts von allein zurück.** Bei Klenke standen zehn Fotos in der
`.mSFPprojekt`-Datei und null im Hottgenroth-Projekt — ein „Erfassung
zurücksetzen" hätte sie alle gekostet. Was zurückgeholt wird, steht in
`stammdaten.json` unter `rueckuebernahme`; geschrieben wird nur dorthin, wo
Hottgenroth leer ist.

Die Prinzipskizzen sind bewusst **nicht** dabei: MeinSanierungsfahrplan rechnet
beim Speichern jedes Bild auf rund 300 px herunter (eine Fensterskizze ging von
2024 auf 296 px). Die Fassung in Hottgenroth ist die bessere — zurückholen würde
sie verschlechtern.

**Beide Anwendungen müssen geschlossen sein.** Energie.exe und
MeinSanierungsfahrplan halten ihren Stand im Speicher und schreiben ihn beim
Speichern zurück — was von außen dazwischenkommt, ist dann weg. Die Skripte
prüfen das und brechen ab.

## Die Dateien

| Datei | Inhalt |
|---|---|
| `isfp-texte-fuellen.ps1` | Texte aus den Bausteinen, je Bauteil und je Paket |
| `isfp-fertigstellen.ps1` | Stammdaten, Kostenpositionen, Förderung, Prüfliste |
| `anlagenkosten-setzen.ps1` | Anlagenkosten in `TableAnlage` des Containers |
| `zuordnung.json` | SANBEZ → Textbaustein, 22 Hüllregeln + Anlagenregeln |
| `stammdaten.json` | Büroangaben, Förderprogramme, Prüfschwellen |
| `anlagenkosten.json` | Anlagenkosten je Projekt und Paket |
| `stammdaten/` | Logo und Unterschrift als JPEG |
| `Textbausteine-…/` | die Bausteindateien des Büros |
| `Maßnahmenbilder-…/` | Prinzipskizzen |
| `laeufe/` | Sicherungen, entpackte Container, abgelegte `.mSFPprojekt` |

## Woher welche Angabe kommt

Gemessen am Abgleich Rohexport (358 Pfade) gegen fertigen Fahrplan (391 Pfade).
93 Feldarten kamen von Hand dazu; so verteilen sie sich heute:

| Herkunft | Wer füllt | Beispiele |
|---|---|---|
| Rechenmodell | Energie.exe selbst | Bilanz, Kennwerte, Anlagen, Komponentengerüst |
| Textbausteine | `isfp-texte-fuellen.ps1` | Anschreiben, Beschreibung, Zu beachten, Das bringt es, Skizzen |
| Büro | `isfp-fertigstellen.ps1` | BAFA-Nr., Anschrift, Logo, Unterschrift |
| Container | `isfp-fertigstellen.ps1` | Kostenpositionen, Investition, Sowieso, Förderung |
| Ortskenntnis | Berater, in der Maske | techDoku, Nutzereinfluss, Fotos |
| Knopf in der Maske | Berater | Energiekosten, Verbrauch (iSFP → Kosten → *berechnen*) |
| Druckanwendung | zurück per `-Uebernehmen` | Fotos, Bildzuschnitte, Unterschrift |

Die letzten beiden Zeilen kann kein Werkzeug liefern. Die Prüfliste am Ende von
`isfp-fertigstellen.ps1` zählt sie einzeln auf, mit Quelle.

## Bilder: zwei Sorten, zwei getrennte Wege

Das zu verwechseln kostet Arbeit — die beiden haben nichts miteinander zu tun.

**Fotos** (Titelbild, „Foto heute", Ansichten) liegen in `PrMedia`
(`MediaType` 14/15), gepflegt in der Bilderverwaltung von Hottgenroth. In der
`iSFP2.xml` steht nur das leere Gerüst; die Bytes setzt die Software erst ein,
wenn sie die `.mSFPprojekt` erzeugt. **In allen 59 Projekten der Datenbank ist
jeder Foto-Stream in der `iSFP2.xml` leer** — das ist der Normalzustand.

Am Bild hängen vier Angaben, und jede landet an einer festen Stelle:

| Spalte in `PrMedia` | in der Oberfläche | im iSFP |
|---|---|---|
| `XimMediaType` | **Funktion** | bestimmt, wohin das Bild geht |
| `Category` | Reihenfolge | Position innerhalb der Funktion |
| `ShortDesc` | Name | `titel` |
| `InfoDesc` | **Beschreibung** | `beschreibung` |
| `MediaCopyright` | Bildquelle | `bildquelle` |

Die Funktionen:

| `XimMediaType` | Bedeutung | Ziel im iSFP | Anzahl |
|---|---|---|---|
| 10 | Titelbild | `fotos/titel` | 1 |
| 12 | Foto heute | `fotos/fotoHeute/item` | 4 |
| 13 | Ansicht | `fotos/ansichten/item` | beliebig |
| 1 | Unterlage (Plan, Grundriss) | — | — |
| 0 | ohne Funktion | **erscheint nirgends** | — |

An Messinger und Bieche Feld für Feld nachgewiesen.

**Prinzipskizzen** je Maßnahme sind etwas ganz anderes: sie werden in der
iSFP-Maske oder in der Druckanwendung hochgeladen und liegen **direkt** in der
`iSFP2.xml`. `isfp-texte-fuellen.ps1` füllt sie aus dem Ordner
`Maßnahmenbilder`.

`isfp-fertigstellen.ps1` schreibt an Fotos nichts — es zeigt unter *Bilder in
Hottgenroth* nur, welchem Bild Funktion, Name oder Beschreibung fehlt.

## Zwei Regeln, die Zeit gekostet haben

**Komponenten nicht neu bauen.** `sanierungskomponenten` erzeugt die Maske aus
dem Modell. Ein Entwurf, der sie von außen aufgebaut hat, ist daran gescheitert:
beim nächsten Öffnen waren sie wieder weg. Die Werkzeuge füllen deshalb
*vorhandene* Komponenten, sie legen keine an. `einzelPositionen` sind das
Gegenteil — im Rohexport null Stück, also reine Dialogdaten, die von außen
geschrieben werden dürfen.

**Kein `¶` in die XML.** Die Bausteindateien trennen Absätze mit U+00B6. In 39
echten Exporten kommt das Zeichen kein einziges Mal vor: dort steht `<br>` in
`beschreibung` und `zu_beachten`, sonst ein Zeilenumbruch. Ungewandelt wird das
Zeichen wörtlich gedruckt. `isfp-texte-fuellen.ps1` räumt am Ende jedes Laufs
über alle Textknoten auf, `isfp-fertigstellen.ps1` meldet Reste.

## Beim Ändern der Skripte

Windows PowerShell 5.1 liest eine `.ps1` ohne Byte Order Mark als ANSI — aus
`Maßnahmenbilder` wird dann `MaÃŸnahmenbilder`, und der Bilderordner wird nicht
gefunden. Nach jeder Änderung neu speichern:

```powershell
$p = '.\isfp-fertigstellen.ps1'
$t = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($true)))
```
