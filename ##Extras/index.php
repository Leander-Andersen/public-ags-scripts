<?php
// ── Computation phase — nothing echoed yet ────────────────────────────────────

require_once __DIR__ . '/globalVariables.php';

$directory = getcwd();
$scanned_directory = array_diff(scandir($directory), $ignore);
$docroot = realpath($_SERVER['DOCUMENT_ROOT']);
$scheme  = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
$host    = $_SERVER['HTTP_HOST'];

// Build breadcrumb
$breadcrumb_html = '';
$curReal = realpath($directory);
if ($curReal !== $docroot) {
    $relDir = ltrim(str_replace($docroot, '', $curReal), '/\\');
    $relDir = str_replace('\\', '/', $relDir);
    $parts  = array_values(array_filter(explode('/', $relDir)));
    $crumb  = '<nav class="breadcrumb">'
            . '<a href="/"><span class="material-symbols-outlined" style="font-size:16px;vertical-align:middle">home</span></a>';
    $path = '';
    foreach ($parts as $i => $part) {
        $path .= '/' . $part;
        $crumb .= '<span class="bc-sep">›</span>';
        if ($i === array_key_last($parts)) {
            $crumb .= '<span class="bc-current">' . htmlspecialchars($part) . '</span>';
        } else {
            $crumb .= '<a href="' . htmlspecialchars($path) . '/">' . htmlspecialchars($part) . '</a>';
        }
    }
    $crumb .= '</nav>';
    $breadcrumb_html = $crumb;
}

// Build file/folder list
$items_html = '';
foreach ($scanned_directory as $file) {
    if (is_dir($file)) {
        $items_html .= '<li>'
            . '<span class="material-symbols-outlined folderIcon">folder</span>'
            . '<a href="' . $file . '/">' . $file . '/</a>'
            . '</li>';
    } else {
        $filesize = filesize($file);
        $mtime    = filemtime($file);
        $ext      = strtolower(pathinfo($file, PATHINFO_EXTENSION));

        $fullPath = realpath($directory . DIRECTORY_SEPARATOR . $file);
        $relPath  = ltrim(str_replace($docroot, '', $fullPath), '/');

        if (in_array($ext, ['md', 'markdown'])) {
            $href = '/viewer.php?f=' . rawurlencode($relPath);
        } else {
            $href = '/' . $relPath;
        }

        $fullUrl = $scheme . '://' . $host . $href;

        $items_html .= '<li>'
            . '<span class="material-symbols-outlined fileIcon">draft</span>'
            . '<a href="' . $href . '">' . $file . '</a>'
            . '<span class="file-meta">'
            .   '<span class="file-mtime">' . date('Y-m-d', $mtime) . '</span>'
            .   '<span class="file-size">' . formatSizeUnits($filesize) . '</span>'
            . '</span>'
            . '<button class="copy-btn" data-url="' . htmlspecialchars($fullUrl) . '" title="Copy URL" aria-label="Copy URL">'
            .   '<span class="material-symbols-outlined">content_copy</span>'
            . '</button>'
            . '</li>';
    }
}

function formatSizeUnits($bytes)
{
    if ($bytes >= 1073741824)      { return number_format($bytes / 1073741824, 2) . ' GB'; }
    elseif ($bytes >= 1048576)     { return number_format($bytes / 1048576, 2) . ' MB'; }
    elseif ($bytes >= 1024)        { return number_format($bytes / 1024, 2) . ' KB'; }
    elseif ($bytes > 1)            { return $bytes . ' bytes'; }
    elseif ($bytes == 1)           { return $bytes . ' byte'; }
    else                           { return '0 bytes'; }
}
?>
<!DOCTYPE html>
<html lang="en">

