---
name: container-vorschau-braucht-zurueck
description: container.ps1 -Vorschau wirkt nur zusammen mit -Zurueck; allein holt es neu und überschreibt den Arbeitsordner
metadata:
  type: project
---

`container.ps1 -Vorschau` **ohne** `-Zurueck` fällt in den Holen-Zweig: es lädt
den Container erneut aus der Datenbank und entpackt mit `-Force` darüber. Ein
mit `setze-kernel.ps1` eingesetzter Blob im Arbeitsordner ist danach weg. Der
Kopfkommentar des Skripts („zeigt, was sich geändert hat, schreibt aber nicht")
sagt das nicht — die Abfrage auf `$Vorschau` steht erst im Zurueck-Zweig.

**Why:** Am 26.09.2026 beim Projekt Klenke passiert. Kein Schaden, weil der
Blob (`b4.bin`) außerhalb des Ordners lag — aber `setze-kernel.ps1` musste neu
laufen. Wer die Zwischenstände im Arbeitsordner hält, verliert sie.

**How to apply:** Immer `-Zurueck -Vorschau` zusammen aufrufen. Das baut
`eberater-NEU.zip`, nennt die geänderten Tabellen und kehrt **vor** dem UPDATE
um. Die gebauten Blobs außerhalb von `arbeit/` ablegen. Siehe
[[leitungslage-nicht-im-austauschformat]].
