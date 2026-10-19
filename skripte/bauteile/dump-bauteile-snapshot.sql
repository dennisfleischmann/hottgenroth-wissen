SET NOCOUNT ON;
USE HsetuPrjData;
GO

PRINT '=== SNAPSHOT START ==='
PRINT '--- TABLE ROW COUNTS ---'

SELECT 'TcBuildingElementDimension' as tbl, COUNT(*) as cnt FROM TcBuildingElementDimension
UNION ALL SELECT 'TcBuildingElementDimensionLayer', COUNT(*) FROM TcBuildingElementDimensionLayer
UNION ALL SELECT 'TcBuildingElementDimensionLayerSection', COUNT(*) FROM TcBuildingElementDimensionLayerSection
UNION ALL SELECT 'TcElementReference', COUNT(*) FROM TcElementReference
UNION ALL SELECT 'TcDimension', COUNT(*) FROM TcDimension
UNION ALL SELECT 'TcDimensionLayer', COUNT(*) FROM TcDimensionLayer
UNION ALL SELECT 'TcDimensionLayerSection', COUNT(*) FROM TcDimensionLayerSection
UNION ALL SELECT 'TcMaterialDimension', COUNT(*) FROM TcMaterialDimension
UNION ALL SELECT 'BmElement', COUNT(*) FROM BmElement
UNION ALL SELECT 'BmElementWall', COUNT(*) FROM BmElementWall
UNION ALL SELECT 'BmElementDimensioning', COUNT(*) FROM BmElementDimensioning
UNION ALL SELECT 'BmElementDimensioningVariant', COUNT(*) FROM BmElementDimensioningVariant
ORDER BY tbl;
GO

PRINT '--- TcBuildingElementDimension (ALL COLUMNS, project only) ---'
SELECT * FROM TcBuildingElementDimension
WHERE ProjectUId = 'B5CF9F01-9DDF-4C79-A164-A6D73B097DE2'
ORDER BY SortNum;
GO

PRINT '--- TcBuildingElementDimensionLayer (project only) ---'
SELECT * FROM TcBuildingElementDimensionLayer
WHERE ProjectUId = 'B5CF9F01-9DDF-4C79-A164-A6D73B097DE2'
ORDER BY DimensionUId, SortNum;
GO

PRINT '--- TcBuildingElementDimensionLayerSection (project dims) ---'
SELECT * FROM TcBuildingElementDimensionLayerSection
WHERE DimensionUId IN (SELECT UId FROM TcBuildingElementDimension WHERE ProjectUId = 'B5CF9F01-9DDF-4C79-A164-A6D73B097DE2')
ORDER BY DimensionUId, SortNum;
GO

PRINT '--- TcElementReference (project only) ---'
SELECT * FROM TcElementReference
WHERE ProjectUId = 'B5CF9F01-9DDF-4C79-A164-A6D73B097DE2';
GO

PRINT '--- TcDimension (recent, last 24h) ---'
SELECT * FROM TcDimension
WHERE StampEdit > DATEADD(hour, -24, GETDATE())
ORDER BY StampEdit DESC;
GO

PRINT '--- TcDimensionLayer (recent, last 24h) ---'
SELECT * FROM TcDimensionLayer
WHERE StampEdit > DATEADD(hour, -24, GETDATE())
ORDER BY StampEdit DESC;
GO

PRINT '=== SNAPSHOT END ==='
