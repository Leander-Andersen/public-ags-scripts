<?php
session_start();

// ── Lock check ────────────────────────────────────────────────────────────────
$LOCK_FILE = __DIR__ . '/setup.lock';
if (file_exists($LOCK_FILE)) {
    $locked_at = trim(file_get_contents($LOCK_FILE));
?><!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>Setup locked</title>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0-alpha1/dist/css/bootstrap.min.css">
</head><body class="bg-light"><div class="container py-5" style="max-width:640px">
<div class="alert alert-warning"><strong>Setup already completed</strong><br>
Ran on: <?= htmlspecialchars($locked_at) ?><br><br>
Delete <code>setup.lock</code> from the server to re-run setup.</div>
</div></body></html>
<?php
    exit;
}

// ── CSRF token ────────────────────────────────────────────────────────────────
if (empty($_SESSION['csrf_token'])) {
    $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
}
$csrf = $_SESSION['csrf_token'];

// ── Hardcoded originals (what exists in the repo right now) ───────────────────
const OLD_SCRIPT_DOMAIN = 'script.isame12.no';
const OLD_FOLDER        = 'public-ags-scripts';
const OLD_WEBROOT       = '/var/www/html';

// ── Files that will be rewritten ──────────────────────────────────────────────
$TARGET_FILES = [
    'SetDefaultBrowser/SetDefaultBrowser.ps1',
    'SetDefaultBrowser/SetBraveDefault.ps1',
    'SetDefaultBrowser/SetChromeDefault.ps1',
    'SetDefaultBrowser/SetFirefoxDefault.ps1',
    'index.php',
    '##Extras/index.php',
];

// ── Helpers ───────────────────────────────────────────────────────────────────
function build_replacements(string $domain, string $folder, string $webroot): array {
    return [
        OLD_SCRIPT_DOMAIN => $domain,
        OLD_FOLDER        => $folder,
        OLD_WEBROOT       => rtrim($webroot, '/'),
    ];
}

function get_preview(array $files, array $replacements): array {
    $preview = [];
    foreach ($files as $rel) {
        $path = __DIR__ . '/' . $rel;
        if (!is_file($path)) continue;
        $lines       = file($path, FILE_KEEP_BLANK_LINES);
        $diffs       = [];
        foreach ($lines as $i => $line) {
            $new = str_replace(array_keys($replacements), array_values($replacements), $line);
            if ($new !== $line) {
                $diffs[] = ['n' => $i + 1, 'old' => rtrim($line), 'new' => rtrim($new)];
            }
        }
        if ($diffs) {
            $preview[] = ['file' => $rel, 'diffs' => $diffs];
        }
    }
    return $preview;
}

function apply_changes(array $files, array $replacements): array {
    $results = [];
    foreach ($files as $rel) {
        $path = __DIR__ . '/' . $rel;
        if (!is_file($path)) {
            $results[] = ['file' => $rel, 'status' => 'skip', 'msg' => 'File not found'];
            continue;
        }
        $orig = file_get_contents($path);
        $new  = str_replace(array_keys($replacements), array_values($replacements), $orig);
        if ($orig === $new) {
            $results[] = ['file' => $rel, 'status' => 'unchanged', 'msg' => 'Nothing to change'];
            continue;
        }
        file_put_contents($path . '.bak', $orig);        // backup
        if (file_put_contents($path, $new) !== false) {
            $results[] = ['file' => $rel, 'status' => 'ok', 'msg' => 'Updated — backup saved as ' . basename($rel) . '.bak'];
        } else {
            $results[] = ['file' => $rel, 'status' => 'err', 'msg' => 'Write failed — check file permissions'];
        }
    }
    return $results;
}

