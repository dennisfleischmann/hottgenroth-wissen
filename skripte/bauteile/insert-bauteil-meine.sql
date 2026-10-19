-- Bauteil: WA-Außenwand-WDVS-Test (4 Schichten)
-- Ziel: "Meine Bauteile" (HsetuUsrData, projektübergreifend)

USE HsetuUsrData;
GO

DECLARE @DimUId   uniqueidentifier = NEWID();
DECLARE @BasisUId uniqueidentifier = NEWID();
DECLARE @Layer0   uniqueidentifier = NEWID();
DECLARE @Layer1   uniqueidentifier = NEWID();
DECLARE @Layer2   uniqueidentifier = NEWID();
DECLARE @Layer3   uniqueidentifier = NEWID();
DECLARE @NullGuid uniqueidentifier = 'AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA';
DECLARE @NullVal  float = -987654321.99;
DECLARE @Now      datetime = GETDATE();
DECLARE @SyncNow  datetime = DATEADD(hour, -2, GETDATE());

-- Nächste SortNum ermitteln
DECLARE @NextSort int;
SELECT @NextSort = ISNULL(MAX(SortNum), 0) + 10 FROM TcBuildingElementDimension;

-- Bauteil-Definition
INSERT INTO TcBuildingElementDimension (
    UId, BasisUId, OId, SortNum, LongDesc,
    Thickness, UValue, RValue,
    InternalCoefficientOfHeatTransfer, ExternalCoefficientOfHeatTransfer,
    IsVentilated, FractionOfFrame, GValue, ShadingCoefficient,
    CatalogStateType, EditModeType, StateType, VariantType, GeneratorType,
    StampEdit, StampCreate, SeqNum,
    SyncType, SyncVersion, SyncMeta, SyncCreate, SyncEdit, SyncStamp, SyncRowVersion,
    RawThickness, FinalThickness,
    ProjectUId, GId,
    ElementMeta
) VALUES (
    @DimUId, @BasisUId, -1, @NextSort, N'WA-Außenwand-WDVS-Test',
    0.42, 0.199189, 4.850408,
    0.13, 0.04,
    0, @NullVal, @NullVal, @NullVal,
    0, 0, 0, 0, 0,
    @Now, @Now, -1,
    2, N'1.3.1.5', N'{"meta":{"sync":{"mod":"6.6.0","dal":"17.3"}}}',
    @NullGuid, @NullGuid, @SyncNow, NEWID(),
    0.0, 0.0,
    @NullGuid, @DimUId,
    N'RAI=0,13
RAA=0,04
CP10CM=4800
CP3CM=16000
CPEnIso13786=5020
G1S1=Gipsputz ohne Zuschlag|0,510000|1,5|10,000000|35,000000|1|1200,000000|Falsch|Falsch|Falsch|0|1.1.2|1,000000|0,000000|0,000000|0,000000|NEIN
G1S2=Kalksandstein, NM/DM  (1800 kg/m³)|0,990000|24|5,000000|15,000000|4|1800,000000|Falsch|Falsch|Falsch|0|4.1.2|1,000000|0,000000|0,000000|0,000000|NEIN
G1S3=Polystyrol PS -Partikelschaum  (WLG 035 - > 30 kg/m³)|0,035000|16|80,000000|250,000000|5|30,000000|Falsch|Falsch|Falsch|0|5.5.1.1.1.2|1,500000|0,000000|0,000000|0,000000|NEIN
G1S4=Putzmörtel aus Kalk, Kalkzement und hydraulischem Kalk|0,700000|0,5|15,000000|35,000000|1|1400,000000|Falsch|Falsch|Falsch|0|1.1.1|1,000000|0,000000|0,000000|0,000000|NEIN
KorrLS=Falsch|0|-1
KorrBe=version2008|Falsch|6|0|0|0|-1|0
KorrUD=Falsch|0|0|0|-1
'
);

-- Schicht 0: Gipsputz (innen)
INSERT INTO TcBuildingElementDimensionLayer (
    UId, DimensionUId, LayerSectionUId, OId, SortNum, LongDesc,
    LayerType, MaterialGroupType, MaterialType,
    ThermalConductivity, Density, HeatCapacity, Thickness,
    DiffusionResistanceCoefficient, Emissivity, IsVentilated,
    CatalogStateType, EditModeType, StateType, VariantType, GeneratorType,
    StampEdit, StampCreate, SeqNum,
    SyncType, SyncVersion, SyncMeta, SyncCreate, SyncEdit, SyncStamp, SyncRowVersion,
    ProjectUId, GId, MaterialUId, EN6946UgType
) VALUES (
    @Layer0, @DimUId, @NullGuid, -1, 0, N'Gipsputz ohne Zuschlag',
    0, 1, 0,
    0.51, 1200.0, 1.0, 0.015,
    @NullVal, @NullVal, 0,
    0, 0, 0, 0, 0,
    @Now, @Now, -1,
    2, N'1.3.1.8', N'{"meta":{"sync":{"mod":"6.6.0","dal":"17.3"}}}',
    @NullGuid, @NullGuid, @SyncNow, NEWID(),
    @NullGuid, @Layer0, @NullGuid, 0
);

