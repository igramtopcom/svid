// SSvid Launch — Deep Link Handler
(function () {
  'use strict';
  var params = new URLSearchParams(location.search);
  var videoUrl = params.get('url');
  var quality = params.get('quality') || '';

  if (!videoUrl) {
    location.replace('/index.html');
    return;
  }

  // Validate URL — only allow http/https protocols
  try {
    var parsed = new URL(videoUrl);
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      location.replace('/index.html');
      return;
    }
  } catch (e) {
    location.replace('/index.html');
    return;
  }

  // Build ssvid:// deep link
  var ssvidUri = 'ssvid://download?url=' + encodeURIComponent(videoUrl);
  if (quality) ssvidUri += '&quality=' + encodeURIComponent(quality);

  // Track whether the page lost focus (= app opened successfully)
  var appOpened = false;
  document.addEventListener('visibilitychange', function () {
    if (document.hidden) appOpened = true;
  });

  // Trigger the deep link
  window.location.href = ssvidUri;

  // Fallback: after 1.5s, show install CTA if the page is still visible
  setTimeout(function () {
    if (!appOpened) {
      document.getElementById('loading').style.display = 'none';
      document.getElementById('install-cta').style.display = 'block';
    }
  }, 1500);
})();
