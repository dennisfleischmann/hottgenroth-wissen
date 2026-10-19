-- ============================================================
-- Beispiel-Bauteil fuer Projekt "Jan Malte Strackerjan_iSFP (1)"
-- Ziel: Bauteilkatalog des Projekts, Ordner "=== Benutzerdefinierte Bauteile ==="
--
-- Aufbau (innen -> aussen), U = 0,199 W/(m2K), d = 42 cm:
--   0: Gipsputz                    1,5 cm
--   1: Kalksandstein KS 1800      24,0 cm
--   2: EPS WLS 035 (Daemmung)     16,0 cm
--   3: Armierungsputz              0,5 cm
--
-- Basiert auf insert-bauteil-v4.sql, mit den zwei gegen den Software-Trace
-- verifizierten Korrekturen: TcBasis.UsageType = 2 und TcBasis.SyncType = 2.
-- Doku: ../docs/hottgenroth-bauteil-sql.md
-- ============================================================

USE HsetuPrjData;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @ProjUId       uniqueidentifier = 'B0D79F01-95F2-2F78-8B16-9D54B907F5CC';
DECLARE @BauteilName   nvarchar(200)    = N'BEISPIEL-Aussenwand-WDVS-16cm';

DECLARE @CatalogUId    uniqueidentifier;
DECLARE @TimUId        uniqueidentifier;
DECLARE @CatContentUId uniqueidentifier;
DECLARE @BasisUId      uniqueidentifier = NEWID();
DECLARE @DimUId        uniqueidentifier = NEWID();
DECLARE @CatEntryUId   uniqueidentifier = NEWID();

DECLARE @NullGuid      uniqueidentifier = 'AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA';
DECLARE @NullVal       float            = -987654321.99;
DECLARE @Now           datetime         = GETDATE();
DECLARE @Epoch         datetime         = '1899-12-30T00:00:00';
DECLARE @SyncNow       datetime         = DATEADD(hour, -2, GETDATE());
DECLARE @SyncMeta      nvarchar(200)    = N'{"meta":{"sync":{"mod":"6.6.0","dal":"17.3"}}}';

-- Kennwerte: RValue = Summe der Schicht-R OHNE Rsi/Rse, U = 1/(R + Rsi + Rse)
DECLARE @Thickness float = 0.42;
DECLARE @RValue    float = 4.850408;
DECLARE @UValue    float = 0.199189;
DECLARE @Rsi       float = 0.13;
DECLARE @Rse       float = 0.04;

-- ============================================================
-- 0) Katalog + Ordner des Projekts ermitteln
-- ============================================================
SELECT @CatalogUId = UId, @TimUId = TIMUId
FROM   TcCatalog
WHERE  ProjectUId = @ProjUId;

IF @CatalogUId IS NULL
BEGIN
    RAISERROR(N'Kein Bauteilkatalog fuer dieses Projekt gefunden - Abbruch.', 16, 1);
    RETURN;
END

SELECT @CatContentUId = UId
FROM   TcCatalogContent
WHERE  CatalogUId = @CatalogUId AND CatalogContainerType = 6;

IF @CatContentUId IS NULL
BEGIN
    RAISERROR(N'Kein Ordner "Benutzerdefinierte Bauteile" gefunden - Abbruch.', 16, 1);
    RETURN;
END

IF EXISTS (SELECT 1 FROM TcBasis WHERE ProjectUId = @ProjUId AND LongDesc = @BauteilName)
BEGIN
    RAISERROR(N'Ein Bauteil mit diesem Namen existiert bereits - Abbruch.', 16, 1);
    RETURN;
END

PRINT N'Katalog:  ' + CAST(@CatalogUId AS nvarchar(36));
PRINT N'Ordner:   ' + CAST(@CatContentUId AS nvarchar(36));

-- ============================================================
-- Schichtdefinition (innen -> aussen)
-- ============================================================
DECLARE @L TABLE (
    SortNum      int,
    UId          uniqueidentifier,
    Name         nvarchar(200),
    Lambda       float,   -- W/(mK)
    Dicke        float,   -- m
    Rohdichte    float,   -- kg/m3
    WKapazitaet  float,   -- kJ/(kgK)
    MuUnten      float,
    MuOben       float,
    MatGruppe    int,     -- = Spalte GruppeNr im Baustoffkatalog
    LayerType    int,     -- 0 = normal, 3 = Daemmschicht
    MatType      int,     -- 0 = Standard, 1 = Daemmstoff
    KatPfad      nvarchar(50)
);

