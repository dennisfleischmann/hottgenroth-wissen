# Werkzeuge für den DIN-18599-Objektgraph

Drei kleine Programme, um `Kernel18599V5.bin` zu lesen und zu ändern — den
BinaryFormatter-Strom, in dem die Anlagentechnik der DIN-18599-Berechnung liegt.
Hintergrund und Belege in [`../../DIN18599-ANLAGENTECHNIK.md`](../../DIN18599-ANLAGENTECHNIK.md).

Alle drei sind **.NET Framework 4.8, x64**. Das ist keine Bequemlichkeit: den
`BinaryFormatter` gibt es in .NET 10 nicht mehr, und die IBP-Assemblies sind
Framework-Assemblies. Sie laden `DIN18599DataModel.dll` über einen
`AssemblyResolve`-Handler aus `C:\Program Files\HSETU\Energieberater2022`.

## Bauen

```powershell
$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
& $csc /nologo /platform:x64 /out:ibp-dump.exe      IbpDump.cs
& $csc /nologo /platform:x64 /out:ibp-roundtrip.exe IbpRoundtrip.cs
& $csc /nologo /platform:x64 /out:ibp-add-boiler.exe IbpAddBoiler.cs
```

## Benutzen

```powershell
# Was steht drin? Vorgabe sind die Geraetesammlungen.
ibp-dump.exe beispiel-kernel18599.bin

# Tiefer, und andere Aeste:
ibp-dump.exe blob.bin 2 "Zones,UnitHeating,CircuitHeatWater"

# Aendert das Baujahr des ersten Erzeugers und schreibt in eine NEUE Datei.
ibp-roundtrip.exe blob.bin blob-neu.bin

# Legt einen zweiten Kessel ueber die Fabrik an und haengt ihn an den Pooltyp.
ibp-add-boiler.exe blob.bin blob-plus.bin
```

Keines der Programme schreibt in seine Eingabedatei oder in die Datenbank. Wer den
geänderten Blob zurück ins Projekt bringen will, tut das selbst — und an einer Kopie
des Projekts, nicht am Original.

## Was die drei zeigen

| Programm | beantwortet |
|---|---|
| `ibp-dump` | Was steht im Graphen? Welche Geräte, welche Werte? |
| `ibp-roundtrip` | Übersteht eine Änderung das Serialisieren? (ja) |
| `ibp-add-boiler` | Lässt sich ein Gerät anlegen und korrekt verdrahten? (ja, über `NewGeneratorBoiler`) |

## Fallstricke, die schon eingesammelt sind

- **`IBPHashtable` ist keine `IDictionary`.** Eigene Klasse mit `Count`, Indexern
  `this[int]`/`this[string]` und `Add(string, object)`. Ein `as IDictionary` liefert
  `null`.
- **Die Werte sind Eigenschaften, keine Felder** — und sitzen teils auf Basisklassen.
  Reflexion muss die Kette absuchen und beides prüfen.
- **Nichts von Hand zusammenstecken.** Für Geräte, Einheiten, Kreise, Zonen und
  Bauteile gibt es Fabrikmethoden (`NewGeneratorBoiler`, `NewUnitHeating`,
  `NewCircuitHeatWater`, `NewZone`, `NewConstruction` …). Sie setzen Kennungen und
  Querverweise selbst; das Setzen von `Generator` trägt `strGeneratorID` nach.
- **Objektverweise überleben die Serialisierung als Identität**, nicht als Kopie.
  Zwei Komponenten, die auf denselben Erzeugertyp zeigen, tun das nach dem Neuladen
  immer noch.

## Sammlungen ändern — `ibp-sammlung`

`ibp-feld-setzen` bricht ab, sobald ein Pfad auf einer Sammlung endet. Dafür gibt es
dieses Werkzeug. Gebraucht wird es für **Verweislisten**, allen voran `AmbientZone`:
ein Rohr trägt `enumAmbientType = 2` („in Zone"), und *welche* Zone gemeint ist, steht
als Objektkennung in einer `IBPArrayList` daneben.

```powershell
$p = "CircuitHeatWater[0].Distributions[0].Pipes[2].AmbientTemperature.AmbientZone"
ibp-sammlung.exe k.bin -       $p                                    # zeigen
ibp-sammlung.exe k.bin neu.bin $p anhaengen "P0Zone_1[E9BB54E1]"     # Zone eintragen
ibp-sammlung.exe k.bin neu.bin "CircuitDHW[0].Distributions[0].Pumps" entfernen 0
ibp-sammlung.exe k.bin neu.bin $p leeren
```

**Der Schalter allein genügt nicht.** Wer `enumAmbientType` auf 2 setzt und die Liste
leer lässt, bekommt ein Modell, das „in Zone" behauptet und die Verluste trotzdem
niemandem gutschreibt: `P58Calculator.AddUpSinksAndSourcesZone` steigt bei einem leeren
Eintrag wortlos aus. Immer beides setzen — erst anhängen, dann den Schalter.

Beim Entfernen aus `Pumps` bleibt der Pumpen**typ** im Vorrat (`P58CircuitPumps`)
stehen; nur der Verweis der Verteilung verschwindet. Ob die Software den
`iReferenceCount` selbst nachzieht, ist offen — nach dem Zurückschreiben prüfen.
