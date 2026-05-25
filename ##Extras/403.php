<?php
// Real 403 status, not a 200 with a 403-looking body.
http_response_code(403);
?>
<!DOCTYPE html>
<html lang="en" data-theme="overpinku">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>403 — Off-limits ♡</title>
<link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Cpath fill='%23e91e8c' d='M16 28C16 28 3 18 3 10.5C3 6.5 6.5 3.5 10.5 3.5C13 3.5 15.2 5 16 7C16.8 5 19 3.5 21.5 3.5C25.5 3.5 29 6.5 29 10.5C29 18 16 28 16 28Z'/%3E%3Ccircle cx='11' cy='10' r='2' fill='white' opacity='0.55'/%3E%3C/svg%3E">
<meta name="robots" content="noindex">
<style>
:root {
    --bg:      #fff0f5;
    --surface: #fff8fa;
    --text:    #5c1a3a;
    --muted:   #b05070;
    --accent:  #e91e8c;
    --accent2: #ff69b4;
    --btn-pink:#e91e8c;
    --btn-pink-hover:#c2185b;
}

* { box-sizing: border-box; }

html, body {
    margin: 0;
    padding: 0;
    min-height: 100vh;
    background: var(--bg);
    background-image: radial-gradient(circle, rgba(255,105,180,.22) 1.5px, transparent 1.5px);
    background-size: 22px 22px;
    color: var(--text);
    font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
    font-weight: 300;
    overflow-x: hidden;
    /* Heart cursor — matches the rest of the OverPinku theme. */
    cursor: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='22' height='24' viewBox='0 0 22 24'%3E%3Cpath fill='%23e91e8c' stroke='white' stroke-width='1.2' stroke-linejoin='round' d='M1 1 L1 16 L5 12.5 L8 18.5 L10 17.5 L7 11.5 L12 11.5 Z'/%3E%3Cpath fill='%23ff69b4' stroke='white' stroke-width='0.7' stroke-linejoin='round' d='M15 15 C15 15 12.5 12.5 12.5 11 C12.5 10.1 13.2 9.5 14 9.5 C14.5 9.5 14.8 9.8 15 10.3 C15.2 9.8 15.5 9.5 16 9.5 C16.8 9.5 17.5 10.1 17.5 11 C17.5 12.5 15 15 15 15 Z'/%3E%3C/svg%3E") 1 1, auto;
}
body, body * { cursor: inherit; }

.wrap {
    position: relative;
    z-index: 1;
    min-height: 100vh;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 40px 20px;
    text-align: center;
}

