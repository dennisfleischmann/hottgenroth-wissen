<?php
/**
 * Baut aus den CSV-Ausleitungen die Arbeitsmappe "Hottgenroth-Bauteile.xlsx".
 *
 * Aufruf:  php baue-excel.php <csv-verzeichnis> <zieldatei.xlsx>
 */

require 'C:/Projekte_Dev/energieberatung/vendor/autoload.php';

use PhpOffice\PhpSpreadsheet\Spreadsheet;
use PhpOffice\PhpSpreadsheet\Writer\Xlsx;
use PhpOffice\PhpSpreadsheet\Style\Alignment;
use PhpOffice\PhpSpreadsheet\Style\Border;
use PhpOffice\PhpSpreadsheet\Style\Fill;
use PhpOffice\PhpSpreadsheet\Cell\DataType;

[$_, $csvDir, $ziel] = $argv + [null, null, null];
if (!$csvDir || !$ziel) {
    fwrite(STDERR, "Aufruf: php baue-excel.php <csv-verzeichnis> <zieldatei.xlsx>\n");
    exit(1);
}

// ---------------------------------------------------------------- Wörterbücher

/** TTechDataBuildingElementType — steht in TcBasis.GroupType. */
const BAUTEILART = [
    0 => 'ohne Angabe',      1 => 'Wand',             2 => 'Tür',
    3 => 'Fenster',          4 => 'Geschossbauteil',  5 => 'Dach',
    6 => 'Stütze',           7 => 'Träger',           8 => 'Gaube',
    9 => 'Podest',          10 => 'Treppe',          11 => 'Bodenplatte',
    12 => 'Schacht',        13 => 'Öffnung',         14 => 'Fassade',
    15 => 'Rollladenkasten', 16 => 'Nische',          17 => 'Wärmebrücke',
    18 => 'Verschattung',   19 => 'Außenluftdurchlass', 20 => 'Akustik',
    21 => 'Fuge',
];

/** TTechDataBuildingElementLayerType — TcBuildingElementDimensionLayer.LayerType. */
const SCHICHTART = [
    0 => '',                 1 => 'Standard',        2 => 'belüftet',
    3 => 'Dämmung',          4 => 'Wärmereflexion',  5 => 'Element',
    6 => 'Lattung',          7 => 'Konterlattung',   8 => 'Folie',
    9 => 'Systemelement',   10 => 'Sparren',        11 => 'Dampfsperre',
    12 => 'Grundelement',   13 => 'Belag',          14 => 'Estrich',
    15 => 'Putz',
];

/** TMaterialGroupType — TcBuildingElementDimensionLayer.MaterialGroupType. */
const STOFFGRUPPE = [
    0 => '',           1 => 'Putze',      2 => 'Baustoffe',  3 => 'Platten',
    4 => 'Mauerwerk',  5 => 'Dämmstoffe', 6 => 'Holz',       7 => 'Beläge',
    8 => 'Sonstige',   9 => 'Systemplatten',
];

// ---------------------------------------------------------------- Hilfsmittel

/**
 * Die Ordnernamen der Software sind gesperrt gesetzt: "A u ß e n w ä n d e".
 * Zwei Leerzeichen sind dabei Rauschen innerhalb eines Wortes, drei und mehr
 * trennen Wörter. Mehrzeichige Wortteile bleiben, wie sie sind.
 */
function entsperre(string $s): string
{
    $s = trim($s);
    $s = trim($s, "= \t\n\r");
    $s = trim($s);
    if ($s === '') {
        return '';
    }

    $teile = explode(' ', $s);
    $raus = [];
    $puffer = '';
    $luecke = 0;

    foreach ($teile as $t) {
        if ($t === '') {
            $luecke++;
            continue;
        }
        if (mb_strlen($t) > 1) {
            if ($puffer !== '') { $raus[] = $puffer; $puffer = ''; }
            $raus[] = $t;
            $luecke = 0;
            continue;
        }
        // Einzelnes Zeichen: gehört zum gesperrten Wort, sofern die Lücke klein war.
        if ($luecke >= 2 && $puffer !== '') { $raus[] = $puffer; $puffer = ''; }
        $puffer .= $t;
        $luecke = 0;
    }
    if ($puffer !== '') { $raus[] = $puffer; }

    return preg_replace('/\s+/u', ' ', implode(' ', $raus));
}

