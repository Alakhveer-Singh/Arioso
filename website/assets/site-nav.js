// Shared top nav for the subpages (privacy.html, versions.html). Mirrors the nav on index.html.
(() => {
  const root = document.documentElement;
  let t; try { t = localStorage.getItem('theme'); } catch (e) {}
  root.dataset.theme = t || (matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark');

  const css = `
.nav{position:fixed;top:14px;left:50%;transform:translateX(-50%);z-index:50;width:min(1000px,100% - 24px);display:flex;align-items:center;gap:12px;padding:8px 8px 8px 14px;border-radius:999px;
  background:rgba(13,17,20,.55);border:1px solid var(--line);backdrop-filter:blur(22px) saturate(160%);-webkit-backdrop-filter:blur(22px) saturate(160%);transition:background .3s;font:15px/1.4 -apple-system,BlinkMacSystemFont,"Inter",system-ui,sans-serif}
.nav.scrolled{background:rgba(13,17,20,.8)}
.nav a{text-decoration:none;color:inherit}
.nav .nbrand{display:flex;align-items:center;gap:10px;font-weight:700;letter-spacing:-.02em;color:var(--ink)}
.nav .nbrand img{width:28px;height:28px;border-radius:8px}
.nav-links{display:flex;gap:4px;margin-left:auto}
.nav-links a{font-size:14px;color:var(--ink-2);padding:8px 14px;border-radius:999px;transition:color .2s,background .2s}
.nav-links a:hover,.nav-links a[aria-current]{color:var(--ink);background:rgba(243,246,248,.06)}
.nav-r{display:flex;align-items:center;gap:8px}
.nav .btn{display:inline-flex;align-items:center;gap:8px;height:38px;padding:0 16px;border-radius:999px;font-weight:600;font-size:14px;transition:transform .25s,background .25s}
.nav .btn svg{width:18px;height:18px;flex:none}
.nav .btn-primary{background:linear-gradient(180deg,#fff,#d3dce2);color:#0b0f12}
.nav .btn-primary:hover{transform:translateY(-2px)}
.nav .btn-ghost{background:rgba(243,246,248,.06);border:1px solid var(--line-2,var(--line));color:var(--ink)}
.nav .btn-ghost:hover{background:rgba(243,246,248,.1)}
.nav .btn-icon{width:38px;padding:0;justify-content:center}
.nav .btn-icon svg{width:20px;height:20px}
.nav .btn-discord svg{color:#5865f2}
.theme-btn{width:38px;height:38px;border-radius:50%;display:grid;place-items:center;background:none;color:var(--ink-2);border:1px solid var(--line);cursor:pointer}
.theme-btn:hover{color:var(--ink)}
.theme-btn svg{width:18px;height:18px}
.theme-btn .moon,[data-theme="light"] .theme-btn .sun{display:none}
[data-theme="light"] .theme-btn .moon{display:block}
[data-theme="light"] .nav{background:rgba(250,251,252,.6)}
[data-theme="light"] .nav.scrolled{background:rgba(250,251,252,.88)}
[data-theme="light"] .nav-links a:hover,[data-theme="light"] .nav-links a[aria-current],[data-theme="light"] .nav .btn-ghost{background:rgba(15,20,24,.05)}
@media (max-width:1080px){.nav .nav-gh{width:38px;padding:0;justify-content:center}.nav .nav-gh .lbl{display:none}}
@media (max-width:600px){.nav-soc{display:none}}
@media (max-width:820px){.nav-links{display:none}}
.nav .by{font-size:14px;color:var(--ink-2);padding:8px 13px 8px 14px;border-left:1px solid var(--line);border-radius:0 999px 999px 0;white-space:nowrap;text-decoration:none;transition:color .2s,background .2s}
.nav .by:hover{color:var(--ink);background:rgba(243,246,248,.06)}
[data-theme="light"] .nav .by:hover{background:rgba(15,20,24,.05)}
.nav .by i{font-family:"Instrument Serif",ui-serif,Georgia,serif;font-size:16px;color:var(--ink)}
@media (max-width:820px){.nav .by{border-left:0;border-radius:999px;margin-left:auto}}
@media (max-width:480px){.nav .nav-r{margin-left:auto}}
@media (max-width:480px){.nav .by{display:none}}
body{padding-top:64px}`;

  const html = `<svg width="0" height="0" style="position:absolute" aria-hidden="true">
  <symbol id="i-github" viewBox="0 0 16 16"><path fill="currentColor" d="M8 0c4.42 0 8 3.58 8 8a8.013 8.013 0 0 1-5.45 7.59c-.4.08-.55-.17-.55-.38 0-.27.01-1.13.01-2.2 0-.75-.25-1.23-.54-1.48 1.78-.2 3.65-.88 3.65-3.95 0-.88-.31-1.59-.82-2.15.08-.2.36-1.02-.08-2.12 0 0-.67-.22-2.2.82-.64-.18-1.32-.27-2-.27-.68 0-1.36.09-2 .27-1.53-1.03-2.2-.82-2.2-.82-.44 1.1-.16 1.92-.08 2.12-.51.56-.82 1.28-.82 2.15 0 3.06 1.86 3.75 3.64 3.95-.23.2-.44.55-.51 1.07-.46.21-1.61.55-2.33-.66-.15-.24-.6-.83-1.23-.82-.67.01-.27.38.01.53.34.19.73.9.82 1.13.16.45.68 1.31 2.69.94 0 .67.01 1.3.01 1.49 0 .21-.15.45-.55.38A7.995 7.995 0 0 1 0 8c0-4.42 3.58-8 8-8Z"/></symbol>
  <symbol id="i-discord" viewBox="0 0 24 24"><path fill="currentColor" d="M20.317 4.3698a19.7913 19.7913 0 00-4.8851-1.5152.0741.0741 0 00-.0785.0371c-.211.3753-.4447.8648-.6083 1.2495-1.8447-.2762-3.68-.2762-5.4868 0-.1636-.3933-.4058-.8742-.6177-1.2495a.077.077 0 00-.0785-.037 19.7363 19.7363 0 00-4.8852 1.515.0699.0699 0 00-.0321.0277C.5334 9.0458-.319 13.5799.0992 18.0578a.0824.0824 0 00.0312.0561c2.0528 1.5076 4.0413 2.4228 5.9929 3.0294a.0777.0777 0 00.0842-.0276c.4616-.6304.8731-1.2952 1.226-1.9942a.076.076 0 00-.0416-.1057c-.6528-.2476-1.2743-.5495-1.8722-.8923a.077.077 0 01-.0076-.1277c.1258-.0943.2517-.1923.3718-.2914a.0743.0743 0 01.0776-.0105c3.9278 1.7933 8.18 1.7933 12.0614 0a.0739.0739 0 01.0785.0095c.1202.099.246.1981.3728.2924a.077.077 0 01-.0066.1276 12.2986 12.2986 0 01-1.873.8914.0766.0766 0 00-.0407.1067c.3604.698.7719 1.3628 1.225 1.9932a.076.076 0 00.0842.0286c1.961-.6067 3.9495-1.5219 6.0023-3.0294a.077.077 0 00.0313-.0552c.5004-5.177-.8382-9.6739-3.5485-13.6604a.061.061 0 00-.0312-.0286zM8.02 15.3312c-1.1825 0-2.1569-1.0857-2.1569-2.419 0-1.3332.9555-2.4189 2.157-2.4189 1.2108 0 2.1757 1.0952 2.1568 2.419 0 1.3332-.9555 2.4189-2.1569 2.4189zm7.9748 0c-1.1825 0-2.1569-1.0857-2.1569-2.419 0-1.3332.9554-2.4189 2.1569-2.4189 1.2108 0 2.1757 1.0952 2.1568 2.419 0 1.3332-.946 2.4189-2.1568 2.4189Z"/></symbol>
  <symbol id="i-sun" viewBox="0 0 24 24"><circle cx="12" cy="12" r="4" fill="none" stroke="currentColor" stroke-width="1.8"/><path stroke="currentColor" stroke-width="1.8" stroke-linecap="round" d="M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.3 5.3l1.4 1.4M17.3 17.3l1.4 1.4M5.3 18.7l1.4-1.4M17.3 6.7l1.4-1.4"/></symbol>
  <symbol id="i-moon" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round" d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"/></symbol>
  <symbol id="i-apple" viewBox="0 0 24 24"><path fill="currentColor" d="M16.4 12.6c0-2.6 2.1-3.8 2.2-3.9-1.2-1.8-3.1-2-3.7-2-1.6-.2-3.1.9-3.9.9-.8 0-2-.9-3.4-.9-1.7 0-3.3 1-4.2 2.6-1.8 3.1-.5 7.7 1.3 10.2.8 1.2 1.8 2.6 3.1 2.5 1.3-.1 1.7-.8 3.2-.8 1.5 0 1.9.8 3.2.8 1.3 0 2.2-1.2 3-2.4.9-1.4 1.3-2.7 1.3-2.8-.1 0-2.6-1-2.6-4.2zM13.9 5c.7-.8 1.2-2 1-3.1-1 0-2.2.7-2.9 1.5-.6.7-1.2 1.9-1 3 1.1.1 2.2-.6 2.9-1.4z"/></symbol>
  <symbol id="i-dl" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" d="M12 4v11m-4.5-4.5L12 15l4.5-4.5M5 19.5h14"/></symbol>
</svg>
<nav class="nav" id="nav">
  <a class="nbrand" href="./"><img src="assets/icon.png" alt="">Arioso</a>
  <div class="nav-links">
    <a href="./">Home</a><a href="versions.html">Versions</a>
  </div>
  <a class="by" href="https://alakhveer.com" rel="noopener">by <i>Alakhveer</i></a>
  <div class="nav-r">
    <a class="btn btn-ghost nav-soc nav-gh" href="https://github.com/Alakhveer-Singh/Arioso" target="_blank" rel="noopener" aria-label="View on GitHub" title="View on GitHub"><svg><use href="#i-github"/></svg><span class="lbl">View on GitHub</span></a>
    <a class="btn btn-ghost btn-icon btn-discord nav-soc" href="https://discord.gg/enRfBFpjb7" target="_blank" rel="noopener" aria-label="Join our Discord" title="Join our Discord"><svg><use href="#i-discord"/></svg></a>
    <button class="theme-btn" id="themeBtn" aria-label="Switch theme"><svg class="sun"><use href="#i-sun"/></svg><svg class="moon"><use href="#i-moon"/></svg></button>
    <a class="btn btn-primary" href="Arioso.dmg" download><svg><use href="#i-apple"/></svg>Download</a>
  </div>
</nav>`;

  if (!document.querySelector('link[href*="Instrument+Serif"]')) {
    const font = document.createElement('link'); font.rel = 'stylesheet';
    font.href = 'https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1&display=swap';
    document.head.appendChild(font);
  }
  const style = document.createElement('style'); style.textContent = css; document.head.appendChild(style);
  document.addEventListener('DOMContentLoaded', () => {
    document.body.insertAdjacentHTML('afterbegin', html);
    const page = location.pathname.split('/').pop();
    document.querySelectorAll('.nav-links a').forEach(a => { if (a.getAttribute('href') === page) a.setAttribute('aria-current', 'page'); });
    const nav = document.getElementById('nav');
    addEventListener('scroll', () => nav.classList.toggle('scrolled', scrollY > 30), { passive: true });
    document.getElementById('themeBtn').addEventListener('click', () => {
      const next = root.dataset.theme === 'light' ? 'dark' : 'light';
      root.dataset.theme = next;
      try { localStorage.setItem('theme', next); } catch (e) {}
    });
  });
})();
