-- Bauteil: WA-Aussenwand-WDVS-SQL (4 Schichten)
-- Ziel: Projekt "Werner Grotz" (D1D39F01-46DB-6B7C-A8FC-7F9D64FEC7F1)
-- Erstellt: Katalog + Ordner + Bauteil + Schichten komplett neu

USE HsetuPrjData;
GO

SET NOCOUNT ON;

-- ============================================================
-- GUIDs und Konstanten
-- ============================================================
DECLARE @ProjUId       uniqueidentifier = 'D1D39F01-46DB-6B7C-A8FC-7F9D64FEC7F1';
DECLARE @TimUId        uniqueidentifier = NEWID();
DECLARE @CatalogUId    uniqueidentifier = NEWID();
DECLARE @CatContentUId uniqueidentifier = NEWID();
DECLARE @BasisUId      uniqueidentifier = NEWID();
DECLARE @DimUId        uniqueidentifier = NEWID();
DECLARE @CatEntryUId   uniqueidentifier = NEWID();
DECLARE @Layer0        uniqueidentifier = NEWID();
DECLARE @Layer1        uniqueidentifier = NEWID();
DECLARE @Layer2        uniqueidentifier = NEWID();
DECLARE @Layer3        uniqueidentifier = NEWID();
DECLARE @NullGuid      uniqueidentifier = 'AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA';
DECLARE @NullVal       float = -987654321.99;
DECLARE @Now           datetime = GETDATE();
DECLARE @Epoch         datetime = '1899-12-30T00:00:00';
DECLARE @SyncNow       datetime = DATEADD(hour, -2, GETDATE());
DECLARE @SyncMeta      nvarchar(200) = N'{"meta":{"sync":{"mod":"6.6.0","dal":"17.3"}}}';
DECLARE @BauteilName   nvarchar(200) = N'WA-Aussenwand-WDVS-SQL-v4';

-- ElementMeta als Variable (vermeidet Multiline-Parsing-Probleme)
DECLARE @ElementMeta nvarchar(max) = N'RAI=0,13' + CHAR(13) + CHAR(10)
    + N'RAA=0,04' + CHAR(13) + CHAR(10)
    + N'CP10CM=4800' + CHAR(13) + CHAR(10)
    + N'CP3CM=16000' + CHAR(13) + CHAR(10)
    + N'CPEnIso13786=5020' + CHAR(13) + CHAR(10)
    + N'G1S1=Gipsputz ohne Zuschlag|0,510000|1,5|10,000000|35,000000|1|1200,000000|Falsch|Falsch|Falsch|0|1.1.2|1,000000|0,000000|0,000000|0,000000|NEIN' + CHAR(13) + CHAR(10)
    + N'G1S2=Kalksandstein, NM/DM  (1800 kg/m3)|0,990000|24|5,000000|15,000000|4|1800,000000|Falsch|Falsch|Falsch|0|4.1.2|1,000000|0,000000|0,000000|0,000000|NEIN' + CHAR(13) + CHAR(10)
    + N'G1S3=Polystyrol PS -Partikelschaum  (WLG 035 - > 30 kg/m3)|0,035000|16|80,000000|250,000000|5|30,000000|Falsch|Falsch|Falsch|0|5.5.1.1.1.2|1,500000|0,000000|0,000000|0,000000|NEIN' + CHAR(13) + CHAR(10)
    + N'G1S4=Putzmoertel aus Kalk, Kalkzement und hydraulischem Kalk|0,700000|0,5|15,000000|35,000000|1|1400,000000|Falsch|Falsch|Falsch|0|1.1.1|1,000000|0,000000|0,000000|0,000000|NEIN' + CHAR(13) + CHAR(10)
    + N'KorrLS=Falsch|0|-1' + CHAR(13) + CHAR(10)
    + N'KorrBe=version2008|Falsch|6|0|0|0|-1|0' + CHAR(13) + CHAR(10)
    + N'KorrUD=Falsch|0|0|0|-1';

-- ============================================================
-- Pruefe ob Katalog schon existiert
-- ============================================================
IF EXISTS (SELECT 1 FROM TcCatalog WHERE ProjectUId = @ProjUId)
BEGIN
    PRINT N'WARNUNG: Katalog fuer dieses Projekt existiert bereits!';
    SELECT @CatalogUId = UId, @TimUId = TIMUId FROM TcCatalog WHERE ProjectUId = @ProjUId;
    SELECT @CatContentUId = UId FROM TcCatalogContent WHERE CatalogUId = @CatalogUId AND CatalogContainerType = 6;
    PRINT N'Verwende vorhandenen Katalog: ' + CAST(@CatalogUId AS nvarchar(36));
