# `.BDExit` — Leser, Schreiber und Variantenerzeuger

Werkzeuge für den Energieberater-Container `eberater.zip` aus `PrMedia`.
Das Format ist vollständig entschlüsselt; die Beschreibung steht in
[`../../SANIERUNGSVARIANTEN.md`](../../SANIERUNGSVARIANTEN.md), Abschnitt 8.

## Die Bausteine

| Datei | Zweck |
|---|---|
| `bde.ps1` | Kopf lesen: Feldliste mit Typ und Breite, Satzzahl, Datenanfang, Autowert |
| `satz.ps1` | **Satz feldweise lesen und neu aufbauen** — das Kernstück |
| `variante-bauen.ps1` | legt eine vollständige Sanierungsvariante an |
| `saniere.ps1` | setzt `SANK_ZAHL` für **alle Bauteile einer Art** in einer vorhandenen Variante |
| `sanieren.ps1` | setzt `SANK_ZAHL` über einen Anker (Vorläufer, siehe unten) |

```powershell
.\saniere.ps1 -Ordner .\akt -Proj 5 -Kennzeichen DA -Wert 0.14
```

Kennzeichen: `DA` Dach · `WA` Außenwand · `FA` Fenster · `TA` Außentür ·
`BA` Bodenplatte · `BE` Kellerdecke · `WE` Wand gegen unbeheizt · `WK` Wand kalt.

Legt `SANK_ZAHL` an, wo es fehlt, und schreibt dabei den **gesamten Datenteil** der
Tabelle neu — die Satzlänge ändert sich ja. Die Satzzahl bleibt gleich, ein Bauteil
wird nicht dupliziert.

`bdexit2.ps1`, `bdread.ps1` und `scan.ps1` sind frühere Anläufe. Sie sind an drei
Stellen falsch — Feldnamen mit einem Zeichen brechen sie ab, `AUTOINCVALUE` wird nicht
zum Kopf gezählt, und die Feldbreiten stimmen nur teilweise. **`bde.ps1` ersetzt sie.**

`sanieren.ps1` arbeitet mit festen Abständen hinter dem Bauteilnamen. Das trägt nur
bei Bauteilen, die `SANK_ZAHL` bereits besitzen, und nur bei deren Satzbild — bei
Fenstern findet es still nichts. Für neue Arbeiten `satz.ps1` verwenden.

## Kurzform

```powershell
. .\bde.ps1
. .\satz.ps1

$b = [System.IO.File]::ReadAllBytes('TableHuellfl.BDExit')
$k = BdeKopf $b

# fortlaufend lesen - Satzgrenzen ergeben sich dabei, nichts wird geraten
$o = $k.Daten
while ($o -lt $b.Length) {
    $r = BdeLies $b $k $o -1
    ($r.Werte | Where-Object Name -eq 'K_ZAHL').Wert
    $o = $r.Ende
}

# aendern: vorhandene Felder setzen, fehlende ANLEGEN
$neu = BdeSchreib $b $k $r @{ SANK_ZAHL = 0.95 }
```

Prüfstein vor jedem Schreiben: einen Satz unverändert neu aufbauen und mit dem
Original vergleichen. Ist er nicht Byte für Byte gleich, stimmt die Deutung nicht —
dann nicht schreiben.

## Variante anlegen

```powershell
.\variante-bauen.ps1 -Ziel .\neu -Name 'Variante_Fenster18' -VonProj 3 -NeuProj 4 -Fenster 0.95
```

Baut aus `SICHERUNG-eberater-original.zip` einen Container mit einer zusätzlichen
Variante: je ein Satz in sieben Tabellen, alle Bauteile geklont, die Fenster mit
neu angelegtem `SANK_ZAHL`. Am Ende liest das Skript jede Tabelle noch einmal
vollständig durch — läuft das durch, ist der Container in sich stimmig.

## Vor dem Zurückschreiben

**`Energie.exe` muss geschlossen sein.** Die Software hält den Container im Speicher
und überschreibt beim nächsten Speichern kommentarlos. Ein Fenster ohne sichtbares
Fenster zählt auch — einmal lief eine verwaiste Instanz 34 Stunden lang und hat jeden
Schreibvorgang stillschweigend rückgängig gemacht.

```powershell
if (Get-Process -Name Energie -ErrorAction SilentlyContinue) { throw 'laeuft noch' }
```

## Sicherung

`SICHERUNG-eberater-original.zip` (75.770 Bytes) hält den Stand des Testprojekts
„Werner Grotz" vor dem ersten Eingriff. Die einzelnen `.BDExit` daneben sind dessen
entpackter Inhalt.

## Maßnahmen hinterlegen — `setze-massnahme.ps1`

`saniere.ps1` setzt nur `SANK_ZAHL`. Zu einer Sanierungsmaßnahme gehören **acht**
Felder, und ohne sie bleibt die Wirtschaftlichkeitstabelle leer:

