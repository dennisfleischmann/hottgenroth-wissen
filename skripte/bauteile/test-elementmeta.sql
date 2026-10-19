SET NOCOUNT ON;

DECLARE @Rsi float = 0.13;
DECLARE @Rse float = 0.04;

DECLARE @L TABLE (
    SortNum int, Name nvarchar(200), Lambda float, Dicke float,
    Rohdichte float, WKapazitaet float, MuUnten float, MuOben float,
    MatGruppe int, KatPfad nvarchar(50)
);

INSERT INTO @L VALUES
 (0, N'Gipsputz ohne Zuschlag',                                   0.51,  0.015, 1200, 1.0, 10,  35, 1, N'1.1.2'),
 (1, N'Kalksandstein, NM/DM  (1800 kg/m3)',                       0.99,  0.240, 1800, 1.0,  5,  15, 4, N'4.1.2'),
 (2, N'Polystyrol PS -Partikelschaum  (WLG 035 - > 30 kg/m3)',    0.035, 0.160,   30, 1.5, 80, 250, 5, N'5.5.1.1.1.2'),
 (3, N'Putzmoertel aus Kalk, Kalkzement und hydraulischem Kalk',  0.70,  0.005, 1400, 1.0, 15,  35, 1, N'1.1.1');

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

SET @ElementMeta = REPLACE(@ElementMeta, N',00|', N'|');
SET @ElementMeta = REPLACE(@ElementMeta, N',50|', N',5|');

PRINT @ElementMeta;

PRINT '';
PRINT '--- Kennwerte ---';
DECLARE @R float, @D float;
SELECT @R = SUM(Dicke / Lambda), @D = SUM(Dicke) FROM @L;
PRINT 'Thickness = ' + CONVERT(nvarchar(30), @D);
PRINT 'RValue    = ' + CONVERT(nvarchar(30), @R);
PRINT 'UValue    = ' + CONVERT(nvarchar(30), 1.0 / (@R + @Rsi + @Rse));