END
ELSE
BEGIN
    -- ============================================================
    -- 1) TcCatalog: Bauteilkatalog fuer das Projekt
    -- ============================================================
    INSERT INTO TcCatalog (
        [UId],[TIMUId],[OId],[SortNum],[ShortDesc],[LongDesc],[InfoDesc],
        [Version],[MajorVersion],[MinorVersion],[ReleaseVersion],[BuildVersion],
        [ManufacturerUId],[RegionUId],[LanguageType],[LanguageLCID],
        [Iso3166CountryType],[CatalogStateType],[EditModeType],[StateType],
        [VariantType],[GeneratorType],[StampEdit],[StampCreate],
        [SyncType],[SyncCreate],[SyncEdit],[SyncVersion],[SyncMeta],
        [ProjectUId],[SeqNum],[VariantRoot],[StampSync],
        [CatalogType],[BodyText],[MatchCode],
        [GId],[CatalogSourceType],[BodyTextType],[DateRevised],
        [MId],[SyncStamp],[SyncRowVersion]
    ) VALUES (
        @CatalogUId, @TimUId, -1, -1, N'', N'Bauteilkatalog', N'Vom Modul Bauteilkatalog erstellter Katalog',
        N'', -1, -1, -1, -1,
        @NullGuid, @NullGuid, 0, 0,
        1, 0, 0, 0,
        0, 0, @Now, @Now,
        1, @NullGuid, @NullGuid, N'1.3.8', @SyncMeta,
        @ProjUId, -1, N'', @Epoch,
        0, N'', N'',
        @CatalogUId, 0, 0, @Epoch,
        @NullGuid, @SyncNow, NEWID()
    );
    PRINT N'TcCatalog erstellt: ' + CAST(@CatalogUId AS nvarchar(36));

    -- ============================================================
    -- 2) TcCatalogContent: Ordner "Benutzerdefinierte Bauteile"
    -- ============================================================
    INSERT INTO TcCatalogContent (
        [UId],[OId],[ReferenceUId],[CatalogUId],[ContentLevel],[SortNum],
        [ShortDesc],[LongDesc],[InfoDesc],
        [RegionUId],[DataSourceUId],[ContentType],
        [CatalogStateType],[EditModeType],[StateType],[VariantType],[GeneratorType],
        [StampEdit],[StampCreate],
        [SyncType],[SyncCreate],[SyncEdit],[SyncVersion],[SyncMeta],
        [SeqNum],[CategoryType],[GroupType],[BasisType],[SubType],
        [ValidStartDate],[ValidEndDate],[VariantRoot],[StampSync],
        [CategoryName],[ProjectUId],[BodyText],
        [GId],[BodyTextType],[CatalogContainerType],
        [MId],[SyncStamp],[SyncRowVersion]
    ) VALUES (
        @CatContentUId, -1, @NullGuid, @CatalogUId, 7, -1,
        N'', N'=== Benutzerdefinierte Bauteile ===', N'Vom Modul Bauteilkatalog erstellter Bauteilkatalog-Inhalt',
        @NullGuid, @NullGuid, 1,
        0, 0, 0, 0, 0,
        @Now, @Now,
        1, @NullGuid, @NullGuid, N'1.3.4', @SyncMeta,
        -1, 0, 0, 0, 0,
        @Epoch, @Epoch, N'', @Epoch,
        N'', @ProjUId, N'',
        @CatContentUId, 0, 6,
        @NullGuid, @SyncNow, NEWID()
    );
    PRINT N'TcCatalogContent (Ordner) erstellt: ' + CAST(@CatContentUId AS nvarchar(36));
END;

-- ============================================================
-- 3) TcBasis: Katalog-Basiseintrag
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
    1, @NullGuid, @NullGuid, N'1.3.1.3', @SyncMeta, @SyncNow, NEWID(),
    0, N'',
    @NullVal, @NullVal, @NullVal, @NullVal, @NullVal, @NullVal,
    @NullVal, @NullVal, @NullVal, @NullVal, @NullVal, @NullVal,
    -1, 0,
    0, 0, 0,
    0, 0, 0, 0
);
PRINT N'TcBasis erstellt: ' + CAST(@BasisUId AS nvarchar(36));

-- ============================================================
-- 4) TcBuildingElementDimension: Bauteil-Definition
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
    @BasisUId, 0.42, 0, 0,
    @NullVal, @NullVal, @NullVal, @NullVal, @NullVal,
    @NullVal, @NullVal, @NullVal, @NullVal, @NullVal,
    0.199189, 4.850408,
    0.13, 0.04,
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
PRINT N'TcBuildingElementDimension erstellt: ' + CAST(@DimUId AS nvarchar(36));

