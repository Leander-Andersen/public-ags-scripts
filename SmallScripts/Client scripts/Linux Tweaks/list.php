<?php
// Index of the tweak scripts in tweaks/, fetched by linux-tweaks.sh.
//
// Output is plain text, one tweak per line, tab separated:
//   file <TAB> root <TAB> category <TAB> name <TAB> description
//
// The metadata comes from the "# @key value" header at the top of each script,
// so dropping a new .sh into tweaks/ is all it takes to add a tweak.
// linux-tweaks.sh has a bash copy of this parser for local runs — keep them in sync.

header('Content-Type: text/plain; charset=utf-8');
header('Cache-Control: no-store');

function parse_tweak_header(string $path): array {
    $meta = ['name' => '', 'description' => '', 'category' => '', 'root' => 'no'];
    $key  = '';

    $fh = fopen($path, 'r');
    if ($fh === false) return $meta;

    while (($line = fgets($fh)) !== false) {
        $line = rtrim($line, "\r\n");
        if (strncmp($line, '#!', 2) === 0) continue;
        if ($line === '' || $line[0] !== '#') break;   // header ends at the first code line

        if (preg_match('/^#\s*@([a-z]+)\s+(.*)$/', $line, $m)) {
            $key = $m[1];
            if (array_key_exists($key, $meta)) $meta[$key] = trim($m[2]);
        } elseif ($key === 'description' && preg_match('/^#\s+(\S.*)$/', $line, $m)) {
            $meta['description'] .= ' ' . trim($m[1]);  // indented continuation line
        } else {
            $key = '';
        }
    }
    fclose($fh);
    return $meta;
}

function clean_field(string $s): string {
    return trim(preg_replace('/\s+/', ' ', $s));
}

$tweaks = [];
foreach (glob(__DIR__ . '/tweaks/*.sh') ?: [] as $path) {
    $file = basename($path);
    if (!preg_match('/^[A-Za-z0-9._-]+\.sh$/', $file)) continue;

    $meta = parse_tweak_header($path);
    $root = strtolower(strtok($meta['root'], " \t") ?: '');

    $tweaks[] = [
        'file'        => $file,
        'root'        => in_array($root, ['yes', 'true', '1'], true) ? 'yes' : 'no',
        'category'    => clean_field($meta['category']) ?: 'Other',
        'name'        => clean_field($meta['name']) ?: substr($file, 0, -3),
        'description' => clean_field($meta['description']),
    ];
}

usort($tweaks, fn($a, $b) => strcasecmp($a['category'], $b['category']) ?: strcasecmp($a['name'], $b['name']));

foreach ($tweaks as $t) {
    echo implode("\t", [$t['file'], $t['root'], $t['category'], $t['name'], $t['description']]), "\n";
}
