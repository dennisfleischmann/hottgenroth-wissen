---
name: erzeugtes-powershell-zwei-fallen
description: "Zwei Syntaxfallen in serverseitig erzeugten PowerShell-Befehlen (Backtick, Operator am Zeilenanfang) plus die Stelle, an der get_vorgang die erreichte Schrittzahl herholt"
metadata: 
  node_type: memory
  type: reference
  originSessionId: ae8bce80-85eb-4f60-a580-6d1572a7c232
  modified: 2026-09-30T05:12:36.458Z
---

Am 30.09.2026 gefunden an Vorgang 191 (`heizung.lesen`), Abbruch in Schritt 1 von 5.
Beide Fallen brechen das **ganze** Skript am Parser — also auch den Zweig, der gar
nicht laufen sollte —, und beide waren an drei Stellen gleichzeitig eingebaut.

**1. Der Backtick gehört nur in eine doppelt geführte Zeichenkette.** `` `n `` war
in PHP als `implode(',`n    ', …)` geschrieben — in einfachen Anführungszeichen ist
das kein Zeilenumbruch, sondern das Zeichenpaar Backtick + n. Im Quelltext des
Skripts ist der Backtick das Escape-Zeichen: „Ausdruck nach "," fehlt". Für einen
echten Umbruch in erzeugtem Code `"\n"` nehmen, `` `n `` nur **innerhalb** von `"…"`.

**2. Der Verkettungs-Operator steht am ZEILENENDE.** PowerShell beendet den
Ausdruck am Zeilenumbruch, auch innerhalb von Klammern. `Write-Error ("a"` +
Folgezeile `+ "b")` ist deshalb ein Syntaxfehler; richtig ist `"a" +` am Zeilenende.

**Wo geprüft:** `tests/Feature/Ai/PowerShellHilfen.php` liest jeden
`shell.run`-Befehl als PowerShell und prüft genau diese zwei Regeln, samt
Selbstprobe, dass der Wächter noch beißt. Jeder neue Auftragstyp mit `shell.run`
hängt sich das Trait ein — sonst prüft keine Probe den Befehl als Sprache
([[auftraege-mit-shell-run]]).

**Und der Nachbar-Fehler:** `get_vorgang` meldete „ungewiss", obwohl belegbar
nichts geschrieben war. `meta.schreibt_ab` stand richtig; die **erreichte**
Schrittzahl kam aber aus `progress_message`, und die überschreibt jede weitere
Meldung des Agenten („Exit-Code 1, …"). Seit dem 30.09.2026 liest die Deutung sie
aus dem Protokoll. Ältere Vorgänge mit `shell.run` können deshalb ein falsches
„ungewiss" tragen.
