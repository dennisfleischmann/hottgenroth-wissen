-- ============================================================
-- INHOMOGENES Bauteil aus dem Altbauatlas
--
-- Quelle: Altbauatlas.de - "Oberste Geschossdecke, Holzbalkendecke, Daemmung"
--         Baualtersklasse 1969-1978, PLZ 80-97, Typologie Bayern
--         (Datenerhebung Universitaet Kassel, FG Bauphysik)
--         Angegebener U-Wert-Bereich: 0,60 - 0,45 W/(m2K)
--
-- Ziel: Projekt "Jan Malte Strackerjan_iSFP (1)"
--
-- Aufbau (innen/unten -> aussen/oben), Gesamtdicke 20,8 cm:
--   1,0 cm Kalkgipsputz              lambda 0,70
--   1,3 cm Gipskartonplatte          lambda 0,21
--   8,0 cm | Gefach: Mineralwolle    lambda 0,040   | Balken: Holz lambda 0,14
--   8,0 cm | Gefach: Luftschicht ruhend R=0,16      | Balken: Holz lambda 0,14
--   2,5 cm Dielung                   lambda 0,14
--
-- Gefachgeometrie: Balken 10 cm bei 60 cm lichtem Abstand
--                  -> Balkenanteil 10/(10+60) = 14,2857 %
--
-- Berechneter U-Wert nach EN ISO 6946 (Mittel aus oberer/unterer Grenze):
--   0,4441 W/(m2K)  -> liegt im Altbauatlas-Bereich, nahe der gedaemmten Variante
--
-- Doku zum Schema: ../docs/hottgenroth-bauteil-sql.md, Abschnitte 9a und 7
-- ============================================================

USE HsetuPrjData;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @ProjUId     uniqueidentifier = 'B0D79F01-95F2-2F78-8B16-9D54B907F5CC';
DECLARE @BauteilName nvarchar(200)    = N'AA-OGD-Holzbalkendecke-1969-1978';
-- GroupType = grobe Kategorie, UsageType = konkreter Bauteiltyp in der Auswahlliste.
-- Beide muessen zusammenpassen, sonst zeigt die Software den falschen Typ an.
DECLARE @GroupType   int              = 4;   -- 4 = Boden/Decke (Wand=1, Tuer=2, Fenster=3, Dach=5)
DECLARE @UsageType   int              = 7;   -- 7 = oberste Geschossdecke (bei GroupType 4)

DECLARE @CatalogUId uniqueidentifier, @TimUId uniqueidentifier, @CatContentUId uniqueidentifier;
DECLARE @BasisUId   uniqueidentifier = NEWID();
DECLARE @DimUId     uniqueidentifier = NEWID();
DECLARE @CatEntryUId uniqueidentifier = NEWID();

DECLARE @NullGuid uniqueidentifier = 'AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA';
DECLARE @NullVal  float    = -987654321.99;
DECLARE @Now      datetime = GETDATE();
DECLARE @Epoch    datetime = '1899-12-30T00:00:00';
DECLARE @SyncNow  datetime = DATEADD(hour, -2, GETDATE());
DECLARE @SyncMeta nvarchar(200) = N'{"meta":{"sync":{"mod":"6.6.0","dal":"17.3"}}}';

-- Waermeuebergangswiderstaende: Decke, Waermestrom aufwaerts
DECLARE @Rsi float = 0.10;
DECLARE @Rse float = 0.10;

-- Vorberechnete Kennwerte (Hottgenroth rechnet sie nicht selbst nach)
DECLARE @Thickness float = 0.208;
DECLARE @RValue    float = 2.051816;    -- ohne Rsi/Rse
DECLARE @UValue    float = 0.444091;

-- Gefachgeometrie fuer den Legacy-Block
DECLARE @BalkenBreite int = 10;   -- cm
DECLARE @LichterAbst  int = 60;   -- cm

-- ============================================================
-- Katalog und Ordner des Projekts
-- ============================================================
SELECT @CatalogUId = UId, @TimUId = TIMUId FROM TcCatalog WHERE ProjectUId = @ProjUId;
IF @CatalogUId IS NULL BEGIN RAISERROR(N'Kein Bauteilkatalog fuer das Projekt.',16,1); RETURN; END

SELECT @CatContentUId = UId FROM TcCatalogContent
 WHERE CatalogUId = @CatalogUId AND CatalogContainerType = 6;
