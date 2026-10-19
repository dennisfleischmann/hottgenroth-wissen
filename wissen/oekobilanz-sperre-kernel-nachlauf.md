---
name: oekobilanz-sperre-kernel-nachlauf
description: "Ökobilanz kann noch nicht genutzt werden / Energieberater-Berechnung fehlerhaft" nennt die Version, meint aber jede Ausnahme im Kernel-Nachlauf — und protokolliert nichts
metadata:
  type: project
---

Die Sperrmeldung der Ökobilanz (ECO-CAD, Modul LCA) lautet „Ökobilanz kann noch nicht
genutzt werden. / Energieberater-Berechnung fehlerhaft. / Projekt muss im Energieberater
neu berechnet werden." Der Ressourcenschlüssel heißt `ValidateError_InvalidEnergyConsultantVersion`,
**die Version ist aber selten die Ursache.**

Sie entsteht an genau einer Stelle — `ModelProjectValidator.ValidateProject`
(`Hsetu.EcoBilancing.LCA.BO.Integration`): einem nackten `catch` um
`energyConsultantCalculator.Update(); Calculate();`. `Calculate()` liest **nicht** den
gespeicherten Blob, sondern lässt `KernelCalculatorLca` und `KernelCalculator` im Prozess
**neu über das Modell laufen** und liest danach `Buildings.First().CR` aus. Jede Ausnahme
darin — fehlendes CalcResult, unvollständiges Modell — ergibt diese eine Meldung.
Das `catch` schreibt **kein** Protokoll: im Projektjournal (`PrJournalEntry`) steht nichts.

Der Versionsvergleich ist eine **getrennte**, nicht sperrende Prüfung
(`KernelVersionChecker`, nur eine Warnblase). Er vergleicht mit `Equals`, nicht „mindestens":
`SupportedKernelVersion = 4.99.797.0` in ECO-CAD 4.3.1.5. Der Stand des Projekts steht in
`PrMedia` mit `MediaName = 'Kernel18599V5.bin'` in `MediaVersion` — von außen prüfbar:

    SELECT MediaName, MediaVersion, DATALENGTH(Media) FROM PrMedia
    WHERE ProjectUUID = '…' AND MediaName LIKE '%Kernel%'

**`MediaSize` ist unbrauchbar** — steht fast überall auf 0, obwohl der Blob da ist. Immer
`DATALENGTH(Media)` nehmen.

Nach dem Kernel-Nachlauf prüft der Validator weiter, und diese Hürden kommen als
**nächste** Meldungen: BGF und NGF > 0, projizierte Dachfläche > 0, BGF ≥ NGF, gesetzter
Gebäudetyp, Bauteile mit Abmessung, und mindestens ein Katalogbauteil **mit Schichtaufbau**.
Ein U-Wert ohne Schichten trägt die Ökobilanz nicht — siehe [[bauteilspiegel-ist-die-kostengrundlage]].

Beim Neuberechnen im Energieberater gelten [[energie-exe-verwaiste-instanz]] und
[[container-ergebnisse-gehoeren-der-software]].
