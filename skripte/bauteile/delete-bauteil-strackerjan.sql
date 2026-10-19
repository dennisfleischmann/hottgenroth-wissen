-- Entfernt das Beispiel-Bauteil "BEISPIEL-Aussenwand-WDVS-16cm" wieder
-- aus dem Projekt "Jan Malte Strackerjan_iSFP (1)".
-- Gegenstueck zu insert-bauteil-strackerjan.sql (Lauf vom 06.08.2026).

USE HsetuPrjData;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @BasisUId uniqueidentifier = '1EF66F84-5FA8-4383-A0E5-3E06851EAB1A';
DECLARE @DimUId   uniqueidentifier = '01786633-BB02-4C98-92C7-F27AF0DB7E75';

BEGIN TRANSACTION;

DELETE FROM TcBuildingElementDimensionLayer WHERE DimensionUId = @DimUId;
PRINT N'Schichten geloescht: ' + CAST(@@ROWCOUNT AS nvarchar(5));

DELETE FROM TcBuildingElementDimension WHERE UId = @DimUId;
PRINT N'Dimension geloescht: ' + CAST(@@ROWCOUNT AS nvarchar(5));

DELETE FROM TcCatalogContents WHERE BasisUId = @BasisUId;
PRINT N'Katalogeintrag geloescht: ' + CAST(@@ROWCOUNT AS nvarchar(5));

DELETE FROM TcBasis WHERE UId = @BasisUId;
PRINT N'Basis geloescht: ' + CAST(@@ROWCOUNT AS nvarchar(5));

COMMIT TRANSACTION;
GO
