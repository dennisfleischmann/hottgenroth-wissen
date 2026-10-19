-- Entfernt "AA-OGD-Holzbalkendecke-1969-1978" wieder aus dem Projekt
-- "Jan Malte Strackerjan_iSFP (1)". Gegenstueck zu insert-bauteil-inhomogen-ogd.sql
-- (Lauf vom 07.08.2026). Reihenfolge: Layer -> Sections -> Dimension -> Katalog -> Basis.

USE HsetuPrjData;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @BasisUId uniqueidentifier = '01599F1A-A503-41A9-A236-872372FB6423';
DECLARE @DimUId   uniqueidentifier = '5AECB3FA-3F13-4123-8484-7CF2FC214F74';

BEGIN TRANSACTION;

DELETE FROM TcBuildingElementDimensionLayer WHERE DimensionUId = @DimUId;
PRINT N'Layer geloescht:        ' + CAST(@@ROWCOUNT AS nvarchar(5));

DELETE FROM TcBuildingElementDimensionLayerSection WHERE DimensionUId = @DimUId;
PRINT N'Sections geloescht:     ' + CAST(@@ROWCOUNT AS nvarchar(5));

DELETE FROM TcBuildingElementDimension WHERE UId = @DimUId;
PRINT N'Dimension geloescht:    ' + CAST(@@ROWCOUNT AS nvarchar(5));

DELETE FROM TcCatalogContents WHERE BasisUId = @BasisUId;
PRINT N'Katalogeintrag gel.:    ' + CAST(@@ROWCOUNT AS nvarchar(5));

DELETE FROM TcBasis WHERE UId = @BasisUId;
PRINT N'Basis geloescht:        ' + CAST(@@ROWCOUNT AS nvarchar(5));

COMMIT TRANSACTION;
GO