/** Ordnerpfad säubern und die im Elternteil schon gesagte Hälfte kürzen. */
function ordnerpfad(string $roh): string
{
    if (trim($roh) === '') {
        return '';
    }
    $teile = array_map('entsperre', explode(' > ', $roh));
    $teile = array_values(array_filter($teile, fn ($t) => $t !== ''));

    for ($i = count($teile) - 1; $i > 0; $i--) {
        $eltern = $teile[$i - 1];
        if (str_starts_with($teile[$i], $eltern)) {
            $rest = ltrim(mb_substr($teile[$i], mb_strlen($eltern)), " |›>-");
            if ($rest !== '') { $teile[$i] = $rest; }
        }
    }

    return implode(' › ', $teile);
}

/**
 * Die Typologie-Ordner tragen Region, Baualtersklasse und Gebäudetyp in einem
 * Namen: "TYPOLOGIE Bremen | 1919-1948 | Ein-/Zweifamilien-Reihenhaus". Die
 * Klasse steht dabei in der Mitte, nicht am Ende — beides sind eigene Spalten
 * wert, weil sich danach filtern lässt.
 *
 * @return array{0: string, 1: string} Baualtersklasse, Gebäudetyp
 */
function ordnerTeile(string $roh): array
{
    if (!str_contains($roh, '|')) {
        return ['', ''];
    }
    $tief = explode(' > ', $roh);
    $stuecke = array_map('entsperre', explode('|', end($tief)));

    $klasse = '';
    $typ = '';
    foreach (array_slice($stuecke, 1) as $s) {
        if ($s === '') {
            continue;
        }
        // "Neubau" und "beliebig" stehen im selben Feld wie die Jahreszahlen.
        if ($klasse === '' && preg_match('/\d{4}|^(vor|ab|bis|nach)\b|^(Neubau|beliebig)$/iu', $s)) {
            $klasse = $s;
            continue;
        }
        $typ = $s;
    }

    return [$klasse, $typ];
}

function zahl(string $s): ?float
{
    $s = trim($s);
    if ($s === '') {
        return null;
    }
    $w = (float) $s;

    return $w;
}

/** U-Wert, Dicke & Co: 0 heißt in diesen Tabellen "nicht angegeben". */
function kennwert(string $s): ?float
{
    $w = zahl($s);

    return ($w === null || $w <= 0.0) ? null : $w;
}

function liesCsv(string $pfad): array
{
    $h = fopen($pfad, 'r');
    if (!$h) {
        throw new RuntimeException("nicht lesbar: $pfad");
    }
    $kopf = fgetcsv($h, 0, ';', '"', '');
    // Die Stückliste (BOM) steht vor dem öffnenden Anführungszeichen, deshalb
    // liest fgetcsv das erste Kopffeld als unquotiert — die Zeichen bleiben stehen.
    if ($kopf && isset($kopf[0])) {
        $kopf[0] = trim(preg_replace('/^\x{FEFF}/u', '', $kopf[0]), '"');
    }
    $zeilen = [];
    while (($r = fgetcsv($h, 0, ';', '"', '')) !== false) {
        if (count($r) === 1 && ($r[0] === null || $r[0] === '')) {
            continue;
        }
        $zeilen[] = array_combine($kopf, array_pad(array_slice($r, 0, count($kopf)), count($kopf), ''));
    }
    fclose($h);

    return $zeilen;
}

// ---------------------------------------------------------------- Einlesen

$katalog   = liesCsv("$csvDir/katalog-bauteile.csv");
$katSchicht = liesCsv("$csvDir/katalog-schichten.csv");
$meine     = liesCsv("$csvDir/meine-bauteile.csv");
$meinSchicht = liesCsv("$csvDir/meine-schichten.csv");
$projekt   = liesCsv("$csvDir/projekt-bauteile.csv");

fwrite(STDERR, sprintf(
    "gelesen: Katalog %d, Katalogschichten %d, Meine %d, Meine Schichten %d, Projekt %d\n",
    count($katalog), count($katSchicht), count($meine), count($meinSchicht), count($projekt)
));

/** Schichten je Bauteil, damit auf dem Hauptblatt ein Aufbau stehen kann. */
function schichtenNachBauteil(array $zeilen): array
{
    $k = [];
    foreach ($zeilen as $z) {
        $k[$z['BauteilId']][] = $z;
    }

    return $k;
}

