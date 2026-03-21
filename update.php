<?php
ini_set('log_errors', '1');
ini_set('error_log', __DIR__ . '/php-errors.log');

session_start();

// ── Bootstrap ─────────────────────────────────────────────────────────────────
$BASE        = __DIR__;
$CONFIG_FILE = __DIR__ . '/.setup-config.json';
$LOCK_FILE   = __DIR__ . '/setup.lock';

// ── CSRF ──────────────────────────────────────────────────────────────────────
if (empty($_SESSION['csrf_token'])) {
    $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
}
$csrf = $_SESSION['csrf_token'];

// ── Placeholders (must match setup.php) ───────────────────────────────────────
const PLACEHOLDER_DOMAIN = '<SCRIPT_DOMAIN>';
const PLACEHOLDER_FOLDER = '<SCRIPT_FOLDER>';

// ── Git helper ────────────────────────────────────────────────────────────────
// Runs a git command in $BASE, returns [stdout, stderr, exit_code].
function git(string ...$args): array {
    global $BASE;
    $cmd  = array_merge(['git', '-C', $BASE], $args);
    $spec = [1 => ['pipe', 'w'], 2 => ['pipe', 'w']];
    $proc = proc_open($cmd, $spec, $pipes);
    if (!is_resource($proc)) {
        return ['', 'proc_open failed', 1];
    }
    $out  = stream_get_contents($pipes[1]); fclose($pipes[1]);
    $err  = stream_get_contents($pipes[2]); fclose($pipes[2]);
    $code = proc_close($proc);
    return [trim($out), trim($err), $code];
}

// ── File scanner (same logic as setup.php) ────────────────────────────────────
function find_target_files(string $base): array {
    $skip_names  = ['setup.php', 'update.php', 'setup.lock'];
    $skip_dirs   = ['.git', '.github', '.vscode', 'node_modules'];
    $text_exts   = ['php', 'ps1', 'psm1', 'psd1', 'sh', 'bat', 'cmd', 'txt', 'md', 'json', 'xml', 'html', 'htm', 'css', 'js'];
    $placeholders = [PLACEHOLDER_DOMAIN, PLACEHOLDER_FOLDER];

    $files = [];
    $iter  = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($base, FilesystemIterator::SKIP_DOTS)
    );
    foreach ($iter as $file) {
        if (!$file->isFile()) continue;
        $rel = str_replace('\\', '/', str_replace($base . DIRECTORY_SEPARATOR, '', $file->getPathname()));
        foreach ($skip_dirs as $d) {
            if (strpos($rel, $d . '/') === 0) continue 2;
        }
        $fname = $file->getFilename();
        if (in_array($fname, $skip_names)) continue;
        if (substr($fname, -4) === '.bak') continue;
        if ($fname === '.setup-config.json') continue;
        $ext = strtolower($file->getExtension());
        if (!in_array($ext, $text_exts)) continue;

        $content = file_get_contents($file->getPathname());
        foreach ($placeholders as $p) {
            if (strpos($content, $p) !== false) {
                $files[] = $rel;
                break;
            }
        }
    }
    sort($files);
    return $files;
}

function cleanup_bak_files(string $base): void {
    $iter = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($base, FilesystemIterator::SKIP_DOTS)
    );
    foreach ($iter as $file) {
        if ($file->isFile() && substr($file->getFilename(), -4) === '.bak') {
            unlink($file->getPathname());
        }
    }
}

function apply_settings(array $config, string $base): array {
    $replacements = [
        PLACEHOLDER_DOMAIN => $config['script_domain'],
        PLACEHOLDER_FOLDER => $config['script_folder'],
    ];
    $files   = find_target_files($base);
    $results = [];
    foreach ($files as $rel) {
        $path = $base . '/' . $rel;
        if (!is_file($path)) {
            $results[] = ['file' => $rel, 'status' => 'skip', 'msg' => 'File not found'];
            continue;
        }
        $orig = file_get_contents($path);
        $new  = str_replace(array_keys($replacements), array_values($replacements), $orig);
        if ($orig === $new) {
            $results[] = ['file' => $rel, 'status' => 'unchanged', 'msg' => 'No placeholders found'];
            continue;
        }
        if (file_put_contents($path, $new) !== false) {
            $results[] = ['file' => $rel, 'status' => 'ok', 'msg' => 'Updated'];
        } else {
            $results[] = ['file' => $rel, 'status' => 'err', 'msg' => 'Write failed — check permissions'];
        }
    }
    return $results;
}

