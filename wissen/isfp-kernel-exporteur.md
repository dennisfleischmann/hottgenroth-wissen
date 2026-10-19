---
name: isfp-kernel-exporteur
description: "Die iSFP-XML kann eine Bibliothek schreiben — CreateCertificateSFP im IBP-Kernel, COM-sichtbar — aber die installierte Fassung ist eine Schemageneration zurück"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 815a2566-49de-45b5-a8a5-5e058405e4d5
  modified: 2026-09-13T11:33:52.829Z
---

`IBP18599kernelOutputTemplates.dll` (Fraunhofer IBP, **4.99.797.0**, unter
`C:\Program Files\HSETU\Energieberater2022\`) enthält die komplette iSFP-Ausgabe —
`[ComVisible(true)]`, `[ClassInterface(AutoDual)]`, also headless und aus PowerShell
aufrufbar:

    TiSFPProjekt CreateCertificateDataObjectFromBuildingResidential(DIN18599Building)
    void         AddModernisation(TiSFPProjekt, TMassnahmenpaket, DIN18599Building)
    string       ValidateCertificateXml(string pFilename)
    bool         WriteCertificateXML(TiSFPProjekt, string pFilename)

Sie setzt am `DIN18599Building` an — demselben Modell, das je Variante als
[[din18599-anlagentechnik-ibp-blob]] in `TableZusatz.Kernel18599V5` liegt.
`TransferBuildingDataSFP` darin ist die vollständige Abbildung Rechenmodell → iSFP-Feld
(`tBilanzKennwerteAllgemein.A_huelle = mm.Residential.fA` usw.) und damit auch dann eine
Quelle, wenn man die Kennwerte selbst ableitet.

**Die Einschränkung — am 26.09.2026 per Reflexion nachgemessen** (Fassung unverändert
4.99.797.0 in *allen drei* Installationen, obwohl `Energie.exe` inzwischen 14.0.0.8 ist):
`TBilanzKennwerteAnlageHZ` kennt `JAZ`, `ETA_s35`, `ETA_s55`, `kollektorflaeche` **nicht**
und heißt `art` statt `technik`; `TBilanzKennwerteAllgemein` fehlen `ANGF` und
`energieeffizienzklasse`. `A_huelle`, `AN` und `H_T` sind dagegen **vorhanden**.
Ein echter Export aus Energieberater 13.5.0 führt jedes davon sechsmal (Ist + fünf
Maßnahmenpakete). Und `ValidateCertificateXml` prüft gegen `InputFiles/TiSFPProjekt.xsd` —
ausgerechnet die Fassung von 2022, die laut Regel IS-06 nicht mehr gilt. Wer die
Bibliothek ruft, bekommt eine Datei, die die heutige Druckapplikation als unvollständig
ansieht.

Ob die native `Energie.exe` diese Felder selbst füllt oder ob es irgendwo eine neuere
Kernel-DLL gibt, ist **ungeklärt** — auf dieser Maschine liegt nur die eine Fassung.

**Nicht verwechseln:** `TFWProjectMediaISFPHelper` ist die einzige weitere Klasse mit
„ISFP" im Namen und exportiert nichts — sie sammelt die **Bilder** fürs iSFP und das
Beraterlogo.

Verwandt: [[hsetu-dekompilierter-korpus]], [[isfp-webformular-stand]], [[isfp-drei-stufen]]
