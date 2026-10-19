-- Beispiel-Bauteil: WDVS-sanierte Außenwand
-- Erstellt per SQL INSERT in das aktive Hottgenroth-Projekt
-- Schichtaufbau (innen → außen):
--   0: Gipsputz 1.5 cm
--   1: Kalksandstein KS 1800  24 cm
--   2: EPS Dämmung WLS 035   16 cm
--   3: Armierungsputz          0.5 cm
-- U = 0.199 W/(m²K), Dicke = 42 cm

USE HsetuPrjData;
GO

DECLARE @DimUId   uniqueidentifier = 'D2306321-4DAF-4440-B3F4-BA0A4F052BCE';
DECLARE @BasisUId uniqueidentifier = 'F095CD80-0A7C-4BE4-BB4C-B487128CE221';
DECLARE @Layer0   uniqueidentifier = '46B668C0-41BA-464F-B88E-5D81381CE50C';
DECLARE @Layer1   uniqueidentifier = 'AAB0E713-B885-42BD-8A76-491D6E386B98';
DECLARE @Layer2   uniqueidentifier = '8BE6908E-6179-41BE-998F-DB307C98CA4E';
DECLARE @Layer3   uniqueidentifier = '9E640746-F299-41CB-9527-D8DAE613A551';
DECLARE @ProjUId  uniqueidentifier = 'B5CF9F01-9DDF-4C79-A164-A6D73B097DE2';
DECLARE @NullGuid uniqueidentifier = 'AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA';
DECLARE @NullVal  float = -987654321.99;
DECLARE @Now      datetime = GETDATE();

-- 1) Bauteil-Definition (TcBuildingElementDimension)
INSERT INTO TcBuildingElementDimension (
    UId, BasisUId, OId, SortNum, ShortDesc, LongDesc,
    Thickness, UValue, RValue,
    InternalCoefficientOfHeatTransfer, ExternalCoefficientOfHeatTransfer,
    IsVentilated, FractionOfFrame, GValue, ShadingCoefficient,
    CatalogStateType, EditModeType, StateType, VariantType, GeneratorType,
    StampEdit, StampCreate,
    SyncType, SeqNum,
    ProjectUId, GId
) VALUES (
    @DimUId, @BasisUId, -1, 200, NULL, N'WA-Außenwand-WDVS-Beispiel',
    0.42, 0.199189, 4.850408,
    0.13, 0.04,
    0, @NullVal, @NullVal, @NullVal,
    0, 0, 0, 0, 0,
    @Now, @Now,
    0, -1,
    @ProjUId, @DimUId
);

-- 2) Schicht 0: Gipsputz (innen)
INSERT INTO TcBuildingElementDimensionLayer (
    UId, DimensionUId, LayerSectionUId, OId, SortNum, LongDesc,
    LayerType, MaterialGroupType, MaterialType,
    ThermalConductivity, Density, HeatCapacity, Thickness,
    DiffusionResistanceCoefficient, Emissivity, IsVentilated,
    CatalogStateType, EditModeType, StateType, VariantType, GeneratorType,
    StampEdit, StampCreate, SyncType, SeqNum,
    ProjectUId, GId, MaterialUId, EN6946UgType
) VALUES (
    @Layer0, @DimUId, @NullGuid, -1, 0, N'Gipsputz ohne Zuschlag',
    0, 1, 0,
    0.51, 1200.0, 1.0, 0.015,
    @NullVal, @NullVal, 0,
    0, 0, 0, 0, 0,
    @Now, @Now, 0, -1,
    @ProjUId, @Layer0, @NullGuid, 0
);

-- 3) Schicht 1: Kalksandstein KS 1800
INSERT INTO TcBuildingElementDimensionLayer (
    UId, DimensionUId, LayerSectionUId, OId, SortNum, LongDesc,
    LayerType, MaterialGroupType, MaterialType,
    ThermalConductivity, Density, HeatCapacity, Thickness,
    DiffusionResistanceCoefficient, Emissivity, IsVentilated,
    CatalogStateType, EditModeType, StateType, VariantType, GeneratorType,
    StampEdit, StampCreate, SyncType, SeqNum,
    ProjectUId, GId, MaterialUId, EN6946UgType
) VALUES (
    @Layer1, @DimUId, @NullGuid, -1, 1, N'Kalksandstein, NM/DM  (1800 kg/m³)',
    0, 4, 0,
    0.99, 1800.0, 1.0, 0.24,
    @NullVal, @NullVal, 0,
    0, 0, 0, 0, 0,
    @Now, @Now, 0, -1,
    @ProjUId, @Layer1, @NullGuid, 0
);

-- 4) Schicht 2: EPS Dämmung WLS 035
INSERT INTO TcBuildingElementDimensionLayer (
    UId, DimensionUId, LayerSectionUId, OId, SortNum, LongDesc,
    LayerType, MaterialGroupType, MaterialType,
    ThermalConductivity, Density, HeatCapacity, Thickness,
    DiffusionResistanceCoefficient, Emissivity, IsVentilated,
    CatalogStateType, EditModeType, StateType, VariantType, GeneratorType,
    StampEdit, StampCreate, SyncType, SeqNum,
    ProjectUId, GId, MaterialUId, EN6946UgType
) VALUES (
    @Layer2, @DimUId, @NullGuid, -1, 2, N'Polystyrol PS -Partikelschaum  (WLG 035 - > 30 kg/m³)',
    3, 5, 1,
    0.035, 30.0, 1.5, 0.16,
    @NullVal, @NullVal, 0,
    0, 0, 0, 0, 0,
    @Now, @Now, 0, -1,
    @ProjUId, @Layer2, @NullGuid, 0
);

-- 5) Schicht 3: Armierungsputz (außen)
INSERT INTO TcBuildingElementDimensionLayer (
    UId, DimensionUId, LayerSectionUId, OId, SortNum, LongDesc,
    LayerType, MaterialGroupType, MaterialType,
    ThermalConductivity, Density, HeatCapacity, Thickness,
    DiffusionResistanceCoefficient, Emissivity, IsVentilated,
    CatalogStateType, EditModeType, StateType, VariantType, GeneratorType,
    StampEdit, StampCreate, SyncType, SeqNum,
    ProjectUId, GId, MaterialUId, EN6946UgType
) VALUES (
    @Layer3, @DimUId, @NullGuid, -1, 3, N'Putzmörtel aus Kalk, Kalkzement und hydraulischem Kalk',
    0, 1, 0,
    0.70, 1400.0, 1.0, 0.005,
    @NullVal, @NullVal, 0,
    0, 0, 0, 0, 0,
    @Now, @Now, 0, -1,
    @ProjUId, @Layer3, @NullGuid, 0
);

PRINT 'Bauteil "WA-Außenwand-WDVS-Beispiel" mit 4 Schichten erstellt.';
PRINT 'UId: ' + CAST(@DimUId AS nvarchar(36));
GO