IF @CatContentUId IS NULL BEGIN RAISERROR(N'Kein Ordner "Benutzerdefinierte Bauteile".',16,1); RETURN; END

IF EXISTS (SELECT 1 FROM TcBasis WHERE ProjectUId = @ProjUId AND LongDesc = @BauteilName)
BEGIN RAISERROR(N'Bauteil mit diesem Namen existiert bereits.',16,1); RETURN; END

-- ============================================================
-- Sections (vertikale Schnitte). Reihenfolge wie in der Software:
-- Section 1 = Balken (kleiner Anteil), Section 2 = Gefach.
-- ============================================================
DECLARE @S TABLE (
    SecNum   int,                    -- 1-basiert, entspricht G<n> im ElementMeta
    UId      uniqueidentifier,
    Name     nvarchar(200),
    Anteil   float                   -- Prozent, Summe = 100
);
INSERT INTO @S VALUES
 (1, NEWID(), N'Konstruktionsholz',                    14.2857142857143),
 (2, NEWID(), N'Mineral. und pflanzl. Faserdaemmstoff', 85.7142857142857);

-- ============================================================
-- Schichten je Section. Jede Schicht existiert in JEDER Section;
-- gleiche SortNum muss in allen Sections dieselbe Dicke haben.
-- DickeCm ist bewusst Text - der Legacy-Block will "1", "1,3", "2,5".
-- ============================================================
DECLARE @L TABLE (
    SecNum    int,
    SortNum   int,
    UId       uniqueidentifier,
    Name      nvarchar(200),
    Lambda    float,
    Dicke     float,          -- m
    DickeCm   nvarchar(10),   -- Text fuer ElementMeta
    Rohdichte float,
    WKap      float,
    MuU       float,
    MuO       float,
    Grp       int,
    LT        int,            -- LayerType: 0 normal, 3 Daemmung
    MT        int,            -- MaterialType: 0 Standard, 1 Daemmstoff
    Pfad      nvarchar(30),
    IstGefach nvarchar(6)     -- Feld 8 im Legacy-Block: 'Wahr' bei der Gefachschicht
);

-- Section 1: Balkenschnitt
INSERT INTO @L VALUES
 (1, 0, NEWID(), N'Putzmoertel aus Kalkgips, Gips, Anhydrit und Kalkanhydrit',
      0.70, 0.010, N'1',   1400, 1.0, 10,  35, 1, 0, 0, N'1.1.2',     N'Falsch'),
 (1, 1, NEWID(), N'Gipskartonplatten  (DIN 18180)',
      0.21, 0.013, N'1,3',  900, 1.0,  8,   8, 3, 0, 0, N'3.5.1',     N'Falsch'),
 (1, 2, NEWID(), N'Konstruktionsholz  (DIN 12524 - 500 kg/m3)',
      0.14, 0.080, N'8',    500, 1.6, 20,  50, 6, 0, 0, N'6.1.1',     N'Wahr'),
 (1, 3, NEWID(), N'Konstruktionsholz  (DIN 12524 - 500 kg/m3)',
      0.14, 0.080, N'8',    500, 1.6, 20,  50, 6, 0, 0, N'6.1.1',     N'Wahr'),
 (1, 4, NEWID(), N'Dielung, Nadelholz',
      0.14, 0.025, N'2,5',  500, 1.6, 20,  50, 6, 0, 0, N'6.1.1',     N'Falsch');

-- Section 2: Gefachschnitt
INSERT INTO @L VALUES
 (2, 0, NEWID(), N'Putzmoertel aus Kalkgips, Gips, Anhydrit und Kalkanhydrit',
      0.70, 0.010, N'1',   1400, 1.0, 10,  35, 1, 0, 0, N'1.1.2',     N'Falsch'),
 (2, 1, NEWID(), N'Gipskartonplatten  (DIN 18180)',
      0.21, 0.013, N'1,3',  900, 1.0,  8,   8, 3, 0, 0, N'3.5.1',     N'Falsch'),
 (2, 2, NEWID(), N'Mineral. und pflanzl. Faserdaemmstoff  ( WLG 040)',
      0.040, 0.080, N'8',    60, 1.0,  1,   1, 5, 3, 1, N'5.6.3',     N'Falsch'),
 -- ruhende Luftschicht: R = 0,16 m2K/W laut Altbauatlas -> lambda = d/R = 0,08/0,16 = 0,5
 (2, 3, NEWID(), N'ruhende Luftschicht (horizontal) bis 300mm Dicke',
      0.50, 0.080, N'8',   1.29, 1.0,  1,   1, 8, 0, 0, N'L.5.3.1.2', N'Falsch'),
 (2, 4, NEWID(), N'Dielung, Nadelholz',
      0.14, 0.025, N'2,5',  500, 1.6, 20,  50, 6, 0, 0, N'6.1.1',     N'Falsch');