<head>
    <!-- Matomo -->
    <script>
        var _paq = window._paq = window._paq || [];
        _paq.push(['trackPageView']);
        _paq.push(['enableLinkTracking']);
        (function () {
            var u = "https://isame12.matomo.cloud/";
            _paq.push(['setTrackerUrl', u + 'matomo.php']);
            _paq.push(['setSiteId', '1']);
            var d = document, g = d.createElement('script'), s = d.getElementsByTagName('script')[0];
            g.async = true; g.src = 'https://cdn.matomo.cloud/isame12.matomo.cloud/matomo.js'; s.parentNode.insertBefore(g, s);
        })();
    </script>
    <!-- End Matomo Code -->

    <!-- Cloudflare Web Analytics -->
    <script defer src='https://static.cloudflareinsights.com/beacon.min.js'
        data-cf-beacon='{"token": "b7955e23dd9f4876a776a0ad6bd7d752"}'></script>
    <!-- End Cloudflare Web Analytics -->

    <meta charset="utf-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <title>public-ags-scripts</title>
    <link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Cpath fill='%23e91e8c' d='M16 28C16 28 3 18 3 10.5C3 6.5 6.5 3.5 10.5 3.5C13 3.5 15.2 5 16 7C16.8 5 19 3.5 21.5 3.5C25.5 3.5 29 6.5 29 10.5C29 18 16 28 16 28Z'/%3E%3Ccircle cx='11' cy='10' r='2' fill='white' opacity='0.55'/%3E%3C/svg%3E">
    <meta name="description" content="">
    <meta name="viewport" content="width=device-width, initial-scale=1">

    <!-- Fonts & icons -->
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Roboto:ital,wght@0,100;0,300;0,400;0,500;0,700;0,900;1,100;1,300;1,400;1,500;1,700;1,900&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:opsz,wght,FILL,GRAD@24,400,0,0" />

    <style>
        /* ── Theme tokens ───────────────────────────────── */
        :root {
            --bg:    #181818;
            --text:  #fff;
            --muted: rgb(143, 143, 143);
            --hover: rgba(255, 255, 255, 0.06);
        }

        [data-theme="light"] {
            --bg:    #e8eaed;
            --text:  #212529;
            --muted: #6c757d;
            --hover: rgba(0, 0, 0, 0.07);
        }

        [data-theme="overpinku"] {
            --bg:    #fff0f5;
            --text:  #5c1a3a;
            --muted: #b05070;
            --hover: rgba(255, 20, 147, 0.12);
        }

        /* ── Base ───────────────────────────────────────── */
        /* Only set background on html/body — all other elements stay transparent
           so that li:hover covers the full row including text and icons. */
        * {
            font-family: 'Roboto', Courier, monospace;
            font-weight: 300;
            color: var(--text);
            box-sizing: border-box;
            transition: color 0.25s ease;
        }

        html, body {
            margin: 0;
            padding: 0;
            min-height: 100vh;
            background-color: var(--bg);
            transition: background-color 0.25s ease, color 0.25s ease;
        }

        /* ── Layout ─────────────────────────────────────── */
        .container {
            padding: 28px max(40px, 4vw);
        }

        .page-title {
            font-weight: 400;
            font-size: 1.4rem;
            margin: 0 0 16px;
        }

        /* ── Back link ──────────────────────────────────── */
        .top-link {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            margin-bottom: 12px;
            color: var(--text);
            text-decoration: none;
            font-size: 0.95rem;
        }

        .top-link:hover {
            color: var(--muted);
            text-decoration: none;
        }

        /* ── File list ──────────────────────────────────── */
        ul {
            list-style-type: none;
            padding: 0;
            margin: 0;
        }

        li {
            display: flex;
            align-items: center;
            gap: 10px;
            padding: 8px 12px;
            border-radius: 6px;
            margin: 2px 0;
            transition: background-color 0.15s ease;
        }

        li:hover {
            background-color: var(--hover);
        }

        a {
            text-decoration: none;
            color: var(--text);
            font-size: larger;
        }

        a:hover {
            text-decoration: underline;
            color: var(--muted);
        }

        /* ── File meta (date + size) ────────────────────── */
        .file-meta {
            margin-left: auto;
            display: flex;
            align-items: center;
            gap: 10px;
            flex-shrink: 0;
        }

        .file-mtime {
            font-size: 0.75rem;
            color: var(--muted);
            white-space: nowrap;
        }

        .file-size {
            font-size: 0.8rem;
            color: var(--muted);
            white-space: nowrap;
        }

        /* ── Copy button ─────────────────────────────────── */
        .copy-btn {
            background: transparent;
            border: none;
            padding: 2px 4px;
            border-radius: 4px;
            color: var(--muted);
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            opacity: 0;
            flex-shrink: 0;
            transition: opacity 0.15s, color 0.15s;
        }

        li:hover .copy-btn { opacity: 1; }
        .copy-btn:hover    { color: var(--text); }

        .copy-btn .material-symbols-outlined { font-size: 16px; }

        .copy-btn.copied { color: #4caf50; opacity: 1; }

        /* ── Filter box ──────────────────────────────────── */
        .filter-box {
            width: 100%;
            max-width: 380px;
            padding: 7px 12px;
            margin-bottom: 12px;
            background: rgba(128, 128, 128, 0.08);
            border: 1px solid rgba(128, 128, 128, 0.2);
            border-radius: 6px;
            color: var(--text);
            font-family: 'Roboto', sans-serif;
            font-size: 0.9rem;
            font-weight: 300;
            outline: none;
            transition: border-color 0.2s;
        }

        .filter-box::placeholder { color: var(--muted); }
        .filter-box:focus        { border-color: rgba(128, 128, 128, 0.4); }

        [data-theme="overpinku"] .filter-box {
            background: rgba(255, 20, 147, 0.04);
            border-color: rgba(255, 20, 147, 0.2);
        }
        [data-theme="overpinku"] .filter-box:focus {
            border-color: rgba(255, 20, 147, 0.45);
        }

        /* ── Breadcrumb ──────────────────────────────────── */
        .breadcrumb {
            display: flex;
            align-items: center;
            gap: 5px;
            margin-bottom: 12px;
            flex-wrap: wrap;
        }

        .breadcrumb a {
            color: var(--muted);
            text-decoration: none;
            font-size: 0.88rem;
        }

        .breadcrumb a:hover { color: var(--text); text-decoration: underline; }

        .bc-sep     { color: var(--muted); font-size: 0.8rem; }
        .bc-current { color: var(--text);  font-size: 0.88rem; }

        /* ── Icons ──────────────────────────────────────── */
        .folderIcon { color: purple; }
        .fileIcon   { color: pink; }

        [data-theme="light"] .folderIcon { color: #6f42c1; }
        [data-theme="light"] .fileIcon   { color: #d63384; }

        [data-theme="overpinku"] .folderIcon { color: #e91e8c; }
        [data-theme="overpinku"] .fileIcon   { color: #9c27b0; }

        #PD { font-size: small; }

        .material-symbols-outlined {
            font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 40;
        }

        /* ── Theme toggle ───────────────────────────────── */
        .theme-toggle {
            position: fixed;
            top: 16px;
            right: 16px;
            background: rgba(128, 128, 128, 0.15);
            border: 1px solid rgba(128, 128, 128, 0.25);
            color: var(--text);
            border-radius: 8px;
            padding: 6px 10px;
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            gap: 6px;
            font-size: 0.85rem;
            font-family: 'Roboto', sans-serif;
            font-weight: 300;
            transition: background-color 0.15s;
        }

        .theme-toggle:hover {
            background: rgba(128, 128, 128, 0.25);
        }

        /* ── GitHub link button ─────────────────────────── */
        .gh-link {
            position: fixed;
            top: 56px;
            right: 16px;
            background: rgba(128, 128, 128, 0.15);
            border: 1px solid rgba(128, 128, 128, 0.25);
            color: var(--text);
            border-radius: 8px;
            padding: 6px 10px;
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            gap: 6px;
            font-size: 0.85rem;
            font-family: 'Roboto', sans-serif;
            font-weight: 300;
            text-decoration: none;
            transition: background-color 0.15s;
        }

        .gh-link:hover {
            background: rgba(128, 128, 128, 0.25);
            text-decoration: none;
            color: var(--muted);
        }

        [data-theme="overpinku"] .gh-link {
            background: rgba(255, 20, 147, 0.12);
            border-color: rgba(255, 20, 147, 0.3);
            color: #5c1a3a;
        }

        [data-theme="overpinku"] .gh-link:hover {
            background: rgba(255, 20, 147, 0.22);
            color: #5c1a3a;
        }

        [data-theme="overpinku"] .theme-toggle {
            background: rgba(255, 20, 147, 0.12);
            border-color: rgba(255, 20, 147, 0.3);
            color: #5c1a3a;
            animation: pinku-heartbeat 2.5s ease-in-out infinite;
        }

        [data-theme="overpinku"] .theme-toggle:hover {
            background: rgba(255, 20, 147, 0.22);
        }

        /* ── OverPinku extras ───────────────────────────── */
        html[data-theme="overpinku"],
        html[data-theme="overpinku"] body {
            background-image: radial-gradient(circle, rgba(255, 105, 180, 0.22) 1.5px, transparent 1.5px);
            background-size: 22px 22px;
        }

        /* ── OverPinku: shimmer title ────────────────────── */
        [data-theme="overpinku"] .page-title {
            background: linear-gradient(90deg, #e91e8c, #ff69b4, #ff1493, #ff85c2, #e91e8c);
            background-size: 200% auto;
            -webkit-background-clip: text;
            background-clip: text;
            color: transparent;
            animation: title-shimmer 4s linear infinite;
        }

        @keyframes title-shimmer {
            0%   { background-position: 0% center; }
            100% { background-position: 200% center; }
        }

        /* ── OverPinku: heart cursor (tip = bottom point of heart) ── */
        [data-theme="overpinku"],
        [data-theme="overpinku"] * {
            cursor: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='32' height='32' viewBox='0 0 32 32'%3E%3Cpath fill='%23e91e8c' stroke='white' stroke-width='1.5' stroke-linejoin='round' d='M16 29C16 29 3 19 3 11C3 6.5 6.5 3.5 10.5 3.5C13 3.5 15.2 5 16 7C16.8 5 19 3.5 21.5 3.5C25.5 3.5 29 6.5 29 11C29 19 16 29 16 29Z'/%3E%3C/svg%3E") 16 29, auto;
        }

        /* ── OverPinku: sakura petals ────────────────────── */
        .sakura-petal {
            position: fixed;
            top: -30px;
            pointer-events: none;
            user-select: none;
            z-index: 0;
            animation: sakura-fall linear infinite;
        }

        @keyframes sakura-fall {
            0%   { transform: translateY(0)    rotate(0deg)   translateX(0);    }
            25%  { transform: translateY(25vh)  rotate(90deg)  translateX(18px);  }
            50%  { transform: translateY(50vh)  rotate(180deg) translateX(-12px); }
            75%  { transform: translateY(75vh)  rotate(270deg) translateX(14px);  }
            100% { transform: translateY(110vh) rotate(360deg) translateX(0);    }
        }

        [data-theme="overpinku"] ::selection { background: rgba(255, 20, 147, 0.25); color: #5c1a3a; }

        [data-theme="overpinku"] ::-webkit-scrollbar { width: 8px; }
        [data-theme="overpinku"] ::-webkit-scrollbar-track { background: #ffe4ee; }
        [data-theme="overpinku"] ::-webkit-scrollbar-thumb { background: #ff69b4; border-radius: 10px; }
        [data-theme="overpinku"] ::-webkit-scrollbar-thumb:hover { background: #e91e8c; }

        @keyframes pinku-heartbeat {
            0%, 100% { transform: scale(1); }
            50%       { transform: scale(1.07); }
        }
    </style>

    <!-- Apply saved theme before first paint to prevent flash -->
    <script>
        (function () {
            var t = localStorage.getItem('theme') || 'dark';
            document.documentElement.dataset.theme = t;
        })();
    </script>
</head>

<body>
    <div class="container">
        <h2 class="page-title">Leander's skibidi skripter</h2>

        <?php echo $breadcrumb_html; ?>

        <input class="filter-box" type="search" id="filter" placeholder="Filter…" autocomplete="off" aria-label="Filter files">

        <ul id="file-list">
            <?php echo $items_html; ?>
        </ul>
    </div>

    <a class="gh-link" href="https://github.com/Leander-Andersen/public-ags-scripts/issues/new/choose"
       target="_blank" rel="noopener" aria-label="Report bug or request feature">
        <span class="material-symbols-outlined" style="font-size:18px">bug_report</span>
        <span>Bug / Feature</span>
    </a>

    <button class="theme-toggle" onclick="toggleTheme()" aria-label="Toggle theme">
        <span class="material-symbols-outlined" id="theme-icon" style="font-size:18px">dark_mode</span>
        <span id="theme-label">Light</span>
    </button>

    <script>
        (function () {
            var NEXT  = {dark: 'light', light: 'overpinku', overpinku: 'dark'};
            var LABEL = {dark: 'Light', light: 'OverPinku', overpinku: 'Dark'};
            var ICON  = {dark: 'dark_mode', light: 'light_mode', overpinku: 'favorite'};

            // ── Sakura petals ──────────────────────────────────
            var _petals = [];
            var _petalChars  = ['✿', '❀', '✾', '❁'];
            var _petalColors = ['#ffb3d9', '#ff85c2', '#ff69b4', '#ffcce6', '#ffd6e0'];

            function spawnPetals() {
                clearPetals();
                if (document.documentElement.dataset.theme !== 'overpinku') return;
                for (var i = 0; i < 18; i++) (function() {
                    var el  = document.createElement('span');
                    el.className = 'sakura-petal';
                    el.textContent = _petalChars[Math.floor(Math.random() * _petalChars.length)];
                    var sz  = 10 + Math.random() * 10;
                    var dur = 7 + Math.random() * 8;
                    el.style.cssText = 'left:' + (Math.random() * 100) + 'vw;'
                        + 'font-size:' + sz + 'px;'
                        + 'color:' + _petalColors[Math.floor(Math.random() * _petalColors.length)] + ';'
                        + 'opacity:' + (0.35 + Math.random() * 0.4) + ';'
                        + 'animation-duration:' + dur + 's;'
                        + 'animation-delay:' + (Math.random() * -dur) + 's;';
                    document.body.appendChild(el);
                    _petals.push(el);
                })();
            }

            function clearPetals() {
                _petals.forEach(function(el) { if (el.parentNode) el.parentNode.removeChild(el); });
                _petals = [];
            }

            function applyTheme(t, save) {
                document.documentElement.dataset.theme = t;
                document.getElementById('theme-icon').textContent  = ICON[t]  || 'dark_mode';
                document.getElementById('theme-label').textContent = LABEL[t] || 'Light';
                if (save) localStorage.setItem('theme', t);
                spawnPetals();
            }

            window.toggleTheme = function () {
                applyTheme(NEXT[document.documentElement.dataset.theme] || 'light', true);
            };

            var saved = localStorage.getItem('theme') || 'dark';
            applyTheme(saved, false);

            // ── Copy URL buttons ───────────────────────────────
            document.addEventListener('click', function(e) {
                var btn = e.target.closest('.copy-btn');
                if (!btn) return;
                e.stopPropagation();
                var url = btn.dataset.url;
                var icon = btn.querySelector('.material-symbols-outlined');
                navigator.clipboard.writeText(url).then(function() {
                    btn.classList.add('copied');
                    icon.textContent = 'check';
                    setTimeout(function() {
                        btn.classList.remove('copied');
                        icon.textContent = 'content_copy';
                    }, 1500);
                });
            });

            // ── Filter ────────────────────────────────────────
            document.getElementById('filter').addEventListener('input', function() {
                var q = this.value.toLowerCase();
                document.querySelectorAll('#file-list li').forEach(function(li) {
                    var a = li.querySelector('a');
                    li.style.display = (!a || a.textContent.toLowerCase().includes(q)) ? '' : 'none';
                });
            });

            // ── OverPinku: hearts on click ─────────────────────
            var _ph = ['♥', '♥', '♥', '♡', '❤'];
            var _pc = ['#ff69b4', '#ff1493', '#e91e8c', '#ff85c2', '#c2185b', '#ffb3d9'];
            document.addEventListener('click', function(e) {
                if (e.target.closest('.copy-btn')) return;
                if (document.documentElement.dataset.theme !== 'overpinku') return;
                var n = 7 + Math.floor(Math.random() * 5);
                for (var i = 0; i < n; i++) (function() {
                    var el  = document.createElement('span');
                    el.textContent = _ph[Math.floor(Math.random() * _ph.length)];
                    var sz  = 20 + Math.random() * 14;
                    var a   = (Math.random() - 0.5) * Math.PI * 1.5;
                    var d   = 60 + Math.random() * 90;
                    var dx  = Math.sin(a) * d, dy = -(55 + Math.random() * 85);
                    var dur = 0.55 + Math.random() * 0.4;
                    el.style.cssText = 'position:fixed;left:' + e.clientX + 'px;top:' + e.clientY + 'px;' +
                        'font-size:' + sz + 'px;color:' + _pc[Math.floor(Math.random() * _pc.length)] + ';' +
                        'pointer-events:none;user-select:none;z-index:99999;' +
                        'transform:translate(-50%,-50%) scale(1.3);opacity:1;transition:none';
                    document.body.appendChild(el);
                    requestAnimationFrame(function() { requestAnimationFrame(function() {
                        el.style.transition = 'transform ' + dur + 's ease-out, opacity ' + dur + 's ease-in';
                        el.style.transform  = 'translate(calc(-50% + ' + dx + 'px), calc(-50% + ' + dy + 'px)) scale(0.2)';
                        el.style.opacity    = '0';
                    }); });
                    setTimeout(function() { if (el.parentNode) el.parentNode.removeChild(el); }, (dur + 0.2) * 1000);
                })();
                var lnk = e.target.closest('a[href]');
                if (!lnk || lnk.target || e.ctrlKey || e.metaKey || e.shiftKey || lnk.download) return;
                try { if (new URL(lnk.href).origin !== window.location.origin) return; } catch (_) { return; }
                e.preventDefault();
                setTimeout(function() { window.location.href = lnk.href; }, 350);
            });

            // ── Konami code → OverPinku ────────────────────────
            var _kc = [38,38,40,40,37,39,37,39,66,65], _ki = 0;
            document.addEventListener('keydown', function(e) {
                _ki = (e.keyCode === _kc[_ki]) ? _ki + 1 : 0;
                if (_ki === _kc.length) { _ki = 0; applyTheme('overpinku', true); }
            });
        })();
    </script>
</body>

</html>
