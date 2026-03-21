<?php
// ── Computation phase — nothing echoed yet ────────────────────────────────────

require_once __DIR__ . '/globalVariables.php';

$directory = getcwd();
$scanned_directory = array_diff(scandir($directory), $ignore);

// Build parent directory link
$parent_link_html = '';
if (realpath($directory) !== realpath($_SERVER['DOCUMENT_ROOT'])) {
    $parent_link_html = '<a class="top-link" href="../">'
        . '<span id="PD" class="material-symbols-outlined">arrow_back</span>'
        . 'Parent Directory</a>';
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
        $ext = strtolower(pathinfo($file, PATHINFO_EXTENSION));

        $fullPath = realpath($directory . DIRECTORY_SEPARATOR . $file);
        $docroot  = realpath($_SERVER['DOCUMENT_ROOT']);
        $relPath  = ltrim(str_replace($docroot, '', $fullPath), '/');

        if (in_array($ext, ['md', 'markdown'])) {
            $href = '/viewer.php?f=' . rawurlencode($relPath);
        } else {
            $href = '/' . $relPath;
        }

        $items_html .= '<li>'
            . '<span class="material-symbols-outlined fileIcon">draft</span>'
            . '<a href="' . $href . '">' . $file . '</a>'
            . '<span class="file-size">' . formatSizeUnits($filesize) . '</span>'
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

        .file-size {
            margin-left: auto;
            font-size: 0.8rem;
            color: var(--muted);
            white-space: nowrap;
        }

        /* ── Icons ──────────────────────────────────────── */
        .folderIcon { color: purple; }
        .fileIcon   { color: pink; }

        [data-theme="light"] .folderIcon { color: #6f42c1; }
        [data-theme="light"] .fileIcon   { color: #d63384; }

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

        <?php echo $parent_link_html; ?>

        <ul>
            <?php echo $items_html; ?>
        </ul>
    </div>

    <button class="theme-toggle" onclick="toggleTheme()" aria-label="Toggle theme">
        <span class="material-symbols-outlined" id="theme-icon" style="font-size:18px">dark_mode</span>
        <span id="theme-label">Light</span>
    </button>

    <script>
        (function () {
            function applyTheme(t, save) {
                document.documentElement.dataset.theme = t;
                document.getElementById('theme-icon').textContent  = t === 'dark' ? 'dark_mode' : 'light_mode';
                document.getElementById('theme-label').textContent = t === 'dark' ? 'Light' : 'Dark';
                if (save) localStorage.setItem('theme', t);
            }

            window.toggleTheme = function () {
                var current = document.documentElement.dataset.theme;
                applyTheme(current === 'dark' ? 'light' : 'dark', true);
            };

            // Sync button state with whatever the inline script set
            var saved = localStorage.getItem('theme') || 'dark';
            applyTheme(saved, false);
        })();
    </script>
</body>

</html>