-- ============================================================
-- ElementMeta aufbauen: Kopf, dann je Section BEZ/ANT/ANTWERT + G<n>S<m>
-- ============================================================
DECLARE @CRLF nvarchar(2) = CHAR(13) + CHAR(10);
DECLARE @Meta nvarchar(max);
DECLARE @i int = 1, @cnt int;

SELECT @cnt = COUNT(*) FROM @S;

SET @Meta =
      N'RAI=' + REPLACE(CONVERT(nvarchar(20), CAST(@Rsi AS decimal(10,2))), '.', ',') + @CRLF
    + N'RAA=' + REPLACE(CONVERT(nvarchar(20), CAST(@Rse AS decimal(10,2))), '.', ',') + @CRLF
    -- Speicherkapazitaeten: von Hottgenroth beim naechsten Speichern neu gerechnet,
    -- nicht U-Wert-relevant (siehe Doku Abschnitt 7). Platzhalter.
    + N'CP10CM=1293,05882352941' + @CRLF
    + N'CP3CM=1951,88235294117' + @CRLF
    + N'CPEnIso13786=1834,55909939047' + @CRLF
    + N'InhomogenAlsGefach=Falsch' + @CRLF
    + N'InhomogenDaten=||||||||Wahr|' + CAST(@BalkenBreite AS nvarchar(5))
      + N'|' + CAST(@LichterAbst AS nvarchar(5)) + N'|0|||||||||||||' + @CRLF;

WHILE @i <= @cnt
BEGIN
    SELECT @Meta = @Meta
        + N'BEZ'     + CAST(@i AS nvarchar(3)) + N'=' + Name + @CRLF
        + N'ANT'     + CAST(@i AS nvarchar(3)) + N'='
          + REPLACE(CONVERT(nvarchar(40), CAST(Anteil / 100.0 AS decimal(20,15))), '.', ',') + @CRLF
        + N'ANTWERT' + CAST(@i AS nvarchar(3)) + N'='
          + REPLACE(CONVERT(nvarchar(40), CAST(Anteil AS decimal(20,13))), '.', ',') + @CRLF
    FROM @S WHERE SecNum = @i;

    SELECT @Meta = @Meta
        + N'G' + CAST(@i AS nvarchar(3)) + N'S' + CAST(SortNum + 1 AS nvarchar(3)) + N'=' + Name
        + N'|' + REPLACE(CONVERT(nvarchar(30), CAST(Lambda    AS decimal(18,6))), '.', ',')
        + N'|' + DickeCm
        + N'|' + REPLACE(CONVERT(nvarchar(30), CAST(MuU       AS decimal(18,6))), '.', ',')
        + N'|' + REPLACE(CONVERT(nvarchar(30), CAST(MuO       AS decimal(18,6))), '.', ',')
        + N'|' + CAST(Grp AS nvarchar(3))
        + N'|' + REPLACE(CONVERT(nvarchar(30), CAST(Rohdichte AS decimal(18,6))), '.', ',')
        + N'|' + IstGefach + N'|Falsch|Falsch|0|' + Pfad
        + N'|' + REPLACE(CONVERT(nvarchar(30), CAST(WKap      AS decimal(18,6))), '.', ',')
        + N'|0,000000|0,000000|0,000000|NEIN' + @CRLF
    FROM @L WHERE SecNum = @i ORDER BY SortNum;

    SET @i = @i + 1;
END

SET @Meta = @Meta
    + N'KorrLS=Falsch|0|-1' + @CRLF
    + N'KorrBe=version2008|Falsch|6|0|0|0|-1|0' + @CRLF
    + N'KorrUD=Falsch|0|0|0|-1';

BEGIN TRANSACTION;