/**
 * Kurzfassung des Aufbaus, innen nach außen. Bei inhomogenen Bauteilen zählt
 * das flächenmäßig größte Gefach — sonst stünde dort ein zufälliger Schnitt.
 */
function aufbauText(array $schichten): string
{
    if (!$schichten) {
        return '';
    }
    $nachSektion = [];
    foreach ($schichten as $s) {
        $nachSektion[$s['Sektion']][] = $s;
    }
    $beste = null;
    $bestAnteil = -1.0;
    foreach ($nachSektion as $nr => $liste) {
        $anteil = (float) ($liste[0]['SektionAnteil'] !== '' ? $liste[0]['SektionAnteil'] : 100.0);
        if ($anteil > $bestAnteil) {
            $bestAnteil = $anteil;
            $beste = $liste;
        }
    }
    usort($beste, fn ($a, $b) => (int) $a['Nr'] <=> (int) $b['Nr']);

    $stuecke = [];
    foreach ($beste as $s) {
        $name = trim(preg_replace('/\s+/u', ' ', $s['Schicht']));
        $d = kennwert($s['Dicke']);
        $l = kennwert($s['Lambda']);
        $zusatz = [];
        if ($d !== null) { $zusatz[] = number_format($d * 100, 1, ',', '') . ' cm'; }
        if ($l !== null) { $zusatz[] = 'λ ' . rtrim(rtrim(number_format($l, 3, ',', ''), '0'), ','); }
        $stuecke[] = $name . ($zusatz ? ' (' . implode('; ', $zusatz) . ')' : '');
    }
    $text = implode(' → ', $stuecke);
    if (count($nachSektion) > 1) {
        $text .= sprintf('   [inhomogen, %d Gefache; gezeigt: größtes]', count($nachSektion));
    }

    return mb_strlen($text) > 900 ? mb_substr($text, 0, 897) . '…' : $text;
}

$katAufbau  = schichtenNachBauteil($katSchicht);
$meinAufbau = schichtenNachBauteil($meinSchicht);

// ---------------------------------------------------------------- Mappe

$mappe = new Spreadsheet();
$mappe->getProperties()
    ->setCreator('FS Energieberatung')
    ->setTitle('Bauteile aus Hottgenroth')
    ->setSubject('Bauteilbestand der Hottgenroth-/ETU-Energieberatersoftware')
    ->setDescription('Ausgelesen aus der LocalDB-Instanz (localdb)\\HSETU am ' . date('d.m.Y'));

const KOPF_FARBE = '1F3864';
const ZEBRA      = 'F2F5FA';

function blatt(Spreadsheet $mappe, string $name, int $pos)
{
    // Das erste Blatt gibt es beim Anlegen der Mappe schon; legte man daneben
    // ein neues an, bliebe ein leeres "Worksheet" stehen.
    static $ersteBenutzt = false;
    $b = $ersteBenutzt ? $mappe->createSheet() : $mappe->getActiveSheet();
    $ersteBenutzt = true;
    $b->setTitle($name);

    return $b;
}

/**
 * Schreibt ein Tabellenblatt mit Kopfzeile, Filter und festem Spaltenmaß.
 * $spalten: [Überschrift, Breite, Zahlenformat|null, Ausrichtung|null]
 */
function tabelle($b, array $spalten, array $zeilen): void
{
    $letzte = \PhpOffice\PhpSpreadsheet\Cell\Coordinate::stringFromColumnIndex(count($spalten));

    $b->fromArray(array_column($spalten, 0), null, 'A1', true);

    $kopf = $b->getStyle("A1:{$letzte}1");
    $kopf->getFont()->setBold(true)->getColor()->setARGB('FFFFFFFF');
    $kopf->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FF' . KOPF_FARBE);
    $kopf->getAlignment()->setVertical(Alignment::VERTICAL_CENTER)->setWrapText(true);
    $b->getRowDimension(1)->setRowHeight(30);

    if ($zeilen) {
        $b->fromArray($zeilen, null, 'A2', true);
    }
    $ende = count($zeilen) + 1;

    foreach ($spalten as $i => $sp) {
        $buchstabe = \PhpOffice\PhpSpreadsheet\Cell\Coordinate::stringFromColumnIndex($i + 1);
        $b->getColumnDimension($buchstabe)->setWidth($sp[1]);
        if ($ende >= 2 && ($sp[2] ?? null)) {
            $b->getStyle("{$buchstabe}2:{$buchstabe}{$ende}")->getNumberFormat()->setFormatCode($sp[2]);
        }
        if ($ende >= 2 && ($sp[3] ?? null)) {
            $b->getStyle("{$buchstabe}2:{$buchstabe}{$ende}")->getAlignment()->setHorizontal($sp[3]);
        }
    }

    $b->setAutoFilter("A1:{$letzte}" . max($ende, 1));
    $b->freezePane('A2');
    $b->getStyle("A1:{$letzte}{$ende}")->getAlignment()->setVertical(Alignment::VERTICAL_TOP);
    $b->setSelectedCell('A2');
}

