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

// ── Shared page styles ─────────────────────────────────────────────────────────
function ags_page_styles(): string { return <<<'CSS'
:root{--bg:#181818;--surface:#222;--surface2:#2c2c2c;--border:rgba(255,255,255,.1);--text:#eaeaea;--muted:#9a9a9a;--accent:#b388ff;--btn-pink:#ec4899;--btn-pink-hover:#f472b6;--input-bg:rgba(255,255,255,.06);--input-border:rgba(255,255,255,.15);--s-bg:rgba(40,167,69,.15);--s-fg:#7dd57d;--s-b:rgba(40,167,69,.3);--d-bg:rgba(220,53,69,.15);--d-fg:#ff9090;--d-b:rgba(220,53,69,.3);--w-bg:rgba(255,193,7,.12);--w-fg:#ffd060;--w-b:rgba(255,193,7,.3);--i-bg:rgba(13,202,240,.1);--i-fg:#7ee8ff;--i-b:rgba(13,202,240,.25)}
[data-theme="light"]{--bg:#e8eaed;--surface:#fff;--surface2:#f3f4f6;--border:rgba(0,0,0,.12);--text:#212529;--muted:#6c757d;--accent:#6f42c1;--btn-pink:#be185d;--btn-pink-hover:#db2777;--input-bg:#fff;--input-border:rgba(0,0,0,.2);--s-bg:#d1e7dd;--s-fg:#0a3622;--s-b:#a3cfbb;--d-bg:#f8d7da;--d-fg:#58151c;--d-b:#f1aeb5;--w-bg:#fff3cd;--w-fg:#664d03;--w-b:#ffe69c;--i-bg:#cff4fc;--i-fg:#055160;--i-b:#9eeaf9}
[data-theme="overpinku"]{--bg:#fff0f5;--surface:#fff8fa;--surface2:#ffe4ee;--border:rgba(255,20,147,.2);--text:#5c1a3a;--muted:#b05070;--accent:#e91e8c;--btn-pink:#e91e8c;--btn-pink-hover:#c2185b;--input-bg:rgba(255,20,147,.05);--input-border:rgba(255,20,147,.25);--s-bg:#d1e7dd;--s-fg:#0a3622;--s-b:#a3cfbb;--d-bg:#f8d7da;--d-fg:#58151c;--d-b:#f1aeb5;--w-bg:#fff3cd;--w-fg:#664d03;--w-b:#ffe69c;--i-bg:#cff4fc;--i-fg:#055160;--i-b:#9eeaf9}
*{font-family:'Roboto',system-ui,sans-serif;font-weight:300;box-sizing:border-box;color:var(--text);transition:color .25s ease}
html,body{margin:0;padding:0;min-height:100vh;background-color:var(--bg);transition:background-color .25s ease,color .25s ease}
.container{max-width:800px;margin:0 auto;padding:40px max(24px,4vw)}
h2{font-size:1.4rem;font-weight:400;margin:0 0 4px}h5{font-size:1rem;font-weight:500;margin:0 0 12px}
.text-muted{color:var(--muted)}.text-danger{color:var(--d-fg)}.text-success{color:var(--s-fg)}.fw-semibold{font-weight:600}
.mb-0{margin-bottom:0}.mb-1{margin-bottom:4px}.mb-2{margin-bottom:8px}.mb-3{margin-bottom:16px}.mb-4{margin-bottom:24px}
.mt-1{margin-top:4px}.mt-2{margin-top:8px}.mt-3{margin-top:16px}.mt-4{margin-top:24px}
.ms-2{margin-left:8px}.me-2{margin-right:8px}.py-5{padding-top:48px;padding-bottom:48px}
code{background:rgba(128,128,128,.12);padding:2px 6px;border-radius:4px;font-family:ui-monospace,'Roboto Mono',monospace;font-size:.85em}
.card{background:var(--surface);border:1px solid var(--border);border-radius:10px;overflow:hidden;margin-bottom:24px}
.card-body{padding:20px 24px}.card-title{font-size:1rem;font-weight:500;margin:0 0 16px}
.alert{padding:12px 16px;border-radius:8px;border:1px solid;font-size:.9rem;margin-bottom:16px}
.alert strong{font-weight:600;color:inherit}.alert code{background:rgba(128,128,128,.15);color:inherit}
.alert a{color:inherit;text-decoration:underline}.alert ul{margin:8px 0 0;padding-left:20px}.alert li{margin-bottom:4px}
.alert pre{background:rgba(128,128,128,.1);border:1px solid rgba(128,128,128,.2);padding:8px 10px;border-radius:4px;margin:6px 0 0;font-size:.82rem;white-space:pre-wrap;word-break:break-all}
.alert-success{background:var(--s-bg);color:var(--s-fg);border-color:var(--s-b)}
.alert-danger{background:var(--d-bg);color:var(--d-fg);border-color:var(--d-b)}
.alert-warning{background:var(--w-bg);color:var(--w-fg);border-color:var(--w-b)}
.alert-info{background:var(--i-bg);color:var(--i-fg);border-color:var(--i-b)}
.table{width:100%;border-collapse:collapse;font-size:.9rem}
.table th,.table td{padding:10px 14px;border:1px solid var(--border);text-align:left;background:transparent}
.table th{font-weight:500;color:var(--muted);background:var(--surface2);width:160px}
.table td{background:var(--surface)}.table-sm th,.table-sm td{padding:7px 12px}
.form-label{display:block;margin-bottom:6px;font-size:.9rem}
.form-control,.form-select{display:block;width:100%;padding:9px 12px;background:var(--input-bg);border:1px solid var(--input-border);border-radius:6px;color:var(--text);font-family:inherit;font-size:.95rem;font-weight:300;transition:border-color .2s,box-shadow .2s}
.form-select{appearance:none;-webkit-appearance:none;padding-right:32px;background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 12 12'%3E%3Cpath fill='%23999' d='M6 8L1 3h10z'/%3E%3C/svg%3E");background-repeat:no-repeat;background-position:right 12px center;background-color:var(--input-bg)}
.form-control:focus,.form-select:focus{outline:none;border-color:var(--accent);box-shadow:0 0 0 3px rgba(179,136,255,.15)}
option{background-color:var(--surface);color:var(--text)}
.form-text{display:block;margin-top:4px;font-size:.82rem;color:var(--muted)}
.btn{display:inline-flex;align-items:center;padding:9px 18px;border-radius:6px;border:1px solid transparent;font-family:inherit;font-size:.9rem;font-weight:400;cursor:pointer;text-decoration:none;transition:background-color .15s,border-color .15s,color .15s;white-space:nowrap}
.btn-primary{background:var(--btn-pink);color:#fff}.btn-primary:hover{background:var(--btn-pink-hover)}
.btn-success{background:#2d7d46;color:#fff}.btn-success:hover{background:#379657}
.btn-secondary,.btn-outline-secondary{background:transparent;color:var(--muted);border-color:var(--border)}
.btn-secondary:hover,.btn-outline-secondary:hover{background:rgba(128,128,128,.1);color:var(--text)}
[data-theme="light"] .btn-success{background:#198754}
.list-group{list-style:none;padding:0;margin:0;border-radius:8px;overflow:hidden;border:1px solid var(--border)}
.list-group-item{padding:10px 14px;border-bottom:1px solid var(--border);font-size:.88rem;display:flex;align-items:baseline;gap:6px;background:var(--surface)}
.list-group-item:last-child{border-bottom:none}
.list-group-item code{background:rgba(128,128,128,.15);padding:2px 6px;border-radius:4px}
.list-group-item-success{background:var(--s-bg);color:var(--s-fg)}.list-group-item-danger{background:var(--d-bg);color:var(--d-fg)}.list-group-item-warning{background:var(--w-bg);color:var(--w-fg)}
pre,.commit-log{background:rgba(128,128,128,.08);border:1px solid var(--border);border-radius:8px;padding:14px 16px;font-family:ui-monospace,'Roboto Mono',monospace;font-size:.82rem;white-space:pre-wrap;color:var(--text);margin:0}
details{border:1px solid var(--border);border-radius:8px;margin-bottom:16px}
details[open]>summary{border-bottom:1px solid var(--border)}
summary{padding:10px 14px;cursor:pointer;color:var(--muted);font-size:.9rem;list-style:none}
summary::-webkit-details-marker{display:none}
.border{border:1px solid var(--border)}.rounded{border-radius:6px}
.bg-body-secondary,.bg-dark{background:var(--surface2)}.p-2{padding:8px}.p-3{padding:16px}
.diff-old{background:rgba(255,80,80,.12);color:#ff9090;font-family:monospace;font-size:.82rem;white-space:pre-wrap;word-break:break-all}
.diff-new{background:rgba(60,210,100,.12);color:#7dd57d;font-family:monospace;font-size:.82rem;white-space:pre-wrap;word-break:break-all}
.file-header{background:rgba(255,255,255,.06);border:1px solid var(--border);padding:.4rem .75rem;font-weight:600;font-size:.9rem;border-radius:6px 6px 0 0}
.diff-block{border:1px solid var(--border);border-top:0;border-radius:0 0 6px 6px;overflow:hidden;margin-bottom:20px}
.diff-row{padding:.2rem .75rem}.lnum{display:inline-block;width:2.5rem;color:#888;user-select:none}
[data-theme="light"] .diff-old{background:#ffeef0;color:#b31d28}
[data-theme="light"] .diff-new{background:#e6ffec;color:#22863a}
[data-theme="light"] .file-header{background:#f6f8fa;border-color:rgba(0,0,0,.12)}
.theme-toggle{position:fixed;top:16px;right:16px;z-index:999;background:rgba(128,128,128,.15);border:1px solid rgba(128,128,128,.25);color:var(--text);border-radius:8px;padding:6px 12px;font-size:.85rem;font-weight:300;font-family:inherit;cursor:pointer;transition:background-color .15s}
.theme-toggle:hover{background:rgba(128,128,128,.25)}
.gh-link{position:fixed;top:56px;right:16px;z-index:999;background:rgba(128,128,128,.15);border:1px solid rgba(128,128,128,.25);color:var(--text);border-radius:8px;padding:6px 12px;font-size:.85rem;font-weight:300;font-family:inherit;cursor:pointer;text-decoration:none;display:inline-flex;align-items:center;gap:6px;transition:background-color .15s}
.gh-link:hover{background:rgba(128,128,128,.25);color:var(--muted);text-decoration:none}
[data-theme="overpinku"] .gh-link{background:rgba(255,20,147,.12);border-color:rgba(255,20,147,.3);color:#5c1a3a}
[data-theme="overpinku"] .gh-link:hover{background:rgba(255,20,147,.22);color:#5c1a3a}
[data-theme="overpinku"] .theme-toggle{background:rgba(255,20,147,.12);border-color:rgba(255,20,147,.3);color:#5c1a3a;animation:pinku-heartbeat 2.5s ease-in-out infinite}
[data-theme="overpinku"] .theme-toggle:hover{background:rgba(255,20,147,.22)}
html[data-theme="overpinku"],html[data-theme="overpinku"] body{background-image:radial-gradient(circle,rgba(255,105,180,.22) 1.5px,transparent 1.5px);background-size:22px 22px}
[data-theme="overpinku"] h2,[data-theme="overpinku"] h5{color:#e91e8c}
[data-theme="overpinku"] ::selection{background:rgba(255,20,147,.25);color:#5c1a3a}
[data-theme="overpinku"] ::-webkit-scrollbar{width:8px}[data-theme="overpinku"] ::-webkit-scrollbar-track{background:#ffe4ee}[data-theme="overpinku"] ::-webkit-scrollbar-thumb{background:#ff69b4;border-radius:10px}[data-theme="overpinku"] ::-webkit-scrollbar-thumb:hover{background:#e91e8c}
@keyframes pinku-heartbeat{0%,100%{transform:scale(1)}50%{transform:scale(1.07)}}
CSS; }

// ── Page template ─────────────────────────────────────────────────────────────
function page_open(string $title): void {
    $styles = ags_page_styles();
    echo <<<HTML
<!DOCTYPE html>
<html lang="en" data-theme="dark">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{$title}</title>
<script>(function(){var t=localStorage.getItem('theme')||'dark';document.documentElement.dataset.theme=t;})()</script>
<link href="https://fonts.googleapis.com/css2?family=Roboto:wght@300;400;500&display=swap" rel="stylesheet">
<style>{$styles}</style>
</head>
<body>
<div class="container">
<h2 class="mb-1">Script Library Updater</h2>
<p class="text-muted mb-4">Pulls the latest scripts from git and re-applies your saved settings automatically.</p>
HTML;
}

function page_close(): void {
    echo <<<'HTML'
</div>
<a class="gh-link" href="https://github.com/Leander-Andersen/public-ags-scripts/issues/new/choose" target="_blank" rel="noopener">🐛 Bug / Feature</a>
<button class="theme-toggle" onclick="toggleTheme()" aria-label="Toggle theme" id="theme-btn">Light</button>
<script>
(function(){
  var NEXT={dark:'light',light:'overpinku',overpinku:'dark'};
  var LABEL={dark:'Light',light:'OverPinku \u2665',overpinku:'Dark'};
  function applyTheme(t,save){
    document.documentElement.dataset.theme=t;
    document.getElementById('theme-btn').textContent=LABEL[t]||'Light';
    if(save)localStorage.setItem('theme',t);
  }
  window.toggleTheme=function(){applyTheme(NEXT[document.documentElement.dataset.theme]||'light',true);};
  applyTheme(localStorage.getItem('theme')||'dark',false);
  var _ph=['♥','♥','♥','♡','❤'],_pc=['#ff69b4','#ff1493','#e91e8c','#ff85c2','#c2185b','#ffb3d9'];
  document.addEventListener('click',function(e){
    if(document.documentElement.dataset.theme!=='overpinku')return;
    var n=7+Math.floor(Math.random()*5);
    for(var i=0;i<n;i++)(function(){
      var el=document.createElement('span');
      el.textContent=_ph[Math.floor(Math.random()*_ph.length)];
      var sz=20+Math.random()*14,a=(Math.random()-.5)*Math.PI*1.5,d=60+Math.random()*90;
      var dx=Math.sin(a)*d,dy=-(55+Math.random()*85),dur=.55+Math.random()*.4;
      el.style.cssText='position:fixed;left:'+e.clientX+'px;top:'+e.clientY+'px;font-size:'+sz+'px;color:'+_pc[Math.floor(Math.random()*_pc.length)]+';pointer-events:none;user-select:none;z-index:99999;transform:translate(-50%,-50%) scale(1.3);opacity:1;transition:none';
      document.body.appendChild(el);
      requestAnimationFrame(function(){requestAnimationFrame(function(){
        el.style.transition='transform '+dur+'s ease-out,opacity '+dur+'s ease-in';
        el.style.transform='translate(calc(-50% + '+dx+'px),calc(-50% + '+dy+'px)) scale(0.2)';
        el.style.opacity='0';
      });});
      setTimeout(function(){if(el.parentNode)el.parentNode.removeChild(el);},(dur+.2)*1000);
    })();
    var lnk=e.target.closest('a[href]');
    if(!lnk||lnk.target||e.ctrlKey||e.metaKey||e.shiftKey||lnk.download)return;
    try{if(new URL(lnk.href).origin!==window.location.origin)return;}catch(_){return;}
    e.preventDefault();
    setTimeout(function(){window.location.href=lnk.href;},350);
  });
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
        echo '<div class="alert alert-warning mt-3"><strong>How this works:</strong> The update will reset all repo files to the latest version (including reverting them to placeholders), re-apply your saved settings, and copy the updated file browser and viewer to the web root. Your <code>.setup-config.json</code> is never touched by git.</div>';

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

    // 1. Switch to the chosen branch and reset it to the remote state.
    //    Using checkout -B rather than reset --hard so that HEAD actually moves
    //    to the new branch (reset --hard updates files but leaves HEAD on the old branch).
    [$_out, $checkoutErr, $checkoutCode] = git('checkout', '-f', '-B', $branch, "origin/{$branch}");
    if ($checkoutCode !== 0) {
        echo '<div class="alert alert-danger"><strong>git checkout failed</strong><br><code>' . htmlspecialchars($checkoutErr) . '</code></div>';
        page_close();
        exit;
    }
    echo '<div class="alert alert-success">✅ Switched to <code>' . htmlspecialchars($branch) . '</code> and pulled latest</div>';

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

    // 4. Copy ##Extras web-root files (index.php, viewer.php, globalVariables.php) to DOCUMENT_ROOT
    //    install.sh places these files at the web root on first install; the updater must keep them in sync.
    $webroot = realpath($_SERVER['DOCUMENT_ROOT']);
    $extras  = $BASE . '/##Extras';
    $webroot_files = ['index.php', 'viewer.php', 'globalVariables.php'];
    $copy_results  = [];
    foreach ($webroot_files as $wf) {
        $src  = $extras . '/' . $wf;
        $dest = $webroot . '/' . $wf;
        if (!is_file($src)) {
            $copy_results[] = ['file' => $wf, 'status' => 'skip', 'msg' => 'Source not found in ##Extras'];
            continue;
        }
        if (copy($src, $dest)) {
            $copy_results[] = ['file' => $wf, 'status' => 'ok', 'msg' => 'Copied to web root'];
        } else {
            $copy_results[] = ['file' => $wf, 'status' => 'err', 'msg' => 'Copy failed — check permissions on ' . htmlspecialchars($dest)];
        }
    }

    echo '<h5 class="mt-3 mb-2">Web root files updated</h5>';
    echo '<ul class="list-group mb-4">';
    foreach ($copy_results as $r) {
        $icon = match($r['status']) { 'ok' => '✅', 'skip' => '⚠️', default => '❌' };
        $cls  = match($r['status']) { 'ok' => 'list-group-item-success', 'err' => 'list-group-item-danger', 'skip' => 'list-group-item-warning', default => '' };
        echo "<li class=\"list-group-item {$cls}\"><code>{$r['file']}</code> {$icon} — {$r['msg']}</li>";
    }
    echo '</ul>';

    // 5. Show new commit
    [$commit, $_e, $_c] = git('log', '-1', '--format=%h %s (%ar)');
    echo '<div class="alert alert-success"><strong>Update complete.</strong> Now at: <code>' . htmlspecialchars($commit) . '</code></div>';
    echo '<a href="update.php" class="btn btn-primary">Back to updater</a>';

    page_close();
    exit;
}

// Fallback
header('Location: update.php');
exit;
