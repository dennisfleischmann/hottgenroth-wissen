SET NOCOUNT ON;

-- Alle Raumarten aus BmRoom (PrjData + UsrData kombiniert)
PRINT '=== ALLE RAUMARTEN (RoomType) ==='
SELECT RoomType, MIN(LongDesc) AS Beispiel, COUNT(*) AS Anz, AVG(InsideTemperature) AS AvgTemp
FROM (
    SELECT RoomType, LongDesc, InsideTemperature FROM HsetuPrjData.dbo.BmRoom
    UNION ALL
    SELECT RoomType, LongDesc, InsideTemperature FROM HsetuUsrData.dbo.BmRoom
) x
GROUP BY RoomType
ORDER BY RoomType;

-- Alle Nutzungsprofile (distinct)
PRINT ''
PRINT '=== ALLE NUTZUNGSPROFILE (ProfileUsageType) ==='
SELECT ProfileUsageType, MIN(ShortDesc) AS Kurz, MIN(LongDesc) AS Lang, COUNT(*) AS Anz
FROM (
    SELECT ProfileUsageType, ShortDesc, LongDesc FROM HsetuPrjData.dbo.PdProfileUsage
    UNION ALL
    SELECT ProfileUsageType, ShortDesc, LongDesc FROM HsetuUsrData.dbo.PdProfileUsage
) x
GROUP BY ProfileUsageType
ORDER BY ProfileUsageType;

-- Alle distinct RoomType-Werte aus PdProfile
PRINT ''
PRINT '=== RAUMARTEN IN PROFILEN (PdProfile.RoomType) ==='
SELECT RoomType, COUNT(*) AS Anz
FROM (
    SELECT RoomType FROM HsetuPrjData.dbo.PdProfile WHERE RoomType != 0
    UNION ALL
    SELECT RoomType FROM HsetuUsrData.dbo.PdProfile WHERE RoomType != 0
) x
GROUP BY RoomType
ORDER BY RoomType;
