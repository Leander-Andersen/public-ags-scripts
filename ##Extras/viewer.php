<?php
// viewer.php - safely render markdown files inside the docroot
// Usage: viewer.php?f=relative/path/to/README.md

declare(strict_types=1);

// ---- CONFIG ----
$docroot = realpath($_SERVER['DOCUMENT_ROOT']); // e.g. /var/www/html
// ----------------

// get requested file
$fileParam = $_GET['f'] ?? '';
if ($fileParam === '') {
    http_response_code(400);
    echo "Missing file parameter.";
    exit;
}

// normalize and prevent traversal
$requested = realpath($docroot . DIRECTORY_SEPARATOR . $fileParam);
if ($requested === false || strpos($requested, $docroot) !== 0) {
    http_response_code(403);
    echo "Access denied.";
    exit;
}

// only allow .md (optional: allow .markdown)
$ext = strtolower(pathinfo($requested, PATHINFO_EXTENSION));
if (!in_array($ext, ['md', 'markdown'])) {
    http_response_code(415);
    echo "Unsupported file type.";
    exit;
}

// read file
$contents = @file_get_contents($requested);
if ($contents === false) {
    http_response_code(404);
    echo "File not found.";
    exit;
}

// Build parent directory link identical to index.php style
$parentDirRaw = dirname(str_replace($docroot, '', $requested));
if ($parentDirRaw === '.' || $parentDirRaw === '') {
    $parentDir = '/';
} else {
    $parentDir = '/' . ltrim($parentDirRaw, '/');
}

// safe title
$title = htmlspecialchars(basename($requested));
?>
<!doctype html>
<html lang="en">