INSERT INTO @L VALUES
 (0, NEWID(), N'Gipsputz ohne Zuschlag',
     0.51,  0.015, 1200, 1.0, 10,  35, 1, 0, 0, N'1.1.2'),
 (1, NEWID(), N'Kalksandstein, NM/DM  (1800 kg/m3)',
     0.99,  0.240, 1800, 1.0,  5,  15, 4, 0, 0, N'4.1.2'),
 (2, NEWID(), N'Polystyrol PS -Partikelschaum  (WLG 035 - > 30 kg/m3)',
     0.035, 0.160,   30, 1.5, 80, 250, 5, 3, 1, N'5.5.1.1.1.2'),
 (3, NEWID(), N'Putzmoertel aus Kalk, Kalkzement und hydraulischem Kalk',
     0.70,  0.005, 1400, 1.0, 15,  35, 1, 0, 0, N'1.1.1');

-- ============================================================
-- ElementMeta aus der Schichttabelle erzeugen (Legacy-Textblock).
-- Achtung: Dicke dort in cm und mit deutschem Dezimalkomma.
-- ============================================================
DECLARE @CRLF nvarchar(2) = CHAR(13) + CHAR(10);
DECLARE @ElementMeta nvarchar(max) =
      N'RAI=' + REPLACE(CONVERT(nvarchar(20), CAST(@Rsi AS decimal(10,2))), '.', ',') + @CRLF
    + N'RAA=' + REPLACE(CONVERT(nvarchar(20), CAST(@Rse AS decimal(10,2))), '.', ',') + @CRLF
    + N'CP10CM=4800' + @CRLF
    + N'CP3CM=16000' + @CRLF
    + N'CPEnIso13786=5020' + @CRLF;

SELECT @ElementMeta = @ElementMeta
    + N'G1S' + CAST(SortNum + 1 AS nvarchar(3)) + N'=' + Name
    + N'|' + REPLACE(CONVERT(nvarchar(30), CAST(Lambda      AS decimal(18,6))), '.', ',')
    + N'|' + REPLACE(CONVERT(nvarchar(30), CAST(Dicke * 100 AS decimal(18,2))), '.', ',')
    + N'|' + REPLACE(CONVERT(nvarchar(30), CAST(MuUnten     AS decimal(18,6))), '.', ',')
    + N'|' + REPLACE(CONVERT(nvarchar(30), CAST(MuOben      AS decimal(18,6))), '.', ',')
    + N'|' + CAST(MatGruppe AS nvarchar(3))
    + N'|' + REPLACE(CONVERT(nvarchar(30), CAST(Rohdichte   AS decimal(18,6))), '.', ',')
    + N'|Falsch|Falsch|Falsch|0|' + KatPfad
    + N'|' + REPLACE(CONVERT(nvarchar(30), CAST(WKapazitaet AS decimal(18,6))), '.', ',')
    + N'|0,000000|0,000000|0,000000|NEIN' + @CRLF
FROM @L ORDER BY SortNum;

SET @ElementMeta = @ElementMeta
    + N'KorrLS=Falsch|0|-1' + @CRLF
    + N'KorrBe=version2008|Falsch|6|0|0|0|-1|0' + @CRLF
    + N'KorrUD=Falsch|0|0|0|-1';

-- Die "1,5" der Legacy-Zeile darf keine Nachkommanullen haben
SET @ElementMeta = REPLACE(@ElementMeta, N',00|', N'|');
SET @ElementMeta = REPLACE(@ElementMeta, N',50|', N',5|');

BEGIN TRANSACTION;

