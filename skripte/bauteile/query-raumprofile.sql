SET NOCOUNT ON;

-- 1. Alle Raeume mit Raumart
PRINT '=== RAEUME (BmRoom) ==='
SELECT
    r.Id,
    r.ShortDesc AS Kurzbezeichnung,
    LEFT(r.LongDesc, 80) AS Langbezeichnung,
    r.RoomType AS RaumartNr,
    r.Area,
    r.Volume,
    r.Height,
    r.InsideTemperature AS Innentemp,
    r.HeatingType,
    r.CoolingType,
    r.VentilationType
FROM BmRoom r
ORDER BY r.SortNum, r.Id;

-- 2. Nutzungsprofile (PdProfileUsage)
PRINT ''
PRINT '=== NUTZUNGSPROFILE (PdProfileUsage) ==='
SELECT
    pu.Id,
    pu.ShortDesc AS Kurzbezeichnung,
    LEFT(pu.LongDesc, 80) AS Langbezeichnung,
    pu.ProfileUsageType AS NutzungsTypNr,
    pu.NominalRoomTemperature AS SollTemp,
    pu.HeatingType,
    pu.UserCount AS Personenzahl,
    pu.MaintenanceIllumination AS Beleuchtung_lx,
    pu.SpecificThermalOutputPowerOfPersons AS WaermePersonen,
    pu.SpecificThermalOutputOfDevices AS WaermeGeraete,
    pu.PersonActivityClassType AS AktivitaetTyp
FROM PdProfileUsage pu
ORDER BY pu.SortNum, pu.Id;

-- 3. Profile (PdProfile) mit RoomType
PRINT ''
PRINT '=== PROFILE (PdProfile) ==='
SELECT
    p.Id,
    p.ShortDesc AS Kurzbezeichnung,
    LEFT(p.LongDesc, 80) AS Langbezeichnung,
    p.ProfileType AS ProfilTypNr,
    p.RoomType AS RaumartNr,
    p.Active,
    p.StandardType,
    p.FloorType
FROM PdProfile p
ORDER BY p.SortNum, p.Id;

-- 4. Raumgruppen (Zonen)
PRINT ''
PRINT '=== RAUMGRUPPEN / ZONEN (BmRoomGroup) ==='
SELECT
    rg.Id,
    rg.ShortDesc AS Kurzbezeichnung,
    LEFT(rg.LongDesc, 80) AS Langbezeichnung,
    rg.ParentClassType,
    rg.RoomGroupType,
    rg.SpaceType,
    rg.HeatingType,
    rg.Area,
    rg.Volume,
    rg.InsideTemperature AS Innentemp
FROM BmRoomGroup rg
ORDER BY rg.SortNum, rg.Id;
