-- Korrigiert "AA-OGD-Holzbalkendecke-1969-1978" auf den richtigen Bauteiltyp.
--
-- WICHTIG: Energieberater vorher SCHLIESSEN. Ein erster Korrekturversuch bei
-- laufender Software wurde von dieser wieder ueberschrieben - sie hatte das
-- Bauteil im Speicher und hat ihren Stand zurueckgeschrieben.
--
-- Setzt:
--   UsageType 2 -> 7   (Boden gegen Aussen -> oberste Geschossdecke)
--   Rsi/Rse 0,17/0,04 -> 0,10/0,10   (Waermestrom nach oben statt nach unten)
--
-- U-Wert bleibt 0,4441 = 1 / (2,051816 + 0,10 + 0,10)

USE HsetuPrjData;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @BasisUId uniqueidentifier = '01599F1A-A503-41A9-A236-872372FB6423';
DECLARE @DimUId   uniqueidentifier = '5AECB3FA-3F13-4123-8484-7CF2FC214F74';

BEGIN TRANSACTION;

UPDATE TcBasis
   SET UsageType = 7,
       StampEdit = GETDATE()
 WHERE UId = @BasisUId;
PRINT N'TcBasis aktualisiert: ' + CAST(@@ROWCOUNT AS nvarchar(5));

UPDATE TcBuildingElementDimension
   SET InternalCoefficientOfHeatTransfer = 0.10,
       ExternalCoefficientOfHeatTransfer = 0.10,
       ElementMeta = REPLACE(REPLACE(ElementMeta, N'RAI=0,17', N'RAI=0,1'), N'RAA=0,04', N'RAA=0,1'),
       StampEdit = GETDATE()
 WHERE UId = @DimUId;
PRINT N'Dimension aktualisiert: ' + CAST(@@ROWCOUNT AS nvarchar(5));

COMMIT TRANSACTION;

SELECT b.LongDesc, b.GroupType GT, b.UsageType Usg,
       d.InternalCoefficientOfHeatTransfer Rsi, d.ExternalCoefficientOfHeatTransfer Rse,
       d.UValue, d.RValue
FROM TcBasis b JOIN TcBuildingElementDimension d ON d.BasisUId = b.UId
WHERE b.UId = @BasisUId;
GO