<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title><?php echo $title; ?></title>

    <!-- Github markdown CSS (light used as baseline; we override heavily for dark mode) -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/github-markdown-css/5.2.0/github-markdown-light.min.css">

    <!-- Fonts / icons -->
    <link href="https://fonts.googleapis.com/css2?family=Roboto:ital,wght@0,300;0,400;0,700;1,300;1,400&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:opsz,wght,FILL,GRAD@24,400,0,0" />

    <!-- highlight.js dark theme -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.8.0/styles/atom-one-dark.min.css">
    <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.8.0/highlight.min.js"></script>

    <!-- Apply saved theme before first paint -->
    <script>
        (function () {
            var t = localStorage.getItem('theme') || 'dark';
            document.documentElement.dataset.theme = t;
        })();
    </script>

    <style>
        /* ── Dark theme tokens (default) ──────────────────── */
        :root {
            --bg: #0f0f0f;
            --page-bg: #181818;
            --card-bg: #0f0f0f;
            --muted: #9a9a9a;
            --text: #eaeaea;
            --link: #9ad0ff;
            --link-hover: #bfe8ff;
            --code-bg: #0b0b0b;
            --code-border: rgba(255, 255, 255, 0.04);
            --accent: #b388ff;
            --btn-bg: rgba(255, 255, 255, 0.06);
            --btn-fg: #ddd;
            --thead-bg: rgba(255, 255, 255, 0.06);
            --table-border: rgba(255, 255, 255, 0.04);
            --blockquote-border: rgba(255, 255, 255, 0.06);
            --blockquote-bg: rgba(255, 255, 255, 0.02);
        }

        /* ── Light theme tokens ───────────────────────────── */
        [data-theme="light"] {
            --bg: #fff;
            --page-bg: #f0f0f0;
            --card-bg: #fff;
            --muted: #6c757d;
            --text: #212529;
            --link: #0d6efd;
            --link-hover: #0a58ca;
            --code-bg: #f3f4f5;
            --code-border: rgba(0, 0, 0, 0.08);
            --accent: #6f42c1;
            --btn-bg: rgba(0, 0, 0, 0.06);
            --btn-fg: #333;
            --thead-bg: rgba(0, 0, 0, 0.05);
            --table-border: rgba(0, 0, 0, 0.1);
            --blockquote-border: rgba(0, 0, 0, 0.15);
            --blockquote-bg: rgba(0, 0, 0, 0.03);
        }

        html,
        body {
            height: 100%;
            margin: 0;
            background: var(--page-bg);
            color: var(--text);
            font-family: Roboto, system-ui, -apple-system, "Segoe UI", "Helvetica Neue", Arial;
            -webkit-font-smoothing: antialiased;
            -moz-osx-font-smoothing: grayscale;
        }

        /* ── Back link ────────────────────────────────────── */
        .top-link {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            margin: 18px 0 0;
            color: var(--text);
            text-decoration: none;
            font-size: 0.95rem;
        }

        .top-link .material-symbols-outlined {
            color: var(--text);
            font-size: 20px;
            vertical-align: middle;
        }

        .top-link:hover {
            color: var(--muted);
            text-decoration: none;
        }

        /* ── Filename heading ─────────────────────────────── */
        .file-title {
            font-size: 1.3rem;
            font-weight: 400;
            color: var(--text);
            margin: 8px 0 16px;
            padding-bottom: 8px;
            border-bottom: 1px solid rgba(128, 128, 128, 0.15);
        }

        /* ── Page container ───────────────────────────────── */
        .container {
            max-width: 980px;
            margin: 0 auto;
            padding: 20px;
        }

        /* ── Markdown card ────────────────────────────────── */
        .markdown-body {
            background: var(--card-bg);
            padding: 26px;
            border-radius: 10px;
            box-shadow: 0 6px 18px rgba(0, 0, 0, 0.6);
            color: var(--text);
        }

        /* ── Text / links inside markdown ─────────────────── */
        .markdown-body a {
            color: var(--link);
        }

        .markdown-body a:hover {
            color: var(--link-hover);
            text-decoration: underline;
        }

        .markdown-body p,
        .markdown-body li,
        .markdown-body h1,
        .markdown-body h2,
        .markdown-body h3,
        .markdown-body h4,
        .markdown-body h5,
        .markdown-body h6 {
            color: var(--text);
        }

        .markdown-body blockquote {
            border-left: 3px solid var(--blockquote-border);
            background: var(--blockquote-bg);
            padding: 12px 16px;
            color: var(--muted);
        }

        /* ── Code blocks ──────────────────────────────────── */
        pre {
            background: var(--code-bg);
            border: 1px solid var(--code-border);
            padding: 12px;
            border-radius: 6px;
            overflow: auto;
            position: relative;
            margin: 1em 0;
            color: #e6e6e6;
        }

        pre code {
            background: transparent;
            color: inherit;
            font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, "Roboto Mono", monospace;
        }

        .markdown-body pre,
        .markdown-body pre code {
            background: var(--code-bg);
            border: 1px solid var(--code-border);
        }

        .markdown-body code,
        .markdown-body pre {
            background-color: var(--code-bg);
        }

        /* Inline code */
        code:not(pre code) {
            background: rgba(128, 128, 128, 0.12);
            padding: 2px 6px;
            border-radius: 4px;
            font-size: 0.95em;
        }

        /* ── Tables ───────────────────────────────────────── */
        .markdown-body table {
            border-collapse: collapse;
            width: 100%;
        }

        .markdown-body th,
        .markdown-body td {
            border: 1px solid var(--table-border);
            padding: 8px;
            text-align: left;
        }

        .markdown-body thead tr {
            background: var(--thead-bg);
        }

        /* ── Images ───────────────────────────────────────── */
        .markdown-body img {
            max-width: 100%;
            border-radius: 6px;
        }

        /* ── Copy button ──────────────────────────────────── */
        .copy-btn {
            position: absolute;
            right: 8px;
            top: 8px;
            background: var(--btn-bg);
            color: var(--btn-fg);
            border: 0;
            padding: 6px 8px;
            font-size: 12px;
            border-radius: 6px;
            cursor: pointer;
            opacity: 0.95;
            display: inline-flex;
            align-items: center;
            gap: 6px;
        }

        .copy-btn:active {
            transform: translateY(1px);
        }

        .copy-btn .tick {
            display: none;
        }

        .copied .copy-btn {
            background: #2b662b;
            color: #e8ffe8;
        }

        /* ── Theme toggle ─────────────────────────────────── */
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
            font-family: Roboto, sans-serif;
            font-weight: 300;
            transition: background 0.15s;
        }

        .theme-toggle:hover {
            background: rgba(128, 128, 128, 0.25);
        }

        /* ── Small screens ────────────────────────────────── */
        @media (max-width: 600px) {
            .container {
                padding: 12px;
            }

            .markdown-body {
                padding: 16px;
            }

            .copy-btn {
                right: 6px;
                top: 6px;
                padding: 5px 7px;
                font-size: 11px;
            }
        }
    </style>
