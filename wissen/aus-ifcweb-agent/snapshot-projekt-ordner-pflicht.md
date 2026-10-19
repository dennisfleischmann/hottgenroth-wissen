---
name: snapshot-projekt-ordner-pflicht
description: "$PSScriptRoot in einer Parametervorgabe wirft gerade unter powershell.exe -File -- Snapshot-Projekt.ps1 brach deshalb in jedem Agentenlauf ab"
metadata:
  type: project
  stand: gemessen
---

Snapshot-Projekt.ps1 trug als Vorgabewert `[string]$Ordner = (Join-Path $PSScriptRoot "snapshots")`. Ueber das Werkzeug projekt_aufnehmen brach das Skript mit Rueckgabewert 1 ab, BEVOR irgendetwas aufgenommen war: $PSScriptRoot war leer, Join-Path warf.

Der Ausloeser ist nicht "das Skript laeuft nicht als Datei" -- es ist das Gegenteil. Dieselbe Datei wirft **gerade dann**, wenn sie ueber `powershell.exe -File ...` gestartet wird; ueber `& .\Snapshot-Projekt.ps1` laeuft derselbe Vorgabewert anstandslos. Bedingung ist ein fortgeschrittener Parameterblock: sobald `[Parameter(...)]` oder `[CmdletBinding()]` im Spiel ist, wertet PowerShell die Parametervorgaben in der Bindephase aus -- vor dem Setzen von $PSScriptRoot. Im einfachen Parameterblock ohne Attribute laeuft dieselbe Vorgabe unter -File durch.

Daraus erklaert sich das Fehlerbild: jeder Handtest bestand (das Beispiel im Skriptkopf ruft mit `.\` auf), jeder Agentenlauf fiel (die Bruecke ruft ausschliesslich mit -File auf). Ein Fehlschlag, der sich beim Nachstellen von Hand nicht zeigt.

Inzwischen erledigt: Snapshot-Projekt.ps1 hat `[string]$Ordner = ''` und belegt im Rumpf nach -- `if (-not $Ordner) { $Ordner = Join-Path $PSScriptRoot "snapshots" }` (Zeile 41). -Ordner muss also nicht mehr mitgegeben werden. Kein zweites Skript in bauteile/tools zeigt dasselbe Muster (alle 20 geprueft).

Die Regel dahinter: **$PSScriptRoot nie in einer Parametervorgabe verwenden** -- leer vorgeben und im Rumpf nachbelegen.

**Beleg:** 21.08.2026, Projekt Test0001, PowerShell 5.1.26100.9168: projekt_aufnehmen ohne -Ordner liefert Rueckgabewert 1 und "Join-Path : Das Argument kann nicht an den Parameter Path gebunden werden, da es sich um eine leere Zeichenfolge handelt" -- damals Snapshot-Projekt.ps1 Zeile 18: `[string]$Ordner = (Join-Path $PSScriptRoot "snapshots")`. Mit -Ordner C:\Projekte_Dev\energieberatung\bauteile\tools\snapshots lief derselbe Aufruf durch: 271 Zeilen, 36 Tabellen. Anschliessend wurden beide Aufrufwege gegeneinander nachgemessen: dieselbe Datei wirft ueber `-File` und laeuft ueber `& ./skript.ps1`; mit Parameterblock ohne Attribute laeuft auch `-File`.

**Nicht gemessen:** Die Begruendung ueber die Bindephase ist aus dem Vergleich beider Aufrufwege geschlossen, nicht aus PowerShell-Quelltext oder Doku belegt -- gemessen ist, DASS die Kombination aus `-File` und fortgeschrittenem Parameterblock wirft. Ebenfalls geschlossen ist die Verallgemeinerung zur Regel: nachgeprueft sind nur PowerShell 5.1.26100.9168 auf diesem Rechner und die 20 Skripte in bauteile/tools, von denen sonst keines das Muster zeigt.

**Why:** Der Abbruch trifft die Vorher-Aufnahme -- den Schritt, den man am ehesten als erledigt abhakt. Wer die Meldung ueberliest, aendert ohne Vergleichsstand und kann hinterher nichts mehr nachweisen. Dazu die Tarnung: von Hand nachgestellt bestand der Aufruf jedes Mal, der Fehler wirkte wie ein Phantom des Agenten. Genau solche Fehler bleiben lange liegen.

**How to apply:** In eigenen Skripten $PSScriptRoot niemals in einer Parametervorgabe verwenden -- leer vorgeben, im Rumpf nachbelegen; das gilt fuer jedes Skript mit `[Parameter(...)]` oder `[CmdletBinding()]`. Wer einen Fehlschlag nachstellt, der nur im Agentenlauf auftritt, ruft mit `powershell.exe -File` auf und nicht mit `& ./skript.ps1`, sonst reproduziert er ihn nicht. Nach projekt_aufnehmen weiterhin pruefen, dass Zeilen gemeldet wurden, statt den Erfolg anzunehmen.