-- ============================================================
-- 1) TcBasis: Stammsatz
--    ElementType=2 (Bauteil), GroupType=1, UsageType=2, SyncType=2
-- ============================================================
INSERT INTO TcBasis (
    [UId],[GId],[OId],[SeqNum],[SortNum],[ShortDesc],[LongDesc],[InfoDesc],
    [BodyText],[BodyTextType],[ElementType],[CategoryType],[GroupType],[BasisType],[SubType],
    [ComponentType],[LanguageType],[InstallationSiteType],[LevelOfDetailType],[HeatSourceType],[DesignType],
    [MaterialUId],[ManufacturerUId],[FuelUId],[DataSourceUId],[ColourUId],
    [Category],[CECode],[MatchCode],[ValidStartDate],[ValidEndDate],
    [CatalogStateType],[VDI3805DatabaseName],
    [VDI3805StandardNumber],[VDI3805DataSet100],[VDI3805DataSet110],[VDI3805DataSet160],
    [VDI3805DataSet200],[VDI3805DataSet250],[VDI3805DataSet260],[VDI3805DataSet300],
    [VDI3805DataSet350],[VDI3805DataSet360],[VDI3805DataSet400],[VDI3805DataSet450],
    [VDI3805DataSet460],[VDI3805DataSet500],[VDI3805DataSet550],[VDI3805DataSet560],
    [VDI3805DataSet100Desc],[VDI3805DataSet110Desc],[VDI3805DataSet160Desc],
    [VDI3805DataSet200Desc],[VDI3805DataSet250Desc],[VDI3805DataSet260Desc],
    [VDI3805DataSet300Desc],[VDI3805DataSet350Desc],[VDI3805DataSet360Desc],
    [VDI3805DataSet400Desc],[VDI3805DataSet450Desc],[VDI3805DataSet460Desc],
    [VDI3805DataSet500Desc],[VDI3805DataSet550Desc],[VDI3805DataSet560Desc],
    [VDI3805TGANumber],[VDI3805DataSet],
    [EditModeType],[StateType],[VariantType],[VariantRoot],[GeneratorType],
    [StampCreate],[StampEdit],[StampSync],
    [TIMUId],[ProjectUId],[MId],
    [SyncType],[SyncCreate],[SyncEdit],[SyncVersion],[SyncMeta],[SyncStamp],[SyncRowVersion],
    [UsageType],[ConstructionInfo],
    [FMin01],[FMax01],[FMin02],[FMax02],[FMin03],[FMax03],
    [FMin04],[FMax04],[FMin05],[FMax05],[FMin06],[FMax06],
    [FIdx01],[StandardType],
    [WindowPanelPositionType],[GlazingWindowIsoType],[EdgeMaterialType],
    [FrameMaterialType],[FrameType],[ThermalBridgeJunctionType],[ThermalBridgeCalcType]
) VALUES (
    @BasisUId, @BasisUId, -1, -1, -1, N'', @BauteilName, N'',
    N'', 0, 2, 0, 1, 0, 0,
    0, 0, 0, 0, 0, 0,
    @NullGuid, @NullGuid, @NullGuid, @NullGuid, @NullGuid,
    N'', N'', N'', @Epoch, @Epoch,
    0, N'',
    -999, -999, -999, -999,
    -999, -999, -999, -999,
    -999, -999, -999, -999,
    -999, -999, -999, -999,
    N'', N'', N'',
    N'', N'', N'',
    N'', N'', N'',
    N'', N'', N'',
    N'', N'', N'',
    N'', N'',
    0, 0, 0, N'', 0,
    @Now, @Now, @Epoch,
    @TimUId, @ProjUId, @NullGuid,
    2, @NullGuid, @NullGuid, N'1.3.1.3', @SyncMeta, @SyncNow, NEWID(),
    2, N'',
    @NullVal, @NullVal, @NullVal, @NullVal, @NullVal, @NullVal,
    @NullVal, @NullVal, @NullVal, @NullVal, @NullVal, @NullVal,
    -1, 0,
    0, 0, 0,
    0, 0, 0, 0
);