const F_U   = '0.000';
const F_R   = '0.00';
const F_CM  = '0.0';
const F_PCT = '0.0%';
const RECHTS = Alignment::HORIZONTAL_RIGHT;

// ---------------------------------------------------------------- Blatt: Bauteilkatalog

$spaltenKatalog = [
    ['Katalog',            26, null, null],
    ['Ordner',             52, null, null],
    ['Baualtersklasse',    16, null, null],
    ['Gebäudetyp',         38, null, null],
    ['Dublette',           10, null, null],
    ['Bauteilart',         17, null, null],
    ['Bezeichnung',        52, null, null],
    ['Kurzzeichen',        13, null, null],
    ['U-Wert'."\n".'W/(m²K)', 10, F_U, RECHTS],
    ['R'."\n".'m²K/W',      9, F_R, RECHTS],
    ['Dicke'."\n".'cm',     8, F_CM, RECHTS],
    ['g-Wert',              9, F_R, RECHTS],
    ['U Rahmen'."\n".'W/(m²K)', 10, F_U, RECHTS],
    ['Rahmen-'."\n".'anteil', 9, F_PCT, RECHTS],
    ['Schich-'."\n".'ten',  8, '0', RECHTS],
    ['Gefa-'."\n".'che',    7, '0', RECHTS],
    ['Aufbau (innen → außen)', 70, null, null],
    ['Beschreibung',       60, null, null],
    ['weitere'."\n".'Plätze', 9, '0', RECHTS],
    ['alle Einordnungen',  40, null, null],
    ['Bauteil-ID',         38, null, null],
];

/**
 * Der ausgelieferte Katalog führt manche Bauteile mehrfach — gleicher Ordner,
 * gleicher Name, gleiche Kennwerte, nur eine andere ID. Das ist keine Variante,
 * sondern eine Dublette, und wer sie nicht erkennt, zählt doppelt.
 */
function dublettenSchluessel(array $z): string
{
    return implode('|', [
        $z['Katalog'] ?? '', $z['Ordner'] ?? '', trim($z['Bezeichnung']),
        $z['UWert'], $z['RWert'], $z['Dicke'], $z['GWert'], $z['UWertRahmen'],
    ]);
}

function bauteilZeile(array $z, array $aufbauKarte, bool $mitKatalog, ?array &$gesehen = null): array
{
    $art = $z['ArtNr'] === '' ? null : (int) $z['ArtNr'];
    $ordnerRoh = $z['Ordner'] ?? '';
    $schichten = $aufbauKarte[$z['BauteilId']] ?? [];
    $sektionen = (int) $z['Sektionen'];

    $zeile = [];
    if ($mitKatalog) {
        [$klasse, $typ] = ordnerTeile($ordnerRoh);
        $zeile[] = entsperre($z['Katalog']);
        $zeile[] = ordnerpfad($ordnerRoh);
        $zeile[] = $klasse;
        $zeile[] = $typ;

        $s = dublettenSchluessel($z);
        $zeile[] = isset($gesehen[$s]) ? 'ja' : '';
        $gesehen[$s] = true;
    }
    $zeile[] = $art === null ? '' : (BAUTEILART[$art] ?? "unbekannt ($art)");
    $zeile[] = trim(preg_replace('/\s+/u', ' ', $z['Bezeichnung']));
    $zeile[] = $z['Kurzzeichen'];
    $zeile[] = kennwert($z['UWert']);
    $zeile[] = kennwert($z['RWert']);
    $d = kennwert($z['Dicke']);
    $zeile[] = $d === null ? null : $d * 100;
    $zeile[] = kennwert($z['GWert']);
    $zeile[] = kennwert($z['UWertRahmen']);
    $ra = kennwert($z['Rahmenanteil']);
    $zeile[] = $ra === null ? null : ($ra > 1 ? $ra / 100 : $ra);
    $zeile[] = $sektionen > 1 && $schichten
        ? (int) round(count($schichten) / max($sektionen, 1))
        : (int) $z['SchichtZeilen'];
    $zeile[] = $sektionen > 1 ? $sektionen : null;
    $zeile[] = aufbauText($schichten);
    $zeile[] = trim(preg_replace('/\s+/u', ' ', $z['Beschreibung']));

    return $zeile;
}

