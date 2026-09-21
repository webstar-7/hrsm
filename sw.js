/* PeopleDesk service worker
   - lets the app be installed and start even when the internet is slow or down
   - the app page is fetched from the network first, so updates arrive straight away
   - it NEVER stores anything from your database, sign-in, storage or functions */
const VERSION = 'peopledesk-v1';
const SHELL = ['./', 'index.html', 'manifest.webmanifest', 'icons/icon-192.png', 'icons/icon-512.png'];
const LIBS = /(^|\.)(cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com|fonts\.googleapis\.com|fonts\.gstatic\.com)$/;
const DATA = /\.supabase\.(co|in)$/;

self.addEventListener('install', e => e.waitUntil(caches.open(VERSION).then(c => c.addAll(SHELL)).then(() => self.skipWaiting())));
self.addEventListener('activate', e => e.waitUntil(
  caches.keys().then(keys => Promise.all(keys.filter(k => k.startsWith('peopledesk-') && k !== VERSION).map(k => caches.delete(k)))).then(() => self.clients.claim())));

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (DATA.test(url.hostname)) return;                       // database, sign-in, files, functions: always live
  if (url.origin === self.location.origin) {
    if (req.mode === 'navigate') {                            // the app itself: network first, cached copy if offline
      e.respondWith(fetch(req).then(res => { if (res.ok) { const copy = res.clone(); caches.open(VERSION).then(c => c.put('index.html', copy)); } return res; })
        .catch(() => caches.match('index.html')));
    } else {                                                  // icons, manifest: cache first
      e.respondWith(caches.match(req).then(hit => hit || fetch(req).then(res => { if (res.ok) { const copy = res.clone(); caches.open(VERSION).then(c => c.put(req, copy)); } return res; })));
    }
    return;
  }
  if (LIBS.test(url.hostname)) {                              // libraries and fonts: keep a copy so the app can start offline
    e.respondWith(caches.match(req).then(hit => {
      const net = fetch(req).then(res => { caches.open(VERSION).then(c => c.put(req, res.clone())); return res; }).catch(() => hit);
      return hit || net;
    }));
  }
});