function validate(string $domain, string $folder, string $webroot): array {
    $errs = [];
    if (!preg_match('/^[a-zA-Z0-9][a-zA-Z0-9.\-]*\.[a-zA-Z]{2,}$/', $domain)) {
        $errs[] = 'Script domain looks invalid (e.g. <code>script.yourdomain.com</code>).';
    }
    if (!preg_match('/^[a-zA-Z0-9][a-zA-Z0-9_\-]*$/', $folder)) {
        $errs[] = 'Folder name must be alphanumeric (hyphens/underscores allowed, no spaces).';
    }
    if (!preg_match('/^\//', $webroot)) {
        $errs[] = 'Web root must be an absolute path starting with <code>/</code>.';
    }
    return $errs;
}

// ── Page template ─────────────────────────────────────────────────────────────
function page_open(string $title): void {
    echo <<<HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{$title}</title>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0-alpha1/dist/css/bootstrap.min.css">
<style>
  .diff-old { background:#ffeef0; color:#b31d28; font-family:monospace; font-size:.82rem; white-space:pre-wrap; word-break:break-all; }
  .diff-new { background:#e6ffec; color:#22863a; font-family:monospace; font-size:.82rem; white-space:pre-wrap; word-break:break-all; }
  .file-header { background:#f6f8fa; border:1px solid #d0d7de; padding:.4rem .75rem; font-weight:600; font-size:.9rem; border-radius:.25rem .25rem 0 0; }
  .diff-block  { border:1px solid #d0d7de; border-top:0; border-radius:0 0 .25rem .25rem; overflow:hidden; margin-bottom:1.25rem; }
  .diff-row    { padding:.2rem .75rem; }
  .lnum        { display:inline-block; width:2.5rem; color:#888; user-select:none; }
</style>
</head>
<body class="bg-light">
<div class="container py-5" style="max-width:760px">
<h2 class="mb-1">Script Library Setup</h2>
<p class="text-muted mb-4">Rewrites hardcoded domain &amp; paths across all scripts so they point at your server.</p>
HTML;
}

function page_close(): void {
    echo '</div></body></html>';
}

// ── Route ─────────────────────────────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    // ── GET: show form ────────────────────────────────────────────────────────
    page_open('Setup');
    echo render_form('', '', '', [], $csrf);
    page_close();
    exit;
}

// ── POST ──────────────────────────────────────────────────────────────────────
if (!isset($_POST['csrf_token']) || !hash_equals($csrf, $_POST['csrf_token'])) {
    http_response_code(403);
    die('CSRF mismatch — go back and try again.');
}

$domain  = trim($_POST['script_domain'] ?? '');
$folder  = trim($_POST['folder_name']   ?? '');
$webroot = trim($_POST['web_root']      ?? '');
$errors  = validate($domain, $folder, $webroot);

if ($errors) {
    page_open('Setup — Errors');
    echo render_form($domain, $folder, $webroot, $errors, $csrf);
    page_close();
    exit;
}

$replacements = build_replacements($domain, $folder, $webroot);

if (isset($_POST['confirm']) && $_POST['confirm'] === '1') {
    // ── Apply ─────────────────────────────────────────────────────────────────
    $results = apply_changes($TARGET_FILES, $replacements);
    file_put_contents($LOCK_FILE, date('c'));

    page_open('Setup — Done');
    echo '<h5 class="mb-3">Changes applied</h5>';
    echo '<ul class="list-group mb-4">';
    foreach ($results as $r) {
        $icon = match($r['status']) {
            'ok'        => '✅',
            'unchanged' => '⬛',
            'skip'      => '⚠️',
            default     => '❌',
        };
        $cls = match($r['status']) {
            'ok'        => 'list-group-item-success',
            'err'       => 'list-group-item-danger',
            'skip'      => 'list-group-item-warning',
            default     => '',
        };
        echo "<li class=\"list-group-item {$cls}\"><code>{$r['file']}</code> {$icon} — {$r['msg']}</li>";
    }
    echo '</ul>';
    echo '<div class="alert alert-success"><strong>Setup complete.</strong> A <code>setup.lock</code> file has been created — setup.php will refuse to run again until you delete it. Consider deleting <code>setup.php</code> from the server as well.</div>';
    page_close();
    exit;
}

// ── Preview ───────────────────────────────────────────────────────────────────
$preview = get_preview($TARGET_FILES, $replacements);

page_open('Setup — Preview');
echo '<h5 class="mb-1">Review changes</h5>';
echo '<p class="text-muted mb-3">Lines highlighted in <span class="text-danger">red</span> will be replaced with the <span class="text-success">green</span> version. Click <strong>Apply</strong> to write these changes to disk.</p>';

if (empty($preview)) {
    echo '<div class="alert alert-info">No changes needed — the files already use your provided values (or the target files were not found).</div>';
} else {
    foreach ($preview as $file_entry) {
        echo '<div class="file-header">' . htmlspecialchars($file_entry['file']) . '</div>';
        echo '<div class="diff-block">';
        foreach ($file_entry['diffs'] as $d) {
            $n = htmlspecialchars($d['n']);
            echo "<div class=\"diff-row diff-old\"><span class=\"lnum\">{$n}</span>- " . htmlspecialchars($d['old']) . "</div>";
            echo "<div class=\"diff-row diff-new\"><span class=\"lnum\">{$n}</span>+ " . htmlspecialchars($d['new']) . "</div>";
        }
        echo '</div>';
    }

    echo '<form method="post" class="mt-3">';
    echo '<input type="hidden" name="csrf_token"    value="' . htmlspecialchars($csrf)    . '">';
    echo '<input type="hidden" name="script_domain" value="' . htmlspecialchars($domain)  . '">';
    echo '<input type="hidden" name="folder_name"   value="' . htmlspecialchars($folder)  . '">';
    echo '<input type="hidden" name="web_root"      value="' . htmlspecialchars($webroot) . '">';
    echo '<input type="hidden" name="confirm"        value="1">';
    echo '<button type="submit" class="btn btn-success me-2">Apply changes</button>';
    echo '<a href="setup.php" class="btn btn-outline-secondary">Back</a>';
    echo '</form>';
}

page_close();

// ── Form renderer ─────────────────────────────────────────────────────────────
function render_form(string $domain, string $folder, string $webroot, array $errors, string $csrf): string {
    $d_val = htmlspecialchars($domain);
    $f_val = htmlspecialchars($folder);
    $w_val = htmlspecialchars($webroot);
    $out   = '';

    if ($errors) {
        $out .= '<div class="alert alert-danger"><ul class="mb-0">';
        foreach ($errors as $e) {
            $out .= "<li>{$e}</li>";
        }
        $out .= '</ul></div>';
    }

    $out .= <<<HTML
<form method="post">
  <input type="hidden" name="csrf_token" value="{$csrf}">

  <div class="mb-3">
    <label class="form-label fw-semibold" for="script_domain">Script domain</label>
    <input class="form-control" id="script_domain" name="script_domain"
           placeholder="script.yourdomain.com" value="{$d_val}" required>
    <div class="form-text">Replaces <code>script.isame12.no</code> in all PowerShell scripts.</div>
  </div>

  <div class="mb-3">
    <label class="form-label fw-semibold" for="folder_name">Script folder name</label>
    <input class="form-control" id="folder_name" name="folder_name"
           placeholder="my-scripts" value="{$f_val}" required>
    <div class="form-text">Replaces <code>public-ags-scripts</code> in all URLs. Must match the actual folder on the web server.</div>
  </div>

  <div class="mb-4">
    <label class="form-label fw-semibold" for="web_root">Web root path</label>
    <input class="form-control" id="web_root" name="web_root"
           placeholder="/var/www/html" value="{$w_val}" required>
    <div class="form-text">Replaces <code>/var/www/html</code> in PHP include paths. Use the absolute path on your server.</div>
  </div>

  <button type="submit" class="btn btn-primary">Preview changes</button>
</form>
HTML;

    return $out;
}