$zeilenKatalog = [];
$gesehenKatalog = [];
foreach ($katalog as $z) {
    $r = bauteilZeile($z, $katAufbau, true, $gesehenKatalog);
    $weitere = max(0, (int) $z['Einordnungen'] - 1);
    $r[] = $weitere ?: null;
    $alle = $z['AlleOrdner'];
    $r[] = $weitere ? mb_substr(implode(' • ', array_map('ordnerpfad', explode(' | ', $alle))), 0, 2000) : '';
    $r[] = $z['BauteilId'];
    $zeilenKatalog[] = $r;
}

$b = blatt($mappe, 'Bauteilkatalog', 1);
tabelle($b, $spaltenKatalog, $zeilenKatalog);

// ---------------------------------------------------------------- Blatt: Meine Bauteile

$spaltenMeine = $spaltenKatalog;
$spaltenMeine[] = ['angelegt', 16, null, null];
$spaltenMeine[] = ['geändert', 16, null, null];

$zeilenMeine = [];
$gesehenMeine = [];
foreach ($meine as $z) {
    $r = bauteilZeile($z, $meinAufbau, true, $gesehenMeine);
    $weitere = max(0, (int) $z['Einordnungen'] - 1);
    $r[] = $weitere ?: null;
    $r[] = $weitere ? implode(' • ', array_map('ordnerpfad', explode(' | ', $z['AlleOrdner']))) : '';
    $r[] = $z['BauteilId'];
    $r[] = $z['Angelegt'];
    $r[] = $z['Geaendert'];
    $zeilenMeine[] = $r;
}

$b = blatt($mappe, 'Meine Bauteile', 2);
tabelle($b, $spaltenMeine, $zeilenMeine);

// ---------------------------------------------------------------- Blatt: Projektbauteile

$spaltenProjekt = array_merge(
    [['Projekt', 34, null, null]],
    array_slice($spaltenKatalog, 5, 13),          // Bauteilart … Beschreibung
    [['Bauteil-ID', 38, null, null], ['angelegt', 16, null, null], ['geändert', 16, null, null]]
);

$zeilenProjekt = [];
foreach ($projekt as $z) {
    $r = array_merge([$z['Projekt']], bauteilZeile($z, [], false));
    $r[] = $z['BauteilId'];
    $r[] = $z['Angelegt'];
    $r[] = $z['Geaendert'];
    $zeilenProjekt[] = $r;
}

$b = blatt($mappe, 'Projektbauteile', 3);
tabelle($b, $spaltenProjekt, $zeilenProjekt);

// ---------------------------------------------------------------- Blatt: Schichten

$spaltenSchicht = [
    ['Quelle',          16, null, null],
    ['Bauteil',         52, null, null],
    ['Bauteilart',      17, null, null],
    ['Gefach',           8, '0', RECHTS],
    ['Flächen-'."\n".'anteil', 10, F_PCT, RECHTS],
    ['Nr',               6, '0', RECHTS],
    ['Schicht',         52, null, null],
    ['Schichtart',      15, null, null],
    ['Stoffgruppe',     14, null, null],
    ['Dicke'."\n".'cm',  8, F_CM, RECHTS],
    ['λ'."\n".'W/(mK)', 10, '0.000', RECHTS],
    ['R'."\n".'m²K/W',   9, '0.000', RECHTS],
    ['Rohdichte'."\n".'kg/m³', 11, '0', RECHTS],
    ['c'."\n".'kJ/(kgK)', 10, F_R, RECHTS],
    ['µ',                8, '0', RECHTS],
    ['Bauteil-ID',      38, null, null],
];

$nameVonId = [];
$artVonId  = [];
foreach ([[$katalog, 'Katalog'], [$meine, 'Meine Bauteile']] as [$liste, $quelle]) {
    foreach ($liste as $z) {
        $nameVonId[$z['BauteilId']] = trim(preg_replace('/\s+/u', ' ', $z['Bezeichnung']));
        $art = $z['ArtNr'] === '' ? null : (int) $z['ArtNr'];
        $artVonId[$z['BauteilId']] = $art === null ? '' : (BAUTEILART[$art] ?? '');
    }
}