</head>

<body>
    <div class="container">
        <a class="top-link" href="<?php echo htmlspecialchars($parentDir); ?>">
            <span id="PD" class="material-symbols-outlined">arrow_back</span>
            <span>Parent Directory</span>
        </a>

        <h1 class="file-title"><?php echo $title; ?></h1>

        <article id="content" class="markdown-body">Loading…</article>
    </div>

    <button class="theme-toggle" onclick="toggleTheme()" aria-label="Toggle theme">
        <span class="material-symbols-outlined" id="theme-icon" style="font-size:18px">dark_mode</span>
        <span id="theme-label">Light</span>
    </button>

    <script>
        (function() {
            // ── Theme toggle ──────────────────────────────────
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

            var saved = localStorage.getItem('theme') || 'dark';
            applyTheme(saved, false);

            // ── Markdown rendering ────────────────────────────
            const md = <?php echo json_encode($contents, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE); ?>;

            const target = document.getElementById('content');
            if (!target) {
                console.error('Markdown target element not found.');
                return;
            }

            marked.setOptions({
                gfm: true,
                breaks: false,
                smartLists: true,
                highlight: function(code, lang) {
                    try {
                        return hljs.highlightAuto(code, lang ? [lang] : undefined).value;
                    } catch (e) {
                        try {
                            return hljs.highlightAuto(code).value;
                        } catch (e2) {
                            return code;
                        }
                    }
                }
            });

            try {
                target.innerHTML = marked.parse(md);
            } catch (err) {
                target.textContent = 'Error rendering markdown.';
                console.error(err);
                return;
            }

            document.querySelectorAll('pre code').forEach((el) => {
                try { hljs.highlightElement(el); } catch (e) {}
            });

            // ── Copy buttons ──────────────────────────────────
            function makeCopyButtons() {
                Array.from(document.querySelectorAll('pre')).forEach(pre => {
                    if (pre.dataset.copyButtonAdded) return;
                    pre.dataset.copyButtonAdded = '1';

                    const btn = document.createElement('button');
                    btn.className = 'copy-btn';
                    btn.type = 'button';
                    btn.innerHTML = '<span class="label">Copy</span><span class="tick">✓</span>';

                    btn.addEventListener('click', async (ev) => {
                        const codeEl = pre.querySelector('code');
                        if (!codeEl) return;
                        const text = codeEl.innerText || codeEl.textContent || '';
                        try {
                            await navigator.clipboard.writeText(text);
                            pre.classList.add('copied');
                            btn.querySelector('.label').textContent = 'Copied';
                            btn.querySelector('.tick').style.display = 'inline';
                            setTimeout(() => {
                                pre.classList.remove('copied');
                                btn.querySelector('.label').textContent = 'Copy';
                                btn.querySelector('.tick').style.display = 'none';
                            }, 1500);
                        } catch (e) {
                            try {
                                const r = document.createRange();
                                r.selectNodeContents(codeEl);
                                const sel = window.getSelection();
                                sel.removeAllRanges();
                                sel.addRange(r);
                                document.execCommand('copy');
                                sel.removeAllRanges();
                                pre.classList.add('copied');
                                btn.querySelector('.label').textContent = 'Copied';
                                setTimeout(() => {
                                    pre.classList.remove('copied');
                                    btn.querySelector('.label').textContent = 'Copy';
                                }, 1200);
                            } catch (e2) {
                                console.error('Copy failed', e2);
                            }
                        }
                    });

                    pre.style.position = 'relative';
                    pre.appendChild(btn);
                });
            }

            makeCopyButtons();

            const mo = new MutationObserver((mutations) => {
                let added = false;
                for (const m of mutations) {
                    if (m.addedNodes && m.addedNodes.length) { added = true; break; }
                }
                if (added) makeCopyButtons();
            });
            mo.observe(target, { childList: true, subtree: true });
        })();
    </script>
</body>

</html>