.code {
    font-size: clamp(7rem, 22vw, 13rem);
    font-weight: 700;
    line-height: 1;
    margin: 0 0 12px;
    background: linear-gradient(90deg, #e91e8c, #ff69b4, #ff1493, #ff85c2, #e91e8c);
    background-size: 200% auto;
    -webkit-background-clip: text;
    background-clip: text;
    color: transparent;
    animation: shimmer 4s linear infinite;
    user-select: none;
    position: relative;
}

/* Tiny padlock charm tucked under the 403 — subtle "locked" cue without
   leaning on Material Symbols or any external icon font. */
.code::after {
    content: "🔒";
    position: absolute;
    top: -12px;
    right: -8px;
    font-size: 0.22em;
    -webkit-text-fill-color: initial;
    color: #e91e8c;
    filter: drop-shadow(0 2px 4px rgba(233, 30, 140, 0.35));
    animation: lock-wiggle 3.2s ease-in-out infinite;
    transform-origin: center;
}

@keyframes lock-wiggle {
    0%, 80%, 100% { transform: rotate(-4deg); }
    85%           { transform: rotate(8deg); }
    90%           { transform: rotate(-6deg); }
    95%           { transform: rotate(4deg); }
}

@keyframes shimmer {
    0%   { background-position: 0% center; }
    100% { background-position: 200% center; }
}

.title {
    font-size: clamp(1.2rem, 3vw, 1.6rem);
    font-weight: 400;
    margin: 0 0 8px;
    color: var(--accent);
}

.subtitle {
    font-size: 1rem;
    color: var(--muted);
    max-width: 38ch;
    margin: 0 0 32px;
    line-height: 1.5;
}

.home-btn {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 11px 22px;
    border-radius: 999px;
    background: var(--btn-pink);
    color: #fff;
    text-decoration: none;
    font-size: 0.95rem;
    font-weight: 400;
    box-shadow: 0 6px 18px rgba(233, 30, 140, 0.25);
    transition: background 0.15s, transform 0.15s, box-shadow 0.15s;
}
.home-btn:hover {
    background: var(--btn-pink-hover);
    transform: translateY(-1px);
    box-shadow: 0 8px 22px rgba(233, 30, 140, 0.35);
}
.home-btn .heart {
    animation: heartbeat 1.4s ease-in-out infinite;
    display: inline-block;
}

@keyframes heartbeat {
    0%, 100% { transform: scale(1); }
    50%      { transform: scale(1.18); }
}

::selection { background: rgba(255,20,147,.25); color: #5c1a3a; }
::-webkit-scrollbar { width: 8px; }
::-webkit-scrollbar-track { background: #ffe4ee; }
::-webkit-scrollbar-thumb { background: #ff69b4; border-radius: 10px; }
::-webkit-scrollbar-thumb:hover { background: #e91e8c; }

/* Sakura petals — same pattern as 404.php, kept inlined so each error
   page is independently servable even if the other breaks. */
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
</style>
</head>
<body>
<div class="wrap">
    <div class="code">403</div>
    <div class="title">This one's locked down ♡</div>
    <p class="subtitle">
        You found a file that's not meant for the public — config, lock files,
        backups, that kind of thing. Nothing personal, just keeping the
        sensitive stuff sensitive.
    </p>
    <a href="/" class="home-btn">
        <span class="heart">♥</span>
        <span>Back to the file browser</span>
    </a>
</div>

<script>
(function () {
    // ── Sakura petals drifting down ───────────────────────────────────
    var chars  = ['✿', '❀', '✾', '❁'];
    var colors = ['#ffb3d9', '#ff85c2', '#ff69b4', '#ffcce6', '#ffd6e0'];
    for (var i = 0; i < 18; i++) {
        var el  = document.createElement('span');
        el.className = 'sakura-petal';
        el.textContent = chars[Math.floor(Math.random() * chars.length)];
        var sz  = 10 + Math.random() * 10;
        var dur = 7 + Math.random() * 8;
        el.style.cssText =
            'left:' + (Math.random() * 100) + 'vw;' +
            'font-size:' + sz + 'px;' +
            'color:' + colors[Math.floor(Math.random() * colors.length)] + ';' +
            'opacity:' + (0.35 + Math.random() * 0.4) + ';' +
            'animation-duration:' + dur + 's;' +
            'animation-delay:' + (Math.random() * -dur) + 's;';
        document.body.appendChild(el);
    }

    // ── Click anywhere → burst of hearts ──────────────────────────────
    var heartChars  = ['♥', '♥', '♥', '♡', '❤'];
    var heartColors = ['#ff69b4', '#ff1493', '#e91e8c', '#ff85c2', '#c2185b', '#ffb3d9'];
    document.addEventListener('click', function (e) {
        var n = 7 + Math.floor(Math.random() * 5);
        for (var i = 0; i < n; i++) (function () {
            var el = document.createElement('span');
            el.textContent = heartChars[Math.floor(Math.random() * heartChars.length)];
            var sz  = 20 + Math.random() * 14;
            var a   = (Math.random() - 0.5) * Math.PI * 1.5;
            var d   = 60 + Math.random() * 90;
            var dx  = Math.sin(a) * d, dy = -(55 + Math.random() * 85);
            var dur = 0.55 + Math.random() * 0.4;
            el.style.cssText =
                'position:fixed;left:' + e.clientX + 'px;top:' + e.clientY + 'px;' +
                'font-size:' + sz + 'px;color:' + heartColors[Math.floor(Math.random() * heartColors.length)] + ';' +
                'pointer-events:none;user-select:none;z-index:99999;' +
                'transform:translate(-50%,-50%) scale(1.3);opacity:1;transition:none';
            document.body.appendChild(el);
            requestAnimationFrame(function () {
                requestAnimationFrame(function () {
                    el.style.transition = 'transform ' + dur + 's ease-out, opacity ' + dur + 's ease-in';
                    el.style.transform  = 'translate(calc(-50% + ' + dx + 'px), calc(-50% + ' + dy + 'px)) scale(0.2)';
                    el.style.opacity    = '0';
                });
            });
            setTimeout(function () { if (el.parentNode) el.parentNode.removeChild(el); }, (dur + 0.2) * 1000);
        })();

        // Delay same-origin nav so the burst stays visible.
        var lnk = e.target.closest('a[href]');
        if (!lnk || lnk.target || e.ctrlKey || e.metaKey || e.shiftKey || lnk.download) return;
        try { if (new URL(lnk.href).origin !== window.location.origin) return; } catch (_) { return; }
        e.preventDefault();
        setTimeout(function () { window.location.href = lnk.href; }, 350);
    });
})();
</script>
</body>
</html>