| Feld | |
|---|---|
| `SANBEZ` | Bezeichnung — ohne sie ist die Zeile in der Wirtschaftlichkeit namenlos |
| `SANK_ZAHL` | Ziel-U-Wert |
| `SANKOSTENQM` · `SANKOSTEN` | Kosten je m² und gesamt |
| `SANKOSTENQM_EE` · `SANKOSTEN_EE` | energiebedingte Mehrkosten |
| `SANDICKE` · `SANLAMBDA` | Dämmstoff |

```powershell
.\setze-massnahme.ps1 -Ordner .\entpackt -Proj 19 -Kennzeichen WA `
     -Bauteile 'AW 003*','AW 006*','AW 001-2*','AW 004-2*' `
     -Bezeichnung 'WDVS Außendämmung, WLS035 12cm' `
     -ZielU 0.19 -KostenQm 266 -MehrkostenQm 109 -Dicke 12 -Lambda 0.035
```

**Zwei Dinge, die das Skript von `setze-bauteilfeld.ps1` unterscheiden.**

*Die Sowieso-Kosten stehen nirgends.* Sie sind `SANKOSTEN − SANKOSTEN_EE`; die
Software bildet sie daraus. Wer nur `SANKOSTEN` setzt, bekommt eine Maßnahme, die
zu 100 % als energiebedingt gilt — und damit eine zu hohe Förderung im iSFP. Ohne
`-MehrkostenQm` ist genau das gewollt (Kellerdämmung, Perimeterdämmung), sonst
muss der Wert mit.

*Die Auswahl geht über Bauteilmuster, nicht nur über das Kennzeichen.* An einem
Kennzeichen hängen oft mehrere Maßnahmen: im Projekt Messinger tragen die
`WA`-Bauteile „WDVS Außendämmung" (266 €/m²) **und** „WDVS Kellerwand" (289 €/m²).
Ein Aufruf je Kennzeichen würde beide gleich setzen.

**Bezugsfläche ist `FLAECHE_BR`** (brutto), nicht `FLAECHE` (netto nach Abzug von
Fenstern und Türen). An 33 Bauteilen geprüft: `SANKOSTEN / SANKOSTENQM` trifft
`FLAECHE_BR` auf die zweite Stelle. Fehlt das Feld, rechnet das Skript mit der
Nettofläche und sagt es.

`-Vorschau` zeigt Treffer und Beträge, ohne zu schreiben. `-Loeschen` nimmt die
Maßnahme wieder zurück. Nach dem Schreiben wird die Tabelle neu eingelesen und
jeder Treffer gegengeprüft.

**Die Kette für ein neues Paket:**

```
variante-bauen.ps1      Variante anlegen + Name (VarianteBez)
setze-massnahme.ps1     Bezeichnung, Ziel-U, Kosten, Mehrkosten
uwerte-uebernehmen.ps1  U-Werte ins Rechenmodell — sonst zeigt die Variante
                        sanierte Werte und rechnet mit den alten
pruefe-variante.ps1     Gegenprobe
```

## Container holen und zurückschreiben — `container.ps1`

Der Weg in die Datenbank und zurück, mit den vier Regeln eingebaut, an die man
sonst jedes Mal einzeln denken muss.

```powershell
.\container.ps1 -Projekt 'Messinger' -Ordner .\arbeit
# ... variante-bauen.ps1 · setze-massnahme.ps1 · uwerte-uebernehmen.ps1 ...
.\container.ps1 -Projekt 'Messinger' -Ordner .\arbeit -Zurueck
```

1. **Energie.exe muss beim Zurückschreiben zu sein.** Das Skript bricht sonst ab
   und nennt die PID. Ein Prozess ohne Fenster zählt auch.
2. **Beim Holen wird gesichert** — `eberater-ORIGINAL.zip` samt SHA-256. Fehlt die
   Sicherung, wird nicht zurückgeschrieben.
3. **Prüfstein vor dem Schreiben**: jede der neun Tabellen wird Satz für Satz
   durchgelesen und gegen die Satzzahl im Kopf gehalten.
4. **Gegenprobe danach** aus der Datenbank, nicht aus dem Speicher.

Ersetzt werden nur Tabellen, deren Bytes sich geändert haben. Ein mehrdeutiger
Projektname wird abgewiesen, statt das falsche Projekt zu treffen.

## Maßnahmen auslesen — `zeige-massnahmen.ps1`

```powershell
.\zeige-massnahmen.ps1 -Ordner .\arbeit
.\zeige-massnahmen.ps1 -Ordner .\arbeit -Proj 21 -JeBauteil
.\zeige-massnahmen.ps1 -Ordner .\arbeit -Csv .\massnahmen.csv
```

Je Variante: Maßnahme, Bauteile, Bruttofläche, Ziel-U-Wert, Gesamtkosten,
**Sowieso-Kosten**, **energiebedingte Mehrkosten** — und der Zuwachs gegenüber dem
vorangehenden Paket, denn die Beträge in der Tabelle sind kumulativ, die
Investition eines Maßnahmenpakets im iSFP ist die Differenz.
