// SSvid Service Worker — Cache-first for assets, network-first for pages
var CACHE_NAME = 'ssvid-v1.4.1';
var STATIC_ASSETS = [
  '/fonts/fonts.css',
  '/fonts/inter-400-latin.woff2',
  '/fonts/inter-500-latin.woff2',
  '/fonts/inter-600-latin.woff2',
  '/fonts/plus-jakarta-sans-700-latin.woff2',
  '/favicon.svg',
  '/logo.png'
];

self.addEventListener('install', function(e) {
  e.waitUntil(
    caches.open(CACHE_NAME).then(function(cache) {
      return cache.addAll(STATIC_ASSETS);
    })
  );
  self.skipWaiting();
});

self.addEventListener('activate', function(e) {
  e.waitUntil(
    caches.keys().then(function(names) {
      return Promise.all(
        names.filter(function(n) { return n !== CACHE_NAME; })
          .map(function(n) { return caches.delete(n); })
      );
    })
  );
  self.clients.claim();
});

self.addEventListener('fetch', function(e) {
  var url = new URL(e.request.url);

  // Skip non-GET requests and external origins
  if (e.request.method !== 'GET' || url.origin !== self.location.origin) return;

  // Cache-first for static assets (fonts, images, CSS, JS)
  if (/\.(woff2|css|js|png|svg|avif|webp|ico)$/.test(url.pathname) || url.pathname.startsWith('/fonts/')) {
    e.respondWith(
      caches.match(e.request).then(function(cached) {
        if (cached) return cached;
        return fetch(e.request).then(function(response) {
          if (response.ok) {
            var clone = response.clone();
            caches.open(CACHE_NAME).then(function(cache) { cache.put(e.request, clone); });
          }
          return response;
        });
      })
    );
    return;
  }

  // Network-first for HTML pages (always get latest, cache as fallback)
  if (e.request.headers.get('accept') && e.request.headers.get('accept').indexOf('text/html') !== -1) {
    e.respondWith(
      fetch(e.request).then(function(response) {
        if (response.ok) {
          var clone = response.clone();
          caches.open(CACHE_NAME).then(function(cache) { cache.put(e.request, clone); });
        }
        return response;
      }).catch(function() {
        return caches.match(e.request);
      })
    );
    return;
  }
});
