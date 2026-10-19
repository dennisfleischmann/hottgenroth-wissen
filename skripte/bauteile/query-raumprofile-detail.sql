SET NOCOUNT ON;

-- 1. Raumarten: welche RoomType-Nummern gibt es + Anzahl
PRINT '=== RAUMARTEN (RoomType-Verteilung) ==='
SELECT
    r.RoomType AS RaumartNr,
    MIN(r.LongDesc) AS BeispielName,
    COUNT(*) AS Anzahl,
    AVG(r.InsideTemperature) AS DurchschnittTemp,
    MIN(r.HeatingType) AS HeatingType
FROM BmRoom r
GROUP BY r.RoomType
ORDER BY COUNT(*) DESC;

-- 2. Nutzungsprofile mit Details
PRINT ''
PRINT '=== NUTZUNGSPROFILE (PdProfileUsage) ==='
SELECT
    pu.Id,
    pu.ShortDesc AS Kurz,
    LEFT(pu.LongDesc, 60) AS Lang,
    pu.ProfileUsageType AS TypNr,
    pu.NominalRoomTemperature AS SollTemp,
    pu.HeatingType AS HeizTyp,
    pu.UserCount AS Personen,
    pu.MaintenanceIllumination AS Lux,
    pu.PersonActivityClassType AS AktTyp
FROM PdProfileUsage pu
ORDER BY pu.SortNum, pu.Id;

-- 3. Profile (PdProfile) - nur mit RoomType
PRINT ''
PRINT '=== PROFILE (PdProfile) mit RoomType ==='
SELECT
    p.Id,
    p.ShortDesc AS Kurz,
    LEFT(p.LongDesc, 60) AS Lang,
    p.ProfileType AS ProfilTyp,
    p.RoomType AS RaumartNr,
    p.Active,
    p.StandardType AS StdTyp
FROM PdProfile p
WHERE p.Active = 1 OR p.RoomType IS NOT NULL
ORDER BY p.RoomType, p.SortNum;

-- 4. Raumgruppen/Zonen
PRINT ''
PRINT '=== RAUMGRUPPEN / ZONEN (BmRoomGroup) ==='
SELECT
    rg.Id,
    rg.ShortDesc AS Kurz,
    LEFT(rg.LongDesc, 60) AS Lang,
    rg.RoomGroupType AS GruppenTyp,
    rg.SpaceType AS Raumart,
    rg.HeatingType AS HeizTyp,
    rg.Area,
    rg.Volume,
    rg.InsideTemperature AS Innentemp
FROM BmRoomGroup rg
ORDER BY rg.SortNum, rg.Id;

-- 5. BmRoomData Details
PRINT ''
PRINT '=== RAUM-DETAILS (BmRoomData) ==='
SELECT
    rd.Id,
    rd.ShortDesc AS Kurz,
    LEFT(rd.LongDesc, 60) AS Lang,
    rd.SortNum
FROM BmRoomData rd
ORDER BY rd.SortNum, rd.Id;

-- 6. Nutzungsprofile aus Template-DB (HsetuUsrData)
PRINT ''
PRINT '=== TEMPLATE-NUTZUNGSPROFILE (HsetuUsrData.PdProfileUsage - TOP 30) ==='
SELECT TOP 30
    pu.Id,
    pu.ShortDesc AS Kurz,
    LEFT(pu.LongDesc, 60) AS Lang,
    pu.ProfileUsageType AS TypNr,
    pu.NominalRoomTemperature AS SollTemp
FROM HsetuUsrData.dbo.PdProfileUsage pu
ORDER BY pu.SortNum, pu.Id;

-- 7. Profil-Gruppen
PRINT ''
PRINT '=== PROFIL-GRUPPEN (PdProfileGroup) ==='
SELECT
    pg.Id,
    pg.ShortDesc AS Kurz,
    LEFT(pg.LongDesc, 60) AS Lang,
    pg.ProfileGroupType AS GruppenTyp
FROM PdProfileGroup pg
ORDER BY pg.SortNum, pg.Id;