-- ============================================================
-- 1) TcBasis
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
    N'', 0, 2, 0, @GroupType, 0, 0,
    0, 0, 0, 0, 0, 0,
    @NullGuid, @NullGuid, @NullGuid, @NullGuid, @NullGuid,
    N'', N'', N'', @Epoch, @Epoch,
    0, N'',
    -999, -999, -999, -999, -999, -999, -999, -999,
    -999, -999, -999, -999, -999, -999, -999, -999,
    N'', N'', N'', N'', N'', N'', N'', N'', N'',
    N'', N'', N'', N'', N'', N'',
    N'', N'',
    0, 0, 0, N'', 0,
    @Now, @Now, @Epoch,
    @TimUId, @ProjUId, @NullGuid,
    2, @NullGuid, @NullGuid, N'1.3.1.3', @SyncMeta, @SyncNow, NEWID(),
    @UsageType, N'',
    @NullVal, @NullVal, @NullVal, @NullVal, @NullVal, @NullVal,
    @NullVal, @NullVal, @NullVal, @NullVal, @NullVal, @NullVal,
    -1, 0,
    0, 0, 0, 0, 0, 0, 0
);

-- ============================================================
-- 2) TcBuildingElementDimension
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
    @Meta,
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
-- 3) TcCatalogContents - macht das Bauteil im Baum sichtbar
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
    2, 0, @GroupType, 0, 0, 0, N'',
    @CatalogUId, @NullGuid,
    0, 0, 0, 0, N'', 0,
    @Now, @Now, @Now,
    @ProjUId, @NullGuid, 0,
    2, @NullGuid, @NullGuid, N'1.3.3', @SyncMeta, @SyncNow, NEWID()
);

-- ============================================================
-- 4) LayerSections - MUSS vor den Layern kommen
-- ============================================================
INSERT INTO TcBuildingElementDimensionLayerSection (
    [UId],[GId],[DimensionUId],[OId],[SortNum],[SeqNum],
    [ShortDesc],[LongDesc],[InfoDesc],
    [SectionShareValve],[SectionNum],[SectionLayerNum],[SectionType],
    [CatalogStateType],[EditModeType],[StateType],[VariantType],[VariantRoot],[GeneratorType],
    [StampCreate],[StampEdit],[StampSync],
    [ProjectUId],[MId],[GeoDesc],[GeoType],[CatalogGroupUId],
    [SyncType],[SyncCreate],[SyncEdit],[SyncVersion],[SyncMeta],[SyncStamp],[SyncRowVersion]
)
SELECT
    S.UId, S.UId, @DimUId, -1, S.SecNum - 1, 0,
    N'', S.Name, N'',
    S.Anteil, 0, -999, 0,
    0, 0, 0, 0, N'', 0,
    @Now, @Now, @Epoch,
    @ProjUId, @NullGuid, NULL, NULL, NULL,
    2, @NullGuid, @NullGuid, N'1.3.2.2', @SyncMeta, @SyncNow, NEWID()
FROM @S AS S;

-- ============================================================
-- 5) Layer - jede Schicht in jeder Section, verknuepft ueber LayerSectionUId
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
    L.UId, L.UId, @DimUId, S.UId, -1, L.SortNum, -1,
    N'', L.Name, N'',
    L.LT, 0, 0, 0,
    @NullGuid, L.Grp, L.MT, N'',
    L.Lambda, L.Dicke / L.Lambda, @NullVal, L.Rohdichte, L.WKap, L.Dicke,
    @NullVal, @NullVal,
    L.MuU, L.MuO,
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
FROM @L AS L
JOIN @S AS S ON S.SecNum = L.SecNum;

COMMIT TRANSACTION;

DECLARE @nSec int, @nLay int;
SELECT @nSec = COUNT(*) FROM @S;
SELECT @nLay = COUNT(*) FROM @L;

PRINT N'';
PRINT N'=== "' + @BauteilName + N'" erstellt ===';
PRINT N'BasisUId: ' + CAST(@BasisUId AS nvarchar(36));
PRINT N'DimUId:   ' + CAST(@DimUId AS nvarchar(36));
PRINT N'Sections: ' + CAST(@nSec AS nvarchar(5)) + N'   Layer-Zeilen: ' + CAST(@nLay AS nvarchar(5));
PRINT N'U = 0,4441 W/(m2K)   d = 20,8 cm   (Altbauatlas: 0,60 - 0,45)';
GO