-- ============================================================
-- 2) TcBuildingElementDimension: Kennwerte + ElementMeta
-- ============================================================
INSERT INTO TcBuildingElementDimension (
    [UId],[GId],[OId],[SeqNum],[SortNum],[ShortDesc],[LongDesc],[InfoDesc],[MatchCode],[BodyTextType],
    [BasisUId],[Thickness],[RawThickness],[FinalThickness],
    [Width],[Height],[Length],[Area],[Volume],
    [PsiValue],[PsiSystemValue],[PsiGeometryValue],[UnValue],[WValue],
    [UValue],[RValue],
    [InternalCoefficientOfHeatTransfer],[ExternalCoefficientOfHeatTransfer],
    [FractionOfFrame],[GValue],[ShadingCoefficient],[IsVentilated],
    [ElementMeta],
    [MullionFirstThickness],[MullionFirstOffset],[MullionSecondThickness],[MullionSecondOffset],
    [TransomFirstThickness],[TransomFirstOffset],[TransomSecondThickness],[TransomSecondOffset],
    [HorizontalBarNumberOfBars],[HorizontalBarWidth],[HorizontalBarArea],[HorizontalBarLengthWeight],
    [VerticalBarNumberOfBars],[VerticalBarWidth],[VerticalBarArea],[VerticalBarLengthWeight],
    [GlazingIsoType],[GlazingUValue],[GlazingGValue],
    [GlazingLength],[GlazingWidth],[GlazingPerimeter],[GlazingArea],[GlazingBasisWeight],
    [EdgeLength],[EdgePsiValue],[EdgeLengthWeight],
    [FrameWidth],[FrameArea],[FrameFractionOfFrame],[FrameUValue],[FrameLengthWeight],
    [CatalogStateType],[ValidStartDate],[ValidEndDate],[BodyText],
    [ProjectUId],[StateType],[VariantType],[VariantRoot],[EditModeType],[GeneratorType],
    [StampCreate],[StampEdit],[StampSync],
    [MId],[SyncType],[SyncCreate],[SyncEdit],[SyncVersion],[SyncMeta],[SyncStamp],[SyncRowVersion]
) VALUES (
    @DimUId, @DimUId, -1, -1, -1, N'', @BauteilName, N'', N'', 0,
    @BasisUId, @Thickness, 0, 0,
    @NullVal, @NullVal, @NullVal, @NullVal, @NullVal,
    @NullVal, @NullVal, @NullVal, @NullVal, @NullVal,
    @UValue, @RValue,
    @Rsi, @Rse,
    @NullVal, @NullVal, @NullVal, 0,
    @ElementMeta,
    @NullVal, @NullVal, @NullVal, @NullVal,
    @NullVal, @NullVal, @NullVal, @NullVal,
    -999, @NullVal, @NullVal, @NullVal,
    -999, @NullVal, @NullVal, @NullVal,
    0, @NullVal, @NullVal,
    @NullVal, @NullVal, @NullVal, @NullVal, @NullVal,
    @NullVal, @NullVal, @NullVal,
    @NullVal, @NullVal, @NullVal, @NullVal, @NullVal,
    0, @Epoch, @Epoch, N'',
    @ProjUId, 0, 0, N'', 0, 0,
    @Now, @Now, @Now,
    @NullGuid, 2, @NullGuid, @NullGuid, N'1.3.1.5', @SyncMeta, @SyncNow, NEWID()
);

-- ============================================================
-- 3) TcCatalogContents: Eintrag im Katalogbaum (macht sichtbar)
--    DimensionUId bleibt NullGuid - Verknuepfung laeuft ueber BasisUId
-- ============================================================
INSERT INTO TcCatalogContents (
    [UId],[GId],[CatalogContentUId],[BasisUId],[DimensionUId],
    [OId],[SeqNum],[SortNum],[ShortDesc],[LongDesc],[InfoDesc],
    [ElementType],[CategoryType],[GroupType],[BasisType],[SubType],[FavoriteType],[MatchCode],
    [CatalogUId],[RefUId],
    [CatalogStateType],[EditModeType],[StateType],[VariantType],[VariantRoot],[GeneratorType],
    [StampCreate],[StampEdit],[StampSync],
    [ProjectUId],[MId],[ContainerType],
    [SyncType],[SyncCreate],[SyncEdit],[SyncVersion],[SyncMeta],[SyncStamp],[SyncRowVersion]
) VALUES (
    @CatEntryUId, @CatEntryUId, @CatContentUId, @BasisUId, @NullGuid,
    -1, -1, -1, N'', @BauteilName, N'',
    2, 0, 1, 0, 0, 0, N'',
    @CatalogUId, @NullGuid,
    0, 0, 0, 0, N'', 0,
    @Now, @Now, @Now,
    @ProjUId, @NullGuid, 0,
    2, @NullGuid, @NullGuid, N'1.3.3', @SyncMeta, @SyncNow, NEWID()
);