$zeilenSchicht = [];
foreach ([[$katSchicht, 'Katalog'], [$meinSchicht, 'Meine Bauteile']] as [$liste, $quelle]) {
    foreach ($liste as $s) {
        $anteil = kennwert($s['SektionAnteil']);
        $zeilenSchicht[] = [
            $quelle,
            $nameVonId[$s['BauteilId']] ?? '(nicht zugeordnet)',
            $artVonId[$s['BauteilId']] ?? '',
            (int) $s['Sektion'],
            $anteil === null ? null : $anteil / 100,
            (int) $s['Nr'],
            trim(preg_replace('/\s+/u', ' ', $s['Schicht'])),
            SCHICHTART[(int) $s['SchichtartNr']] ?? '',
            STOFFGRUPPE[(int) $s['StoffgruppeNr']] ?? '',
            ($d = kennwert($s['Dicke'])) === null ? null : $d * 100,
            kennwert($s['Lambda']),
            kennwert($s['RWert']),
            kennwert($s['Rohdichte']),
            kennwert($s['Waermekapazitaet']),
            kennwert($s['my']),
            $s['BauteilId'],
        ];
    }
}

$b = blatt($mappe, 'Schichten', 4);
tabelle($b, $spaltenSchicht, $zeilenSchicht);

// ---------------------------------------------------------------- Blatt: Übersicht

$u = blatt($mappe, 'Übersicht', 5);
$mappe->setIndexByName('Übersicht', 0);

$dubletten = 0;
foreach ($zeilenKatalog as $r) {
    if (($r[4] ?? '') === 'ja') { $dubletten++; }
}

$verteilung = [];
foreach ($katalog as $z) {
    $art = $z['ArtNr'] === '' ? 'ohne Angabe' : (BAUTEILART[(int) $z['ArtNr']] ?? 'unbekannt');
    $verteilung[$art] = ($verteilung[$art] ?? 0) + 1;
}
arsort($verteilung);

$proKatalog = [];
foreach ($katalog as $z) {
    $k = entsperre($z['Katalog']);
    $proKatalog[$k] = ($proKatalog[$k] ?? 0) + 1;
}
arsort($proKatalog);

$zeile = 1;
$schreib = function (array $werte, bool $fett = false, int $groesse = 11, ?string $farbe = null) use ($u, &$zeile) {
    $u->fromArray($werte, null, 'A' . $zeile, true);
    $bis = \PhpOffice\PhpSpreadsheet\Cell\Coordinate::stringFromColumnIndex(max(count($werte), 1));
    $st = $u->getStyle("A{$zeile}:{$bis}{$zeile}");
    if ($fett) { $st->getFont()->setBold(true); }
    if ($groesse !== 11) { $st->getFont()->setSize($groesse); }
    if ($farbe) { $st->getFont()->getColor()->setARGB('FF' . $farbe); }
    $zeile++;
};
$leer = function (int $n = 1) use (&$zeile) { $zeile += $n; };

$schreib(['Bauteile aus Hottgenroth'], true, 18, KOPF_FARBE);
$schreib(['Bauteilbestand der Hottgenroth-/ETU-Energieberatersoftware, ausgelesen am ' . date('d.m.Y')]);
$leer();

$schreib(['Was in dieser Mappe steht'], true, 13, KOPF_FARBE);
$schreib(['Blatt', 'Inhalt', 'Quelle (SQL-Instanz (localdb)\\HSETU)', 'Zeilen'], true);
$schreib(['Bauteilkatalog', 'der von Hottgenroth ausgelieferte Bauteilkatalog', 'HsetuAppTimData', count($zeilenKatalog)]);
$schreib(['Meine Bauteile', '„Meine Bauteile" — projektübergreifend selbst angelegt', 'HsetuUsrData', count($zeilenMeine)]);
$schreib(['Projektbauteile', 'Bauteile innerhalb der angelegten Projekte', 'HsetuPrjData', count($zeilenProjekt)]);
$schreib(['Schichten', 'Schichtaufbauten zu Katalog und „Meine Bauteile"', 'beide', count($zeilenSchicht)]);
$leer();

