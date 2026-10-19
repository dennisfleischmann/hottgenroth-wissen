---
name: hsetu-offline-14-tage
description: "HSETU-Vollversion holt die Lizenz online, arbeitet danach genau 14 Tage aus dem verschlüsselten Offline-Speicher weiter"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 8d7ab468-e4e1-42b0-b9a2-2700ecf57440
  modified: 2026-09-03T13:15:10.141Z
---

Der Energieberater in der Vollversion (`Forming.Standard`) zieht seine Lizenz über
`Source.HottId` von `authservice.hottgenroth.de` + `licenseservice.hottgenroth.de`
(`Hsetu.EnergyConsultant.Application.GetLicenseSource`). Schlägt der Abruf fehl, liest
`HottgenrothIdLicenseProvider` aus `%LOCALAPPDATA%\HSETU\License\Data\<AppId>.offline`.

Die Grenze steht in `Hsetu.License.Client.Desktop`, `JsonLicenses`:
`ExpirationTimeSpan = 14 Tage` ab `lastSyncDate` je Eintrag — danach wird der Eintrag beim
Lesen **gelöscht**, nicht nur ignoriert. Rechnen, HottCAD, Kataloge, TRY und die LocalDB
sind komplett lokal; nur die Lizenz zwingt regelmäßig ins Netz.

Drei Stolperfallen:
- Der Speicher ist DPAPI-`CurrentUser`-verschlüsselt und die DeviceId gerätegebunden — ein
  eigenes Dienstkonto für den Agenten hat einen **leeren** Cache. Siehe
  [[hottgenroth-agent-testaufbau]].
  Die DeviceId selbst ist kein Hardware-Fingerabdruck: `deviceid.dll` (Delphi, nativ) erzeugt
  sie einmalig per `UuidCreate` und legt sie verschlüsselt in der Registry ab —
  `HKLM\SOFTWARE\WOW6432Node\HSETU\DeviceID`, also **maschinenweit, nicht je Benutzer**.
  Sie geht als `X-DeviceId` an den Lizenzdienst (dazu `X-AppId`, `X-AppName`, `X-AppVersion`,
  `X-EditionId`, `X-OSInfo`). Löschen ⇒ neuer Arbeitsplatz beim Dienst.
- Bricht man ein aufpoppendes Anmeldefenster ab, meldet der Client `UserCancel` →
  `AuthentificationCancelledByUserException` → **leerer** Lizenzcontainer, der Offline-Cache
  wird bewusst übersprungen. Nur echte Netzfehler/Timeouts fallen auf den Cache zurück.
- Offline dauert der Start länger: HTTP-Timeout 10 s je Aufruf plus OIDC-Discovery.

Dauerhaft offline vorgesehen sind nur `Source.Local` (HSETU.Lic, Demo/Bildung) und
`Source.Dongle` — beides nutzt der Energieberater nicht. Für abgeschottete Rechner müsste
man Hottgenroth nach Dongle oder dem mitgelieferten `OnPremiseLicenseService` fragen.
