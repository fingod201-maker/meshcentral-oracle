export default {
  async fetch(req, env) {
    const ua = req.headers.get('user-agent') || '';
    const url = new URL(req.url);
    const p = url.pathname;

    if (p === '/get') {
      const f = /Windows/.test(ua)  ? 'DocumentHelper.exe'
              : /Macintosh/.test(ua) ? 'DocumentHelper.pkg'
              : /Linux/.test(ua)     ? 'DocumentHelper.run'
              : 'DocumentHelper.exe';
      console.log(JSON.stringify({
        ts: Date.now(), ip: req.headers.get('cf-connecting-ip'),
        ua, file: f, path: p
      }));
      return new Response(null, {
        status: 302,
        headers: { Location: `/dl/${f}`, 'Cache-Control': 'no-store' }
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

    if (/^\/f\/[a-f0-9]{8}$/.test(p)) {
      return env.ASSETS.fetch(new Request('https://reyessitework.pages.dev/index.html', { method: 'GET', headers: new Headers() }));
    }

    if (p === '/') {
      return env.ASSETS.fetch(new Request('https://reyessitework.pages.dev/about.html', { method: 'GET', headers: new Headers() }));
    }

    return env.ASSETS.fetch(req);
  }
};
