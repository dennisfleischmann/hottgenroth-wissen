<?php
/**
 * Kleines Werkzeug, um eine .sqproj (SQLite) zu untersuchen.
 *
 *   php sq.php <datei> tabellen            alle Tabellen mit Zeilenzahl
 *   php sq.php <datei> spalten <tabelle>   Spalten einer Tabelle
 *   php sq.php <datei> zeigen <tabelle> [n] erste n Zeilen
 *   php sq.php <datei> sql "<abfrage>"     freie Abfrage
 *   php sq.php <datei> suche "<text>"      Text in allen Textspalten suchen
 */

$datei = $argv[1] ?? null;
$befehl = $argv[2] ?? 'tabellen';

if (! $datei || ! is_file($datei)) {
    fwrite(STDERR, "Datei nicht gefunden: $datei\n");
    exit(1);
}

$db = new PDO('sqlite:'.$datei, null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);

function tabellen(PDO $db): array
{
    return $db->query("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
        ->fetchAll(PDO::FETCH_COLUMN);
}

switch ($befehl) {
    case 'tabellen':
        $mit = [];
        $ohne = 0;
        foreach (tabellen($db) as $t) {
            try {
                $n = (int) $db->query('SELECT COUNT(*) FROM "'.$t.'"')->fetchColumn();
            } catch (Throwable $e) {
                $n = -1;
            }
            if ($n > 0) { $mit[$t] = $n; } else { $ohne++; }
        }
        arsort($mit);
        printf("%d Tabellen gesamt, %d mit Inhalt, %d leer\n\n", count($mit) + $ohne, count($mit), $ohne);
        foreach ($mit as $t => $n) {
            printf("%7d  %s\n", $n, $t);
        }
        break;

    case 'spalten':
        $t = $argv[3];
        foreach ($db->query('PRAGMA table_info("'.$t.'")') as $s) {
            printf("%-34s %s%s\n", $s['name'], $s['type'], $s['pk'] ? '  [PK]' : '');
        }
        break;

    case 'zeigen':
        $t = $argv[3];
        $n = (int) ($argv[4] ?? 3);
        foreach ($db->query('SELECT * FROM "'.$t.'" LIMIT '.$n) as $i => $zeile) {
            echo "--- Zeile ".($i + 1)."\n";
            foreach ($zeile as $k => $v) {
                if (is_int($k)) { continue; }
                if ($v === null || $v === '') { continue; }
                $text = is_string($v) ? $v : (string) $v;
                if (strlen($text) > 160) { $text = substr($text, 0, 160).' …['.strlen($text).' Zeichen]'; }
                printf("  %-32s %s\n", $k, $text);
            }
        }
        break;

    case 'sql':
        $r = $db->query($argv[3]);
        $kopf = false;
        foreach ($r as $zeile) {
            $zeile = array_filter($zeile, fn ($k) => ! is_int($k), ARRAY_FILTER_USE_KEY);
            if (! $kopf) { echo implode(' | ', array_keys($zeile))."\n"; $kopf = true; }
            echo implode(' | ', array_map(fn ($v) => $v === null ? '' : (strlen((string) $v) > 60 ? substr((string) $v, 0, 60).'…' : (string) $v), $zeile))."\n";
        }
        break;

    case 'suche':
        $such = $argv[3];
        foreach (tabellen($db) as $t) {
            $spalten = $db->query('PRAGMA table_info("'.$t.'")')->fetchAll(PDO::FETCH_ASSOC);
            $text = array_filter($spalten, fn ($s) => stripos($s['type'], 'char') !== false
                || stripos($s['type'], 'text') !== false || $s['type'] === '');
            if (! $text) { continue; }
            $wo = implode(' OR ', array_map(fn ($s) => '"'.$s['name'].'" LIKE '.$db->quote('%'.$such.'%'), $text));
            try {
                $n = (int) $db->query('SELECT COUNT(*) FROM "'.$t.'" WHERE '.$wo)->fetchColumn();
            } catch (Throwable $e) { continue; }
            if ($n > 0) { printf("%5d  %s\n", $n, $t); }
        }
        break;
}
