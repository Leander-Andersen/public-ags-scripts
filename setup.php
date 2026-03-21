<?php
ini_set('log_errors', '1');
ini_set('error_log', __DIR__ . '/php-errors.log');

session_start();

// ── Lock check ────────────────────────────────────────────────────────────────
$LOCK_FILE = __DIR__ . '/setup.lock';
if (file_exists($LOCK_FILE)) {
    $locked_at = trim(file_get_contents($LOCK_FILE));
?><!DOCTYPE html><html lang="en" data-theme="dark"><head><meta charset="UTF-8"><title>Setup locked</title>
<link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Cpath fill='%23e91e8c' d='M16 28C16 28 3 18 3 10.5C3 6.5 6.5 3.5 10.5 3.5C13 3.5 15.2 5 16 7C16.8 5 19 3.5 21.5 3.5C25.5 3.5 29 6.5 29 10.5C29 18 16 28 16 28Z'/%3E%3Ccircle cx='11' cy='10' r='2' fill='white' opacity='0.55'/%3E%3C/svg%3E">
<script>(function(){var t=localStorage.getItem('theme')||'dark';document.documentElement.dataset.theme=t;})()</script>
<link href="https://fonts.googleapis.com/css2?family=Roboto:wght@300;400;500&display=swap" rel="stylesheet">
<style><?php echo ags_page_styles(); ?></style>
</head><body><div class="container">
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

// ── Placeholders used in scripts ─────────────────────────────────────────────
// Use these in any .ps1 or .php file — setup.php will replace them automatically.
//   <SCRIPT_DOMAIN>  →  domain/subdomain the scripts are served from
//   <SCRIPT_FOLDER>  →  folder name on the web server (repo root folder)

const PLACEHOLDER_DOMAIN = '<SCRIPT_DOMAIN>';
const PLACEHOLDER_FOLDER = '<SCRIPT_FOLDER>';

// ── File scanner ──────────────────────────────────────────────────────────────
// Recursively finds all text files that contain at least one placeholder.
// Skips: setup.php itself, setup.lock, .bak files, .git/, and binary files.
function find_target_files(string $base): array {
    $skip_names = ['setup.php', 'update.php', 'setup.lock'];
    $skip_dirs  = ['.git', '.github', '.vscode', 'node_modules'];
    $text_exts  = ['php', 'ps1', 'psm1', 'psd1', 'sh', 'bat', 'cmd', 'txt', 'md', 'json', 'xml', 'html', 'htm', 'css', 'js'];
    $placeholders = [PLACEHOLDER_DOMAIN, PLACEHOLDER_FOLDER];

    $files = [];
    $iter  = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($base, FilesystemIterator::SKIP_DOTS)
    );

    foreach ($iter as $file) {
        if (!$file->isFile()) continue;

        // Skip unwanted directories
        $rel = str_replace($base . DIRECTORY_SEPARATOR, '', $file->getPathname());
        $rel = str_replace('\\', '/', $rel);
        foreach ($skip_dirs as $d) {
            if (strpos($rel, $d . '/') === 0) continue 2;
        }

        // Skip unwanted filenames and .bak files
        $fname = $file->getFilename();
        if (in_array($fname, $skip_names)) continue;
        if (substr($fname, -4) === '.bak') continue;

        // Only process known text extensions
        $ext = strtolower($file->getExtension());
        if (!in_array($ext, $text_exts)) continue;

        // Only include files that actually contain a placeholder
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

// ── Permission check ─────────────────────────────────────────────────────────
// Returns an HTML warning string if permissions aren't right, null if fine.
function permission_warning(string $base): ?string {
    $user = 'www-data';
    if (function_exists('posix_geteuid') && function_exists('posix_getpwuid')) {
        $info = posix_getpwuid(posix_geteuid());
        if (!empty($info['name'])) $user = $info['name'];
    }

    $warnings = [];

    // Check scripts folder is writable (needed to rewrite files)
    if (!is_writable($base)) {
        $cmd = htmlspecialchars("sudo chown -R {$user}:{$user} {$base}");
        $warnings[] = "Scripts folder not writable — run: <pre class=\"mt-1 mb-0 p-2 bg-body-secondary border rounded\">{$cmd}</pre>";
    }

    // Check parent directory is writable (needed to rename the folder)
    $parent = dirname($base);
    if (!is_writable($parent)) {
        $cmd = htmlspecialchars("sudo chown {$user}:{$user} {$parent}");
        $warnings[] = "Web root directory not writable (needed to rename the scripts folder) — run: <pre class=\"mt-1 mb-0 p-2 bg-body-secondary border rounded\">{$cmd}</pre>";
    }

    if (empty($warnings)) return null;

    $html = '<div class="alert alert-danger"><strong>Permission error</strong><ul class="mb-0 mt-2">';
    foreach ($warnings as $w) $html .= "<li class=\"mb-2\">{$w}</li>";
    $html .= '</ul></div>';
    return $html;
}

// ── Helpers ───────────────────────────────────────────────────────────────────
function build_replacements(string $domain, string $folder): array {
    return [
        PLACEHOLDER_DOMAIN => $domain,
        PLACEHOLDER_FOLDER => $folder,
    ];
}

function get_preview(array $files, array $replacements, string $base): array {
    $preview = [];
    foreach ($files as $rel) {
        $path  = $base . '/' . $rel;
        $lines = file($path);
        $diffs = [];
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

function apply_changes(array $files, array $replacements, string $base): array {
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
            $results[] = ['file' => $rel, 'status' => 'unchanged', 'msg' => 'Nothing to change'];
            continue;
        }
        file_put_contents($path . '.bak', $orig);
        if (file_put_contents($path, $new) !== false) {
            $results[] = ['file' => $rel, 'status' => 'ok', 'msg' => 'Updated — backup saved as ' . basename($rel) . '.bak'];
        } else {
            $results[] = ['file' => $rel, 'status' => 'err', 'msg' => 'Write failed — check file permissions'];
        }
    }
    return $results;
}

function cleanup_bak_files(string $base): int {
    $count = 0;
    $iter  = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($base, FilesystemIterator::SKIP_DOTS)
    );
    foreach ($iter as $file) {
        if ($file->isFile() && substr($file->getFilename(), -4) === '.bak') {
            unlink($file->getPathname());
            $count++;
        }
    }
    return $count;
}

function validate(string $domain, string $folder): array {
    $errs = [];
    if (!preg_match('/^[a-zA-Z0-9][a-zA-Z0-9.\-]*\.[a-zA-Z]{2,}$/', $domain)) {
        $errs[] = 'Script domain looks invalid (e.g. <code>script.yourdomain.com</code>).';
    }
    if (!preg_match('/^[a-zA-Z0-9][a-zA-Z0-9_\-]*$/', $folder)) {
        $errs[] = 'Folder name must be alphanumeric (hyphens/underscores allowed, no spaces).';
    }
    return $errs;
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
[data-theme="overpinku"],[data-theme="overpinku"] *{cursor:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='32' height='32' viewBox='0 0 32 32'%3E%3Cpath fill='%23e91e8c' stroke='white' stroke-width='1.5' stroke-linejoin='round' d='M16 29C16 29 3 19 3 11C3 6.5 6.5 3.5 10.5 3.5C13 3.5 15.2 5 16 7C16.8 5 19 3.5 21.5 3.5C25.5 3.5 29 6.5 29 11C29 19 16 29 16 29Z'/%3E%3C/svg%3E") 16 29,auto}
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
<link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Cpath fill='%23e91e8c' d='M16 28C16 28 3 18 3 10.5C3 6.5 6.5 3.5 10.5 3.5C13 3.5 15.2 5 16 7C16.8 5 19 3.5 21.5 3.5C25.5 3.5 29 6.5 29 10.5C29 18 16 28 16 28Z'/%3E%3Ccircle cx='11' cy='10' r='2' fill='white' opacity='0.55'/%3E%3C/svg%3E">
<script>(function(){var t=localStorage.getItem('theme')||'dark';document.documentElement.dataset.theme=t;})()</script>
<link href="https://fonts.googleapis.com/css2?family=Roboto:wght@300;400;500&display=swap" rel="stylesheet">
<style>{$styles}</style>
</head>
<body>
<div class="container">
<h2 class="mb-1">Script Library Setup</h2>
<p class="text-muted mb-4">Replaces <code>&lt;SCRIPT_DOMAIN&gt;</code> and <code>&lt;SCRIPT_FOLDER&gt;</code> placeholders across all scripts.</p>
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

// ── Route ─────────────────────────────────────────────────────────────────────
// Scan only the scripts folder — web root files no longer have placeholders.
$base        = __DIR__;
$CONFIG_FILE = __DIR__ . '/.setup-config.json';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    page_open('Setup');
    $warn = permission_warning($base);
    if ($warn) echo $warn;
    else echo render_form('', '', [], $csrf);
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
$errors  = validate($domain, $folder);

if ($errors) {
    page_open('Setup — Errors');
    echo render_form($domain, $folder, $errors, $csrf);
    page_close();
    exit;
}

$replacements = build_replacements($domain, $folder);
$target_files = find_target_files($base);

if (isset($_POST['confirm']) && $_POST['confirm'] === '1') {
    // ── Apply ─────────────────────────────────────────────────────────────────
    $results = apply_changes($target_files, $replacements, $base);

    // Save settings so update.php can re-apply them after a git pull
    $config = [
        'script_domain'  => $domain,
        'script_folder'  => $folder,
        'configured_at'  => date('c'),
    ];
    file_put_contents($CONFIG_FILE, json_encode($config, JSON_PRETTY_PRINT));
    file_put_contents($LOCK_FILE, date('c'));

    // Remove .bak files left by apply_changes()
    cleanup_bak_files($base);

    // Rename the scripts folder on disk to match what the user chose
    $current_name = basename(__DIR__);
    $rename_ok    = null;
    if ($current_name !== $folder) {
        $new_path  = dirname(__DIR__) . '/' . $folder;
        $rename_ok = rename(__DIR__, $new_path);
    }

    page_open('Setup — Done');
    echo '<h5 class="mb-3">Changes applied</h5>';
    echo '<ul class="list-group mb-4">';
    foreach ($results as $r) {
        $icon = match($r['status']) { 'ok' => '✅', 'unchanged' => '⬛', 'skip' => '⚠️', default => '❌' };
        $cls  = match($r['status']) { 'ok' => 'list-group-item-success', 'err' => 'list-group-item-danger', 'skip' => 'list-group-item-warning', default => '' };
        echo "<li class=\"list-group-item {$cls}\"><code>{$r['file']}</code> {$icon} — {$r['msg']}</li>";
    }
    if ($rename_ok === true) {
        echo "<li class=\"list-group-item list-group-item-success\">Folder renamed: <code>{$current_name}</code> → <code>" . htmlspecialchars($folder) . "</code> ✅</li>";
    } elseif ($rename_ok === false) {
        echo "<li class=\"list-group-item list-group-item-warning\">Could not rename folder automatically — please rename <code>{$current_name}</code> to <code>" . htmlspecialchars($folder) . "</code> manually.</li>";
    }
    echo '</ul>';
    $new_url = 'https://' . htmlspecialchars($domain) . '/' . htmlspecialchars($folder) . '/';
    echo "<div class=\"alert alert-success\"><strong>Setup complete.</strong> Your scripts are now live at <a href=\"{$new_url}\">{$new_url}</a></div>";
    page_close();
    exit;
}

// ── Preview ───────────────────────────────────────────────────────────────────
$preview = get_preview($target_files, $replacements, $base);

page_open('Setup — Preview');
$warn = permission_warning($base);
if ($warn) { echo $warn; page_close(); exit; }

// ── Debug panel ───────────────────────────────────────────────────────────────
echo '<details class="mb-4"><summary class="text-muted" style="cursor:pointer">Debug info</summary>';
echo '<div class="mt-2 p-3 bg-body-secondary border rounded" style="font-family:monospace;font-size:.8rem">';
echo '<strong>Base path:</strong> ' . htmlspecialchars($base) . '<br>';
echo '<strong>Replacements:</strong><br>';
foreach ($replacements as $k => $v) {
    echo '&nbsp;&nbsp;' . htmlspecialchars($k) . ' → ' . htmlspecialchars($v) . '<br>';
}
echo '<strong>Files scanned with placeholders (' . count($target_files) . '):</strong><br>';
foreach ($target_files as $f) { echo '&nbsp;&nbsp;' . htmlspecialchars($f) . '<br>'; }
echo '</div></details>';

echo '<h5 class="mb-1">Review changes</h5>';
echo '<p class="text-muted mb-3">Lines in <span class="text-danger fw-semibold">red</span> will be replaced with the <span class="text-success fw-semibold">green</span> version.</p>';

if (empty($preview)) {
    echo '<div class="alert alert-info">No placeholders found in any files — nothing to change.</div>';
} else {
    foreach ($preview as $entry) {
        echo '<div class="file-header">' . htmlspecialchars($entry['file']) . '</div>';
        echo '<div class="diff-block">';
        foreach ($entry['diffs'] as $d) {
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
    echo '<input type="hidden" name="confirm"        value="1">';
    echo '<button type="submit" class="btn btn-success me-2">Apply changes</button>';
    echo '<a href="setup.php" class="btn btn-outline-secondary">Back</a>';
    echo '</form>';
}

page_close();

// ── Form renderer ─────────────────────────────────────────────────────────────
function render_form(string $domain, string $folder, array $errors, string $csrf): string {
    $d_val = htmlspecialchars($domain);
    $f_val = htmlspecialchars($folder);
    $out   = '';

    if ($errors) {
        $out .= '<div class="alert alert-danger"><ul class="mb-0">';
        foreach ($errors as $e) { $out .= "<li>{$e}</li>"; }
        $out .= '</ul></div>';
    }

    $out .= <<<HTML
<form method="post">
  <input type="hidden" name="csrf_token" value="{$csrf}">

  <div class="mb-3">
    <label class="form-label fw-semibold" for="script_domain">Script domain</label>
    <input class="form-control" id="script_domain" name="script_domain"
           placeholder="script.yourdomain.com" value="{$d_val}" required>
    <div class="form-text">Replaces <code>&lt;SCRIPT_DOMAIN&gt;</code> in all scripts.</div>
  </div>

  <div class="mb-3">
    <label class="form-label fw-semibold" for="folder_name">Script folder name</label>
    <input class="form-control" id="folder_name" name="folder_name"
           placeholder="my-scripts" value="{$f_val}" required>
    <div class="form-text">Replaces <code>&lt;SCRIPT_FOLDER&gt;</code> in all scripts. Must match the actual folder name on the web server.</div>
  </div>

  <button type="submit" class="btn btn-primary">Preview changes</button>
</form>
HTML;

    return $out;
}