// ── Page template ─────────────────────────────────────────────────────────────
function page_open(string $title): void {
    echo <<<HTML
<!DOCTYPE html>
<html lang="en" data-bs-theme="dark">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{$title}</title>
<script>(function(){var t=localStorage.getItem('theme')||'dark';document.documentElement.dataset.bsTheme=t;})()</script>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css">
<style>
  code { font-size: .85em; }
  .commit-log { font-family: monospace; font-size: .82rem; background: rgba(255,255,255,0.04);
                border: 1px solid rgba(255,255,255,0.1); border-radius: .25rem;
                padding: .75rem 1rem; white-space: pre-wrap; color: #ddd; }
  [data-bs-theme="light"] .commit-log { background:#f6f8fa; border-color:#d0d7de; color:#212529; }
  .badge-ok { background:#198754 }
  .theme-toggle { position:fixed; top:16px; right:16px; z-index:999; border-radius:8px; padding:6px 12px; font-size:.85rem; cursor:pointer; }
</style>
</head>
<body>
<div class="container py-5" style="max-width:760px">
<h2 class="mb-1">Script Library Updater</h2>
<p class="text-muted mb-4">Pulls the latest scripts from git and re-applies your saved settings automatically.</p>
HTML;
}

function page_close(): void {
    echo <<<'HTML'
</div>
<button class="btn btn-outline-secondary theme-toggle" onclick="toggleTheme()" aria-label="Toggle theme" id="theme-btn">Light</button>
<script>
(function(){
  function applyTheme(t,save){
    document.documentElement.dataset.bsTheme=t;
    document.getElementById('theme-btn').textContent=t==='dark'?'Light':'Dark';
    if(save)localStorage.setItem('theme',t);
  }
  window.toggleTheme=function(){applyTheme(document.documentElement.dataset.bsTheme==='dark'?'light':'dark',true);};
  applyTheme(localStorage.getItem('theme')||'dark',false);
})();
</script>
</body></html>
HTML;
}

// ── Guards ────────────────────────────────────────────────────────────────────
// Ensure proc_open is available
if (!function_exists('proc_open')) {
    page_open('Updater — Error');
    echo '<div class="alert alert-danger"><strong>proc_open is disabled</strong><br>Your PHP configuration disables <code>proc_open</code>. Enable it in <code>php.ini</code> (remove it from <code>disable_functions</code>) to use the updater.</div>';
    page_close();
    exit;
}

// Ensure setup has been run
if (!file_exists($CONFIG_FILE)) {
    page_open('Updater — Not configured');
    echo '<div class="alert alert-warning"><strong>Setup not completed yet.</strong><br>Run <a href="setup.php">setup.php</a> first to configure your domain and paths.</div>';
    page_close();
    exit;
}

$config = json_decode(file_get_contents($CONFIG_FILE), true);
if (!$config || empty($config['script_domain'])) {
    page_open('Updater — Corrupt config');
    echo '<div class="alert alert-danger"><strong>.setup-config.json is missing or corrupt.</strong><br>Delete <code>setup.lock</code> and re-run <a href="setup.php">setup.php</a>.</div>';
    page_close();
    exit;
}

// ── GET: status dashboard ─────────────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    [$branch, $_err, $bc] = git('symbolic-ref', '--short', 'HEAD');
    if ($bc !== 0) $branch = 'main';
    [$commit, ,] = git('log', '-1', '--format=%h %s (%ar)');

    // Fetch remote branch list
    git('fetch', '--prune', 'origin');
    [$branchList, ,] = git('branch', '-r', '--format=%(refname:short)');
    $remote_branches = array_filter(array_map(function($b) {
        $b = trim($b);
        // Strip "origin/" prefix and skip HEAD pointer
        if (strpos($b, 'origin/HEAD') !== false) return null;
        return preg_replace('/^origin\//', '', $b);
    }, explode("\n", $branchList)));
    $remote_branches = array_values(array_unique(array_filter($remote_branches)));
    if (empty($remote_branches)) $remote_branches = [$branch];

    page_open('Updater');

    echo '<div class="card mb-4"><div class="card-body">';
    echo '<h5 class="card-title mb-3">Current configuration</h5>';
    echo '<table class="table table-sm table-bordered mb-0">';
    echo '<tr><th style="width:160px">Script domain</th><td><code>' . htmlspecialchars($config['script_domain']) . '</code></td></tr>';
    echo '<tr><th>Script folder</th><td><code>' . htmlspecialchars($config['script_folder']) . '</code></td></tr>';
    echo '<tr><th>Configured on</th><td>' . htmlspecialchars($config['configured_at']) . '</td></tr>';
    echo '<tr><th>Active branch</th><td><code>' . htmlspecialchars($branch) . '</code></td></tr>';
    echo '<tr><th>Current commit</th><td><code>' . htmlspecialchars($commit ?: '—') . '</code></td></tr>';
    echo '</table></div></div>';

    echo '<form method="post">';
    echo '<input type="hidden" name="csrf_token" value="' . htmlspecialchars($csrf) . '">';
    echo '<input type="hidden" name="action"     value="check">';
    echo '<div class="mb-3">';
    echo '<label class="form-label fw-semibold" for="branch">Branch to update from</label>';
    echo '<select class="form-select" id="branch" name="branch">';
    foreach ($remote_branches as $b) {
        $sel = ($b === $branch) ? ' selected' : '';
        echo '<option value="' . htmlspecialchars($b) . '"' . $sel . '>' . htmlspecialchars($b) . '</option>';
    }
    echo '</select></div>';
    echo '<button type="submit" class="btn btn-primary">Check for updates</button>';
    echo '<a href="setup.php" class="btn btn-outline-secondary ms-2">Back to setup</a>';
    echo '</form>';

    page_close();
    exit;
}

// ── POST ──────────────────────────────────────────────────────────────────────
if (!isset($_POST['csrf_token']) || !hash_equals($csrf, $_POST['csrf_token'])) {
    http_response_code(403);
    die('CSRF mismatch — go back and try again.');
}

$action = $_POST['action'] ?? '';

// ── POST action=check: fetch + show incoming commits ──────────────────────────
if ($action === 'check') {
    $branch = preg_replace('/[^a-zA-Z0-9_.\-\/]/', '', $_POST['branch'] ?? '');
    if (empty($branch)) {
        [$branch, $_err, $bc] = git('symbolic-ref', '--short', 'HEAD');
        if ($bc !== 0 || !$branch) $branch = 'main';
    }

    [$_out, $fetchErr, $fetchCode] = git('fetch', 'origin');

    [$log, $_e2, $_c2] = git('log', "HEAD..origin/{$branch}", '--oneline', '--no-decorate');

    page_open('Updater — Check');

    if ($fetchCode !== 0) {
        echo '<div class="alert alert-danger"><strong>git fetch failed</strong><br><code>' . htmlspecialchars($fetchErr) . '</code></div>';
        echo '<a href="update.php" class="btn btn-secondary">Back</a>';
        page_close();
        exit;
    }

    if (empty($log)) {
        echo '<div class="alert alert-success"><strong>Already up to date.</strong> No new commits on <code>' . htmlspecialchars($branch) . '</code>.</div>';
        echo '<a href="update.php" class="btn btn-secondary">Back</a>';
    } else {
        $line_count = count(explode("\n", trim($log)));
        echo '<div class="alert alert-info"><strong>' . $line_count . ' new commit' . ($line_count === 1 ? '' : 's') . ' available</strong> on <code>' . htmlspecialchars($branch) . '</code>:</div>';
        echo '<pre class="commit-log">' . htmlspecialchars($log) . '</pre>';
        echo '<div class="alert alert-warning mt-3"><strong>How this works:</strong> The update will reset all repo files to the latest version (including reverting them to placeholders), then immediately re-apply your saved settings. Your <code>.setup-config.json</code> is never touched by git.</div>';

        echo '<form method="post" class="mt-3">';
        echo '<input type="hidden" name="csrf_token" value="' . htmlspecialchars($csrf) . '">';
        echo '<input type="hidden" name="action"     value="apply">';
        echo '<input type="hidden" name="branch"     value="' . htmlspecialchars($branch) . '">';
        echo '<input type="hidden" name="confirm"    value="1">';
        echo '<button type="submit" class="btn btn-success me-2">Apply update</button>';
        echo '<a href="update.php" class="btn btn-outline-secondary">Cancel</a>';
        echo '</form>';
    }

    page_close();
    exit;
}

// ── POST action=apply: reset hard + re-apply settings ─────────────────────────
if ($action === 'apply' && ($_POST['confirm'] ?? '') === '1') {
    $branch = preg_replace('/[^a-zA-Z0-9_.\-\/]/', '', $_POST['branch'] ?? 'main');
    if (empty($branch)) $branch = 'main';

    page_open('Updater — Applying');

    // 1. Reset to remote (discards all local modifications including applied settings)
    [$_out, $resetErr, $resetCode] = git('reset', '--hard', "origin/{$branch}");
    if ($resetCode !== 0) {
        echo '<div class="alert alert-danger"><strong>git reset failed</strong><br><code>' . htmlspecialchars($resetErr) . '</code></div>';
        page_close();
        exit;
    }
    echo '<div class="alert alert-success">✅ Pulled latest from <code>' . htmlspecialchars($branch) . '</code></div>';

    // 2. Re-read config (in case update.php itself was updated — config is gitignored so it survived)
    $config = json_decode(file_get_contents($CONFIG_FILE), true);

    // 3. Re-apply settings and clean up any .bak files
    $results = apply_settings($config, $BASE);
    cleanup_bak_files($BASE);

    echo '<h5 class="mt-3 mb-2">Settings re-applied</h5>';
    echo '<ul class="list-group mb-4">';
    foreach ($results as $r) {
        $icon = match($r['status']) { 'ok' => '✅', 'unchanged' => '⬛', 'skip' => '⚠️', default => '❌' };
        $cls  = match($r['status']) { 'ok' => 'list-group-item-success', 'err' => 'list-group-item-danger', 'skip' => 'list-group-item-warning', default => '' };
        echo "<li class=\"list-group-item {$cls}\"><code>{$r['file']}</code> {$icon} — {$r['msg']}</li>";
    }
    echo '</ul>';

    // 4. Show new commit
    [$commit, $_e, $_c] = git('log', '-1', '--format=%h %s (%ar)');
    echo '<div class="alert alert-success"><strong>Update complete.</strong> Now at: <code>' . htmlspecialchars($commit) . '</code></div>';
    echo '<a href="update.php" class="btn btn-primary">Back to updater</a>';

    page_close();
    exit;
}

// Fallback
header('Location: update.php');
exit;