$schreib(['Wie die Zahlen zu lesen sind'], true, 13, KOPF_FARBE);
$schreib(['Leere Zelle', 'Der Wert ist nicht hinterlegt. Die Software trägt dafür intern −987654321,99 oder 0 ein; beides steht hier als leere Zelle.']);
$schreib(['U-Wert ohne Aufbau', 'Die Typologie-Kataloge (Baualtersklassen) beschreiben Bauteile allein über den U-Wert — sie haben keine Schichten. Nur ' . number_format(count($katAufbau), 0, ',', '.') . ' der ' . number_format(count($zeilenKatalog), 0, ',', '.') . ' Katalogbauteile führen einen Schichtaufbau.']);
$schreib(['Dicke', 'in cm. In der Datenbank steht sie in m.']);
$schreib(['Gefache', 'Inhomogene Bauteile (Sparren neben Dämmung) sind in Gefache geteilt, jedes mit eigenem Schichtstapel und Flächenanteil. Die Spalte „Aufbau" zeigt das flächenmäßig größte; alle stehen auf dem Blatt „Schichten".']);
$schreib(['g-Wert, U Rahmen, Rahmenanteil', 'nur bei Fenstern und Verglasungen gefüllt.']);
$schreib(['Ordner', 'der Pfad im Bauteilkatalog der Software. Ein Bauteil kann an mehreren Stellen hängen — „weitere Plätze" zählt sie, „alle Einordnungen" nennt sie.']);
$schreib(['Dublette', 'Der ausgelieferte Katalog führt ' . number_format($dubletten, 0, ',', '.') . ' Bauteile doppelt: gleicher Ordner, gleicher Name, gleiche Kennwerte, nur eine andere ID. Die Zweit- und Folgezeilen sind mit „ja" markiert — wer sie herausfiltert, zählt ' . number_format(count($zeilenKatalog) - $dubletten, 0, ',', '.') . ' verschiedene Bauteile.']);
$schreib(['Baualtersklasse, Gebäudetyp', 'aus dem Ordnernamen gelesen ("TYPOLOGIE Bremen | 1919-1948 | Ein-/Zweifamilien-Reihenhaus"). Beides sind keine eigenen Spalten der Datenbank und bleiben deshalb außerhalb der Typologie-Kataloge leer.']);
$leer();

$schreib(['Katalogbauteile nach Bauteilart'], true, 13, KOPF_FARBE);
$schreib(['Bauteilart', 'Anzahl'], true);
foreach ($verteilung as $art => $n) {
    $schreib([$art, $n]);
}
$leer();

$schreib(['Katalogbauteile nach Teilkatalog'], true, 13, KOPF_FARBE);
$schreib(['Teilkatalog', 'Anzahl'], true);
foreach ($proKatalog as $k => $n) {
    $schreib([$k === '' ? '(ohne Katalogzuordnung)' : $k, $n]);
}
$leer();

$schreib(['Herkunft'], true, 13, KOPF_FARBE);
$schreib(['Gelesen aus den LocalDB-Datenbanken der Installation, ohne die Software zu öffnen. Bauteilart, Schichtart und']);
$schreib(['Stoffgruppe stehen dort als Zahl; die Klartexte stammen aus den Aufzählungen der Software selbst']);
$schreib(['(TTechDataBuildingElementType, TTechDataBuildingElementLayerType, TMaterialGroupType).']);

$u->getColumnDimension('A')->setWidth(34);
$u->getColumnDimension('B')->setWidth(95);
$u->getColumnDimension('C')->setWidth(40);
$u->getColumnDimension('D')->setWidth(12);
$u->getStyle('B1:B' . $zeile)->getAlignment()->setWrapText(false);
$u->getStyle('D1:D' . $zeile)->getAlignment()->setHorizontal(RECHTS);
$u->getStyle('B1:B' . $zeile)->getAlignment()->setVertical(Alignment::VERTICAL_TOP);
$u->setSelectedCell('A1');
$u->setShowGridlines(false);

$mappe->setActiveSheetIndexByName('Übersicht');

// ---------------------------------------------------------------- Schreiben

$schreiber = new Xlsx($mappe);
$schreiber->setPreCalculateFormulas(false);
$schreiber->save($ziel);

fwrite(STDERR, "geschrieben: $ziel (" . number_format(filesize($ziel) / 1024 / 1024, 1) . " MB)\n");