-- ============================================================
-- 4) Schichten aus @L erzeugen
-- ============================================================
INSERT INTO TcBuildingElementDimensionLayer (
    [UId],[GId],[DimensionUId],[LayerSectionUId],[OId],[SortNum],[SeqNum],
    [ShortDesc],[LongDesc],[InfoDesc],
    [LayerType],[ScreedType],[ThicknessType],[VentilatedType],
    [MaterialUId],[MaterialGroupType],[MaterialType],[MaterialClassDesc],
    [ThermalConductivity],[RValue],[Roughness],[Density],[HeatCapacity],[Thickness],
    [Emissivity],[DiffusionResistanceCoefficient],
    [LowerDiffusionResistanceCoefficient],[UpperDiffusionResistanceCoefficient],
    [InternalCoefficientOfHeatTransfer],[ExternalCoefficientOfHeatTransfer],
    [ElasticConstant],[LinearExtensionCoefficient],
    [IsVentilated],[IsCapillary],[IsVapourDiffusionTight],[IsHeatReflective],
    [MoistureContent],[HumiditySupplementConductivity],
    [WaterSaturation80Percent],[WaterSaturationFree],
    [DesignValueThermalConductivity],[LowerDesignValueThermalConductivity],[UpperDesignValueThermalConductivity],
    [OI3UId],[OI3IndexActive],[OI3AP],[OI3PEI],[OI3GWP],
    [EN6946UId],[EN6946UGType],
    [EN6946BeamWidth],[EN6946GapWidth],[EN6946OffsetWidth],[EN6946Rotation],
    [EN6946UFType],[EN6946UFAlpha],[EN6946UFLambda],[EN6946UFArea],[EN6946UFCount],[EN6946UFWidth],
    [EN6946URType],[EN6946URF],[EN6946URX],
    [MaterialDimensionUId],[MaterialBasisUId],
    [PipeUId],[PipeLayerPositionType],[PipeD],[PipeD1],[PipeD2],
    [MaterialPCMIsDefined],[MaterialPCMT1],[MaterialPCMT2],[MaterialPCMAdmixture],
    [MaterialPCMEnthalpyOfFusion],[MaterialPCMHeatCapacity],[MaterialPCMThermalConductivity],
    [MaterialPCMHeatCapacityLiquid],[MaterialPCMThermalConductivityLiquid],
    [UMIUId],[UMIEnvironmentType],[EPDUId],[EPDEnvironmentType],
    [CatalogStateType],[ProjectUId],[StateType],[VariantType],[VariantRoot],[EditModeType],[GeneratorType],
    [StampCreate],[StampEdit],[StampSync],
    [MId],[SyncType],[SyncCreate],[SyncEdit],[SyncVersion],[SyncMeta],[SyncStamp],[SyncRowVersion]
)
SELECT
    L.UId, L.UId, @DimUId, @NullGuid, -1, L.SortNum, -1,
    N'', L.Name, N'',
    L.LayerType, 0, 0, 0,
    @NullGuid, L.MatGruppe, L.MatType, N'',
    L.Lambda, L.Dicke / L.Lambda, @NullVal, L.Rohdichte, L.WKapazitaet, L.Dicke,
    @NullVal, @NullVal,
    L.MuUnten, L.MuOben,
    @NullVal, @NullVal,
    @NullVal, @NullVal,
    0, 0, 0, 0,
    @NullVal, @NullVal,
    0, 0,
    @NullVal, @NullVal, @NullVal,
    @NullGuid, 0, 0, 0, 0,
    @NullGuid, 0,
    @NullVal, @NullVal, @NullVal, @NullVal,
    0, @NullVal, @NullVal, @NullVal, @NullVal, @NullVal,
    0, @NullVal, @NullVal,
    @NullGuid, @NullGuid,
    @NullGuid, 0, @NullVal, @NullVal, @NullVal,
    0, @NullVal, @NullVal, @NullVal,
    @NullVal, @NullVal, @NullVal,
    @NullVal, @NullVal,
    @NullGuid, 0, @NullGuid, 0,
    0, @ProjUId, 0, 0, N'', 0, 0,
    @Now, @Now, @Epoch,
    @NullGuid, 2, @NullGuid, @NullGuid, N'1.3.1.8', @SyncMeta, @SyncNow, NEWID()
FROM @L AS L;

COMMIT TRANSACTION;

PRINT N'';
PRINT N'=== Bauteil "' + @BauteilName + N'" erstellt ===';
PRINT N'BasisUId:    ' + CAST(@BasisUId AS nvarchar(36));
PRINT N'DimUId:      ' + CAST(@DimUId AS nvarchar(36));
PRINT N'CatEntryUId: ' + CAST(@CatEntryUId AS nvarchar(36));

DECLARE @LayerCount int;
SELECT @LayerCount = COUNT(*) FROM @L;
PRINT N'Schichten:   ' + CAST(@LayerCount AS nvarchar(5));
PRINT N'--- ElementMeta ---';
PRINT @ElementMeta;
GO
