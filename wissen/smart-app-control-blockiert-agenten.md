---
name: smart-app-control-blockiert-agenten
description: "Auf neuen Windows-11-Rechnern blockiert Smart App Control den Hottgenroth-Agenten und meldet irrefuehrend \"Device Guard-Richtlinie Ihrer Organisation\""
metadata: 
  node_type: memory
  type: project
  originSessionId: 43095ec6-5f0f-4c36-9938-758f4e455036
  modified: 2026-10-01T14:27:26.071Z
---

Beim Einrichten des Hottgenroth-Agenten auf dem Arbeitsplatz von Tonio Wichmann
(01.10.2026) blockierte Windows erst `install.ps1` („Eine Anwendungsrichtlinie hat
diese Datei blockiert"), dann die EXE selbst:

> 'hottgenroth-agent.exe' wurde durch die **Device Guard-Richtlinie Ihrer Organisation**
> blockiert.

**Die Meldung lügt über die Ursache.** Es war keine Unternehmensrichtlinie, kein
AppLocker, kein Dienstleister — es war **Smart App Control**, das auf neu
aufgesetzten Windows-11-Rechnern von sich aus eingeschaltet ist und alles blockiert,
was Microsoft nicht als bekannt-und-vertrauenswürdig führt. Unsignierte Firmensoftware
fällt immer darunter.

**Die eine Zeile, die es beweist** (PowerShell, ohne Admin):

```powershell
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -Name VerifiedAndReputablePolicyState
```

`1` = an und erzwingend, `0` = aus, Fehler = gar nicht vorhanden. Abschalten unter
*Windows-Sicherheit → App- und Browsersteuerung → Intelligente App-Steuerung →
Einstellungen → Aus*. **Einbahnstraße:** wieder einschalten geht nur mit einer
Windows-Neuinstallation.

**Was in die Irre führte, damit es nicht noch einmal passiert:**

- `Win32_DeviceGuard` meldet `UsermodeCodeIntegrityPolicyEnforcementStatus = 2`
  (erzwungen) — das sagt Smart App Control und Unternehmensrichtlinie gleichermaßen.
- Neun `.cip`-Dateien unter `CodeIntegrity\CiPolicies\Active` sehen nach Firmenpolitik
  aus; die meisten bringt Windows selbst mit.
- `citool -lp` braucht Adminrechte, sonst nur `0x80070005`.
- Das Protokoll `Microsoft-Windows-CodeIntegrity/Operational` war beschädigt und gab
  nichts heraus; `wevtutil cl <Name>` legt es neu an, danach den Block erneut auslösen.
- **Der Registry-Wert hätte als erstes gefragt gehört** — er kostet eine Zeile und
  beendet die Suche.

Ab dem Abschalten läuft der normale Weg: `Einrichten.cmd` doppelklicken, als der
Benutzer, **nicht** als Administrator (siehe [[hottgenroth-agent-testaufbau]]).
Erhöhen hilft gegen Smart App Control ohnehin nicht, und mit einem fremden
Admin-Konto landet die Installation im falschen Profil — dann sieht der Agent die
benutzergebundene `(localdb)\HSETU` nicht.

Vorher in `/admin/users`: Rolle `berater` **und** das MCP-Recht
`hottgenroth:arbeitsplatz`. Die Rolle allein gibt das Recht nicht, sie erlaubt nur,
es zu haben; ohne beides endet die Browser-Anmeldung mit `400`.