-- Schicht 1: Kalksandstein KS 1800
INSERT INTO TcBuildingElementDimensionLayer (
    UId, DimensionUId, LayerSectionUId, OId, SortNum, LongDesc,
    LayerType, MaterialGroupType, MaterialType,
    ThermalConductivity, Density, HeatCapacity, Thickness,
    DiffusionResistanceCoefficient, Emissivity, IsVentilated,
    CatalogStateType, EditModeType, StateType, VariantType, GeneratorType,
    StampEdit, StampCreate, SeqNum,
    SyncType, SyncVersion, SyncMeta, SyncCreate, SyncEdit, SyncStamp, SyncRowVersion,
    ProjectUId, GId, MaterialUId, EN6946UgType
) VALUES (
    @Layer1, @DimUId, @NullGuid, -1, 1, N'Kalksandstein, NM/DM  (1800 kg/m³)',
    0, 4, 0,
    0.99, 1800.0, 1.0, 0.24,
    @NullVal, @NullVal, 0,
    0, 0, 0, 0, 0,
    @Now, @Now, -1,
    2, N'1.3.1.8', N'{"meta":{"sync":{"mod":"6.6.0","dal":"17.3"}}}',
    @NullGuid, @NullGuid, @SyncNow, NEWID(),
    @NullGuid, @Layer1, @NullGuid, 0
);

-- Schicht 2: EPS Dämmung WLS 035
INSERT INTO TcBuildingElementDimensionLayer (
    UId, DimensionUId, LayerSectionUId, OId, SortNum, LongDesc,
    LayerType, MaterialGroupType, MaterialType,
    ThermalConductivity, Density, HeatCapacity, Thickness,
    DiffusionResistanceCoefficient, Emissivity, IsVentilated,
    CatalogStateType, EditModeType, StateType, VariantType, GeneratorType,
    StampEdit, StampCreate, SeqNum,
    SyncType, SyncVersion, SyncMeta, SyncCreate, SyncEdit, SyncStamp, SyncRowVersion,
    ProjectUId, GId, MaterialUId, EN6946UgType
) VALUES (
    @Layer2, @DimUId, @NullGuid, -1, 2, N'Polystyrol PS -Partikelschaum  (WLG 035 - > 30 kg/m³)',
    3, 5, 1,
    0.035, 30.0, 1.5, 0.16,
    @NullVal, @NullVal, 0,
    0, 0, 0, 0, 0,
    @Now, @Now, -1,
    2, N'1.3.1.8', N'{"meta":{"sync":{"mod":"6.6.0","dal":"17.3"}}}',
    @NullGuid, @NullGuid, @SyncNow, NEWID(),
    @NullGuid, @Layer2, @NullGuid, 0
);

-- Schicht 3: Armierungsputz (außen)
INSERT INTO TcBuildingElementDimensionLayer (
    UId, DimensionUId, LayerSectionUId, OId, SortNum, LongDesc,
    LayerType, MaterialGroupType, MaterialType,
    ThermalConductivity, Density, HeatCapacity, Thickness,
    DiffusionResistanceCoefficient, Emissivity, IsVentilated,
    CatalogStateType, EditModeType, StateType, VariantType, GeneratorType,
    StampEdit, StampCreate, SeqNum,
    SyncType, SyncVersion, SyncMeta, SyncCreate, SyncEdit, SyncStamp, SyncRowVersion,
    ProjectUId, GId, MaterialUId, EN6946UgType
) VALUES (
    @Layer3, @DimUId, @NullGuid, -1, 3, N'Putzmörtel aus Kalk, Kalkzement und hydraulischem Kalk',
    0, 1, 0,
    0.70, 1400.0, 1.0, 0.005,
    @NullVal, @NullVal, 0,
    0, 0, 0, 0, 0,
    @Now, @Now, -1,
    2, N'1.3.1.8', N'{"meta":{"sync":{"mod":"6.6.0","dal":"17.3"}}}',
    @NullGuid, @NullGuid, @SyncNow, NEWID(),
    @NullGuid, @Layer3, @NullGuid, 0
);

PRINT N'Bauteil "WA-Außenwand-WDVS-Test" in Meine Bauteile erstellt.';
PRINT 'UId: ' + CAST(@DimUId AS nvarchar(36));
PRINT 'SortNum: ' + CAST(@NextSort AS nvarchar(10));
GO
