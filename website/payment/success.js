// SSvid Payment Success — License Key Retrieval
(function() {
  'use strict';
  var API = 'https://api.ssvid.app/api/v1/premium/stripe/web-verify';
  var params = new URLSearchParams(window.location.search);
  var sessionId = params.get('session_id');
  var refEl = document.getElementById('session-ref');
  var statusMsg = document.getElementById('status-msg');
  var licenseBox = document.getElementById('license-box');
  var licenseKeyEl = document.getElementById('license-key');
  var openAppBtn = document.getElementById('open-app-btn');
  var hintMsg = document.getElementById('hint-msg');
  var copyBtn = document.getElementById('copy-key-btn');

  if (sessionId && refEl) {
    refEl.textContent = 'Reference: ' + sessionId;
  }

  if (copyBtn) {
    copyBtn.addEventListener('click', function() {
      var key = licenseKeyEl.textContent;
      if (navigator.clipboard) {
        navigator.clipboard.writeText(key).then(function() {
          copyBtn.textContent = 'Copied!';
          setTimeout(function() { copyBtn.textContent = 'Copy Key'; }, 2000);
        });
      }
    });
  }

  function showLicense(key) {
    statusMsg.textContent = 'Thank you! Your license key is ready.';
    licenseBox.style.display = 'block';
    licenseKeyEl.textContent = key;
    openAppBtn.href = 'ssvid://activate?key=' + encodeURIComponent(key);
    openAppBtn.style.display = '';
    hintMsg.textContent = 'Open SSvid and enter this key, or click the button above to activate automatically.';
  }

  function showPending() {
    statusMsg.textContent = 'Payment received! Your license is being created...';
    hintMsg.textContent = 'This usually takes a few seconds. The page will update automatically.';
  }

  function showError() {
    statusMsg.textContent = 'Thank you for your payment!';
    hintMsg.textContent = 'Your license key will be delivered shortly. If you don\'t see it within a few minutes, please contact support.';
  }

  if (!sessionId) {
    statusMsg.textContent = 'Thank you for your purchase!';
    hintMsg.textContent = 'If you just completed a payment, please check your email or return to the checkout page. If you need help, contact support@ssvid.app.';
    return;
  }

  var attempts = 0;
  var maxAttempts = 12;

  function poll() {
    var ctrl = new AbortController();
    var tid = setTimeout(function() { ctrl.abort(); }, 8000);
    fetch(API + '?session_id=' + encodeURIComponent(sessionId), { signal: ctrl.signal })
      .then(function(r) { clearTimeout(tid); if (!r.ok) throw new Error(r.status); return r.json(); })
      .then(function(data) {
        if (data.success && data.data) {
          var key = data.data.licenseKey;
          if (key && /^SSVID-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$/.test(key)) {
            showLicense(key);
            return;
          }
          if (data.data.status === 'completed') {
            showPending();
          }
        }
        attempts++;
        if (attempts < maxAttempts) {
          setTimeout(poll, 3000);
        } else {
          showError();
        }
      })
      .catch(function() {
        attempts++;
        if (attempts < maxAttempts) {
          setTimeout(poll, 3000);
        } else {
          showError();
        }
      });
  }

  poll();
})();