-- ============================================================
-- 5) TcCatalogContents: Bauteil im Katalogbaum sichtbar machen
-- ============================================================
INSERT INTO TcCatalogContents (
    [UId],[CatalogContentUId],[BasisUId],[DimensionUId],
    [OId],[SeqNum],[SortNum],[ShortDesc],[LongDesc],[InfoDesc],
    [ElementType],[CategoryType],[GroupType],[BasisType],[SubType],[FavoriteType],[MatchCode],
    [CatalogUId],[RefUId],
    [CatalogStateType],[EditModeType],[StateType],[VariantType],[VariantRoot],[GeneratorType],
    [StampCreate],[StampEdit],[StampSync],
    [ProjectUId],[MId],[ContainerType],
    [SyncType],[SyncCreate],[SyncEdit],[SyncVersion],[SyncMeta],[SyncStamp],[SyncRowVersion]
) VALUES (
    @CatEntryUId, @CatContentUId, @BasisUId, @NullGuid,
    -1, -1, -1, N'', @BauteilName, N'',
    2, 0, 1, 0, 0, 0, N'',
    @CatalogUId, @NullGuid,
    0, 0, 0, 0, N'', 0,
    @Now, @Now, @Now,
    @ProjUId, @NullGuid, 0,
    2, @NullGuid, @NullGuid, N'1.3.3', @SyncMeta, @SyncNow, NEWID()
);
PRINT N'TcCatalogContents erstellt: ' + CAST(@CatEntryUId AS nvarchar(36));

-- ============================================================
-- 6) Layers: 4 Schichten
-- ============================================================
-- Schicht 0: Gipsputz (innen) 15mm
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
) VALUES (
    @Layer0, @Layer0, @DimUId, @NullGuid, -1, 0, -1,
    N'', N'Gipsputz ohne Zuschlag', N'',
    0, 0, 0, 0,
    @NullGuid, 1, 0, N'',
    0.51, 0.0294117647058824, @NullVal, 1200, 1.0, 0.015,
    @NullVal, @NullVal,
    10, 35,
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
);

-- Schicht 1: Kalksandstein KS 1800 240mm
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
) VALUES (
    @Layer1, @Layer1, @DimUId, @NullGuid, -1, 1, -1,
    N'', N'Kalksandstein, NM/DM  (1800 kg/m3)', N'',
    0, 0, 0, 0,
    @NullGuid, 4, 0, N'',
    0.99, 0.242424242424242, @NullVal, 1800, 1.0, 0.24,
    @NullVal, @NullVal,
    5, 15,
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
);

-- Schicht 2: EPS WLS 035 160mm (Daemmschicht)
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
) VALUES (
    @Layer2, @Layer2, @DimUId, @NullGuid, -1, 2, -1,
    N'', N'Polystyrol PS -Partikelschaum  (WLG 035 - > 30 kg/m3)', N'',
    3, 0, 0, 0,
    @NullGuid, 5, 1, N'',
    0.035, 4.57142857142857, @NullVal, 30, 1.5, 0.16,
    @NullVal, @NullVal,
    80, 250,
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
);

-- Schicht 3: Armierungsputz (aussen) 5mm
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
) VALUES (
    @Layer3, @Layer3, @DimUId, @NullGuid, -1, 3, -1,
    N'', N'Putzmoertel aus Kalk, Kalkzement und hydraulischem Kalk', N'',
    0, 0, 0, 0,
    @NullGuid, 1, 0, N'',
    0.70, 0.00714285714285714, @NullVal, 1400, 1.0, 0.005,
    @NullVal, @NullVal,
    15, 35,
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
);

PRINT N'';
PRINT N'=== Bauteil "' + @BauteilName + N'" komplett erstellt ===';
PRINT N'Projekt:   Werner Grotz (' + CAST(@ProjUId AS nvarchar(36)) + N')';
PRINT N'CatalogUId:   ' + CAST(@CatalogUId AS nvarchar(36));
PRINT N'CatContentUId: ' + CAST(@CatContentUId AS nvarchar(36));
PRINT N'TIMUId:    ' + CAST(@TimUId AS nvarchar(36));
PRINT N'BasisUId:  ' + CAST(@BasisUId AS nvarchar(36));
PRINT N'DimUId:    ' + CAST(@DimUId AS nvarchar(36));
PRINT N'CatEntryUId: ' + CAST(@CatEntryUId AS nvarchar(36));
PRINT N'4 Schichten: Gipsputz 15mm | KS1800 240mm | EPS-WLS035 160mm | Armierungsputz 5mm';
GO
