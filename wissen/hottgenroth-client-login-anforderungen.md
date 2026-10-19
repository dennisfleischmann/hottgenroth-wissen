---
name: hottgenroth-client-login-anforderungen
description: "Was der Hottgenroth-OIDC-Client von unseren Token/Claims/Lizenzen erwartet (aus dem Dekompilat belegt): sub muss GUID sein, tenants ein Array, Lizenz-GUIDs centgenau; U-Therm=4c5aed38, Hott-Therm=1c0e1843"
metadata:
  node_type: memory
  type: project
  originSessionId: aa234aa5-b72b-40ae-b628-48e75924bd54
  modified: 2026-10-12T21:34:29.878Z
---

# Hottgenroth-Client: harte Anforderungen an Hottgenroth-ID

Am dekompilierten Client (`C:\Projekte_Dev\hsetu-decompiled`, v. a.
`Hsetu.LoginControl.OAuth.cs`, `Hsetu.License.Workflow.Desktop.cs`) belegt —
gilt für die eingesetzten Builds (EE-Berater 2.9.2, Energieberater 2.8.1):

- **`sub` MUSS ein parsebarer GUID sein.** `ClaimsUserInfoProvider.GetUserInfo`
  ruft `Guid.Parse(GetClaim("sub"))` (OAuth.cs:1490). Unser `sub = user->id`
  (Integer „425") wirft → Claims-Pfad scheitert → Client fällt auf die zeitlich
  jüngste `<sub>.auth`-Datei zurück = **der zuletzt gespeicherte Nutzer**.
  Das ist die Ursache des „alter User bleibt eingeloggt". Fix (offen): user->id
  reversibel auf eine GUID abbilden, Lesestellen (Licenses/UserInfoController)
  decodieren.
- **`tenants` ist ein ARRAY** von Objekten (`CreateTenantCollection`,
  System.Text.Json, case-insensitiv). Feldnamen: `id`,`name`,`roles`,
  `permissions`, `cids`, `fnm`, `snm`. `tenant_id` (einzeln) liest nur der
  älteste Build (Textbausteine). Leeres `[]` wirft NICHT (LicenseModel.Create
  nutzt `?.Name`), ist also nicht die Loop-Ursache — aber ohne passenden Tenant
  bleibt der Mandantenname generisch. Owner-Tenant braucht Rolle `ten:own`
  (`GetOwner` macht `Single`).
- **Claims kommen aus dem ID-Token** (`ProcessToken` liest IdentityToken), nicht
  dem Access-Token. Beim `refresh_token`-Grant MUSS ein frischer id_token mit.
- **Logout:** Client schickt `end_session` OHNE `id_token_hint` und kein
  `prompt=login`; `DoLogout` löscht nur lokale Dateien (refresh.token), nie die
  `.auth`/`.license`. Ein geteilter Token-Store pro (authority,clientId,scopes)
  wird von ALLEN HSETU-Apps geteilt (ein Singleton-AuthHelper je Prozess).

## Lizenz-GUIDs: Katalog centgenau halten

**Produkt-GUIDs sind NICHT die Updater-GUIDs** (`Hsetu.Update.Common` hat ganz
andere). Die echte Lizenz-GUID steht als `new LicenseId(<nr>, Guid.Parse("..."))`
in der jeweiligen App/Modul-Datei. Fehler gefunden 12.10.2026 in
`app/Services/HottgenrothId/ProductCatalog.php`:

- `1c0e1843-df55-4f7b-8488-a5cefae26f7d` = **Hott-Therm** (HottTherm.cs, LicenseId 815) — war fälschlich als „U-Therm" gelabelt.
- `4c5aed38-aa0e-402f-a2db-4e49aed11313` = **U-Therm** (belegt: die LICC-Prüf-
  datei `<guid>.temp` auf dem Arbeitsplatz trägt genau diese GUID; unsere Tests
  nennen sie „U-Therm Vollversion"). U-Therm selbst ist NICHT dekompiliert.

Folge war: U-Therm fand seine Lizenz nie („keine Lizenz"), obwohl 14 Lizenzen
ausgeliefert wurden. Seit 12.10.2026 im Katalog getrennt und deployt.

**Diagnose-Trick:** Welche Lizenz-GUID eine nicht-dekompilierte App prüft, steht
im LICC-Log (`%TEMP%\HSETU\LICC\LICC.log`) und im Dateinamen der Prüfdatei
`%LOCALAPPDATA%\HSETU\License\Data\<lizenz-guid>.temp`.

Verwandt: [[hottgenroth-id-feature]], [[hsetu-dekompilierter-korpus]]
