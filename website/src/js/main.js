// SSvid Landing Page — script.js
// Theme toggle, billing toggle, navbar scroll, mobile menu, platform detection, scroll reveal

(function () {
  'use strict';

  // --- Theme Toggle ---
  var themeToggle = document.getElementById('theme-toggle');
  var html = document.documentElement;

  function getPreferredTheme() {
    var stored = localStorage.getItem('ssvid-theme');
    if (stored) return stored;
    return 'dark';
  }

  function setTheme(theme) {
    html.setAttribute('data-theme', theme);
    localStorage.setItem('ssvid-theme', theme);
  }

  setTheme(getPreferredTheme());

  if (themeToggle) {
    themeToggle.addEventListener('click', function () {
      var current = html.getAttribute('data-theme');
      setTheme(current === 'light' ? 'dark' : 'light');
    });
  }

  // --- Navbar Scroll Effect ---
  var navbar = document.getElementById('navbar');

  if (navbar) {
    window.addEventListener('scroll', function () {
      if (window.scrollY > 10) {
        navbar.classList.add('scrolled');
      } else {
        navbar.classList.remove('scrolled');
      }
    }, { passive: true });
  }

  // --- Mobile Menu ---
  var menuBtn = document.getElementById('mobile-menu-btn');
  var navLinks = document.getElementById('nav-links');

  if (menuBtn && navLinks) {
    menuBtn.addEventListener('click', function () {
      navLinks.classList.toggle('open');
      menuBtn.classList.toggle('active');
      var expanded = navLinks.classList.contains('open');
      menuBtn.setAttribute('aria-expanded', expanded);
    });

    navLinks.querySelectorAll('a').forEach(function (link) {
      link.addEventListener('click', function () {
        navLinks.classList.remove('open');
        menuBtn.classList.remove('active');
        menuBtn.setAttribute('aria-expanded', 'false');
      });
    });

    // Close mobile menu on click outside
    document.addEventListener('click', function (e) {
      if (navLinks.classList.contains('open') &&
          !menuBtn.contains(e.target) &&
          !navLinks.contains(e.target)) {
        navLinks.classList.remove('open');
        menuBtn.classList.remove('active');
        menuBtn.setAttribute('aria-expanded', 'false');
      }
    });

    // Close mobile menu on Escape key
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && navLinks.classList.contains('open')) {
        navLinks.classList.remove('open');
        menuBtn.classList.remove('active');
        menuBtn.setAttribute('aria-expanded', 'false');
        menuBtn.focus();
      }
    });
  }

  // --- Billing Toggle ---
  var billingToggle = document.getElementById('billing-toggle');
  var billingLabels = document.querySelectorAll('.billing-label');
  var priceValues = document.querySelectorAll('.price-value[data-monthly]');
  var billedYearly = document.querySelectorAll('.price-billed-yearly');
  var priceDevices = document.querySelectorAll('.price-devices[data-monthly]');
  var isYearly = false;

  if (billingToggle && billingLabels.length) {
    billingLabels[0].classList.add('active');

    billingToggle.addEventListener('click', function () {
      isYearly = !isYearly;
      billingToggle.classList.toggle('active', isYearly);
      billingToggle.setAttribute('aria-pressed', isYearly);

      billingLabels.forEach(function (label) {
        var interval = label.getAttribute('data-interval');
        label.classList.toggle('active', (interval === 'yearly') === isYearly);
      });

      priceValues.forEach(function (el) {
        el.style.opacity = '0';
        setTimeout(function () {
          el.textContent = isYearly ? el.dataset.yearly : el.dataset.monthly;
          el.style.opacity = '1';
        }, 150);
      });

      billedYearly.forEach(function (el) {
        el.style.display = isYearly ? 'block' : 'none';
      });

      priceDevices.forEach(function (el) {
        el.style.opacity = '0';
        setTimeout(function () {
          el.textContent = isYearly ? el.dataset.yearly : el.dataset.monthly;
          el.style.opacity = '1';
        }, 150);
      });
    });
  }

  // --- Platform Detection (modern API + fallback) ---
  function detectPlatform() {
    var ua = navigator.userAgent || '';
    
    // Detect mobile platforms first (iOS, Android)
    if (/iPhone|iPad|iPod/i.test(ua)) return 'ios';
    if (/Android/i.test(ua)) return 'android';
    
    // ChromeOS can use Android APK or Linux AppImage
    if (/CrOS/i.test(ua)) return 'chromeos';

    var uaData = navigator.userAgentData;
    if (uaData && uaData.platform) {
      var p = uaData.platform.toLowerCase();
      if (p === 'macos') return 'mac';
      if (p === 'windows') return 'win';
      if (p === 'linux') return 'linux';
    }
    var plat = navigator.platform || '';
    if (plat.indexOf('Win') !== -1) return 'win';
    if (plat.indexOf('Linux') !== -1 || ua.indexOf('Linux') !== -1) return 'linux';
    return 'mac';
  }

  var downloadBtn = document.getElementById('download-btn');
  var downloadLabel = document.getElementById('download-label');
  var downloadMeta = document.getElementById('download-meta');
  var freeDownloadBtn = document.getElementById('free-download-btn');
  var freeDownloadLabel = document.getElementById('free-download-label');
  var pricingDownloadBtn = document.getElementById('pricing-download-btn');
  var pricingDownloadLabel = document.getElementById('pricing-download-label');
  var navDownloadBtn = document.getElementById('nav-download-btn');
  var finalDownloadBtn = document.getElementById('final-download-btn');
  var finalDownloadLabel = document.getElementById('final-download-label');
  var platformCtas = document.querySelectorAll('[data-mac][data-win][data-linux]');
  var mobileCta = document.getElementById('mobile-sticky-cta');
  var mobileCtaBtn = mobileCta ? mobileCta.querySelector('.btn') : null;
  var primaryDownloadSource = downloadBtn || freeDownloadBtn;
  var ctaDataSource = primaryDownloadSource || pricingDownloadBtn || finalDownloadBtn || navDownloadBtn || mobileCtaBtn;
  var altMac = document.getElementById('alt-mac');
  var altWin = document.getElementById('alt-win');
  var altLinux = document.getElementById('alt-linux');
  var altIos = document.getElementById('alt-ios');
  var altAndroid = document.getElementById('alt-android');
  var heroStepDownload = document.getElementById('hero-next-step-download');
  var landingCopy = document.getElementById('landing-copy');
  var detectedOS = detectPlatform();
  var osNames = { mac: 'macOS', win: 'Windows', linux: 'Linux', ios: 'iPhone', android: 'Android', chromeos: 'ChromeOS' };

  // Mobile platform URLs
  var iosAppStoreUrl = 'https://apps.apple.com/app/videogo-media-organizer/id6756922046';
  var androidApkUrl = 'https://github.com/mydinh-studio/ssvid-releases/releases/download/v1.0.8/SSvid-android.apk';

  function readCopy(key, fallback) {
    return landingCopy && landingCopy.dataset[key] ? landingCopy.dataset[key] : fallback;
  }

  function setDownloadTarget(link, href, openNewTab) {
    if (!link) return;
    link.href = href;
    if (openNewTab) {
      link.setAttribute('target', '_blank');
      link.setAttribute('rel', 'noopener noreferrer');
    } else {
      link.removeAttribute('target');
      link.removeAttribute('rel');
    }
  }

  function setAllPlatformTargets(href, openNewTab) {
    platformCtas.forEach(function (link) {
      setDownloadTarget(link, href, openNewTab);
    });
  }

  function getDesktopDownload(platform) {
    return ctaDataSource && ctaDataSource.dataset ? ctaDataSource.dataset[platform] : '';
  }

  function getPrimaryCtaText(fallback) {
    if (downloadLabel) return downloadLabel.textContent;
    if (freeDownloadLabel) return freeDownloadLabel.textContent;
    if (pricingDownloadLabel) return pricingDownloadLabel.textContent;
    if (finalDownloadLabel) return finalDownloadLabel.textContent;
    if (navDownloadBtn) return navDownloadBtn.textContent;
    return fallback;
  }

  function setPrimaryCtaLabel(text) {
    if (downloadLabel) downloadLabel.textContent = text;
    if (freeDownloadLabel) freeDownloadLabel.textContent = text;
    if (pricingDownloadLabel) pricingDownloadLabel.textContent = text;
    if (finalDownloadLabel) finalDownloadLabel.textContent = text;
    if (!downloadLabel && !freeDownloadLabel && !pricingDownloadLabel && !finalDownloadLabel && navDownloadBtn) {
      navDownloadBtn.textContent = text;
    }
  }

  function setHeroPlatforms(html) {
    var heroPlatforms = document.querySelector('.hero-platforms');
    if (heroPlatforms) {
      heroPlatforms.innerHTML = html;
    }
  }

  function buildHeroPlatforms(labelText, links) {
    return '<span class="platform-label">' + labelText + '</span>' + links.map(function (link) {
      var attrs = '';
      if (link.openNewTab) {
        attrs = ' target="_blank" rel="noopener noreferrer"';
      }
      return '<a href="' + link.href + '" class="platform-link"' + attrs + '>' + link.label + '</a>';
    }).join('');
  }

  if (ctaDataSource) {
    var ctaPrefix = readCopy('ctaPrefix', 'Download for');
    var ctaIos = readCopy('ctaIos', 'Get for iPhone');
    var ctaAndroid = readCopy('ctaAndroid', 'Download for Android');
    var ctaChromeos = readCopy('ctaChromeos', 'Download for ChromeOS');
    var metaIos = readCopy('metaIos', 'Free · VideoGo on the App Store');
    var metaAndroid = readCopy('metaAndroid', 'v1.0.8 · APK · Free');
    var alsoAvailable = readCopy('alsoAvailable', 'Also available:');
    var androidInstallHintCopy = readCopy('androidInstallHint', 'After download, enable Install unknown apps in Settings to install the APK.');
    var desktopMacHref = getDesktopDownload('mac');
    var desktopWinHref = getDesktopDownload('win');
    var desktopLinuxHref = getDesktopDownload('linux');

    // iOS detected
    if (detectedOS === 'ios') {
      setPrimaryCtaLabel(ctaIos);
      setAllPlatformTargets(iosAppStoreUrl, true);
      if (downloadMeta) downloadMeta.textContent = metaIos;
      setHeroPlatforms(buildHeroPlatforms(alsoAvailable, [
        { label: 'Android', href: androidApkUrl },
        { label: 'macOS', href: desktopMacHref },
        { label: 'Windows', href: desktopWinHref },
        { label: 'Linux', href: desktopLinuxHref }
      ]));
      if (heroStepDownload) heroStepDownload.textContent = readCopy('nextStepIos', 'Open the App Store listing');
    }
    // Android detected
    else if (detectedOS === 'android') {
      setPrimaryCtaLabel(ctaAndroid);
      setAllPlatformTargets(androidApkUrl, false);
      if (downloadMeta) downloadMeta.textContent = metaAndroid;
      setHeroPlatforms(buildHeroPlatforms(alsoAvailable, [
        { label: 'iPhone', href: iosAppStoreUrl, openNewTab: true },
        { label: 'macOS', href: desktopMacHref },
        { label: 'Windows', href: desktopWinHref },
        { label: 'Linux', href: desktopLinuxHref }
      ]));
      if (heroStepDownload) heroStepDownload.textContent = readCopy('nextStepAndroid', 'Install the Android APK');
      // Show Android install hint
      var trustBadges = document.querySelector('.trust-badges');
      if (trustBadges) {
        var installHint = document.createElement('div');
        installHint.className = 'android-install-hint';
        installHint.innerHTML = '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg> ' + androidInstallHintCopy;
        trustBadges.parentNode.insertBefore(installHint, trustBadges.nextSibling);
      }
    }
    // ChromeOS — offer Android APK as primary, Linux as alternative
    else if (detectedOS === 'chromeos') {
      setPrimaryCtaLabel(ctaChromeos);
      setAllPlatformTargets(androidApkUrl, false);
      if (downloadMeta) downloadMeta.textContent = metaAndroid;
      setHeroPlatforms(buildHeroPlatforms(alsoAvailable, [
        { label: 'Linux AppImage', href: desktopLinuxHref },
        { label: 'iPhone', href: iosAppStoreUrl, openNewTab: true },
        { label: 'macOS', href: desktopMacHref },
        { label: 'Windows', href: desktopWinHref }
      ]));
      if (heroStepDownload) heroStepDownload.textContent = readCopy('nextStepChromeos', 'Install the Android build');
    }
    // Desktop platforms
    else {
      var desktopHref = getDesktopDownload(detectedOS === 'mac' ? 'mac' : detectedOS);
      setPrimaryCtaLabel(ctaPrefix + ' ' + osNames[detectedOS]);
      setAllPlatformTargets(desktopHref, false);
      if (heroStepDownload) heroStepDownload.textContent = readCopy('nextStepDesktop', 'Install the native app');
    }

    // Architecture-aware label (macOS only, Chromium browsers)
    if (detectedOS === 'mac' && navigator.userAgentData && navigator.userAgentData.getHighEntropyValues) {
      navigator.userAgentData.getHighEntropyValues(['architecture']).then(function(ua) {
        var arch = ua.architecture === 'arm' ? 'Apple Silicon' : 'Intel';
        setPrimaryCtaLabel(ctaPrefix + ' macOS (' + arch + ')');
      }).catch(function() {});
    }

    // Fetch latest version from public releases repo (desktop only)
    if (detectedOS !== 'ios' && detectedOS !== 'android' && detectedOS !== 'chromeos') {
      fetch('https://api.github.com/repos/mydinh-studio/ssvid-releases/releases/latest')
        .then(function(r) { return r.json(); })
        .then(function(data) {
          if (data.tag_name && downloadMeta) {
            var currentMeta = downloadMeta.textContent.split('·').map(function(part) {
              return part.trim();
            }).filter(Boolean);
            if (currentMeta.length > 1) {
              currentMeta[0] = data.tag_name;
              downloadMeta.textContent = currentMeta.join(' · ');
            } else {
              downloadMeta.textContent = data.tag_name;
            }
          }
        }).catch(function() {});
    }

    // Hide the detected platform from "Also available" links + its preceding separator
    var hideMap = { mac: altMac, win: altWin, linux: altLinux, ios: altIos, android: altAndroid };
    var hideEl = hideMap[detectedOS];
    if (hideEl) {
      hideEl.style.display = 'none';
    }
  }

  // --- Auto-stagger grid children (only for IO fallback, not CSS scroll-driven) ---
  if (!CSS.supports('animation-timeline', 'view()')) {
    document.querySelectorAll('.features-grid, .tech-grid, .pricing-grid, .stats-grid').forEach(function(grid) {
      var children = grid.children;
      for (var i = 0; i < children.length; i++) {
        if (!children[i].classList.contains('reveal')) {
          children[i].classList.add('reveal');
        }
        children[i].classList.add('stagger-' + (i + 1));
      }
    });
  }

  // --- Scroll Reveal (Intersection Observer fallback) ---
  // Only needed if CSS scroll-driven animations are not supported
  if (!CSS.supports('animation-timeline', 'view()')) {
    var revealElements = document.querySelectorAll('.reveal, .reveal-left, .reveal-right, .reveal-scale');

    if (revealElements.length > 0 && 'IntersectionObserver' in window) {
      var observer = new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            entry.target.classList.add('revealed');
            observer.unobserve(entry.target);
          }
        });
      }, {
        threshold: 0.15,
        rootMargin: '0px 0px -60px 0px'
      });

      revealElements.forEach(function (el) {
        observer.observe(el);
      });
    } else {
      // No Intersection Observer support — show everything
      revealElements.forEach(function (el) {
        el.classList.add('revealed');
      });
    }
  }

  // --- Reduced motion check ---
  var prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // --- Hero Demo Video — pause when out of viewport, respect reduced-motion ---
  var heroVideo = document.getElementById('hero-demo-video');
  if (heroVideo) {
    if (prefersReducedMotion) {
      // User prefers reduced motion: never autoplay, show poster only.
      heroVideo.removeAttribute('autoplay');
      heroVideo.pause();
    } else if ('IntersectionObserver' in window) {
      var heroVideoObserver = new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            var p = heroVideo.play();
            if (p && typeof p.catch === 'function') p.catch(function () { /* autoplay blocked — poster stays */ });
          } else {
            heroVideo.pause();
          }
        });
      }, { threshold: 0.25 });
      heroVideoObserver.observe(heroVideo);

      document.addEventListener('visibilitychange', function () {
        if (document.hidden) {
          heroVideo.pause();
        } else if (heroVideo.getBoundingClientRect().top < window.innerHeight && heroVideo.getBoundingClientRect().bottom > 0) {
          var p = heroVideo.play();
          if (p && typeof p.catch === 'function') p.catch(function () {});
        }
      });
    }
  }

  // --- Stat Counter Animation ---
  if ('IntersectionObserver' in window && !prefersReducedMotion) {
    function animateCounter(el) {
      var text = el.textContent.trim();
      if (text === 'Zero') return;
      var suffix = '';
      var target = 0;
      if (text.endsWith('+')) { suffix = '+'; target = parseInt(text); }
      else if (text.endsWith('x')) { suffix = 'x'; target = parseInt(text); }
      else { target = parseInt(text); }
      if (isNaN(target)) return;

      var duration = 1500;
      var startTime = null;
      function step(ts) {
        if (!startTime) startTime = ts;
        var progress = Math.min((ts - startTime) / duration, 1);
        var eased = 1 - Math.pow(1 - progress, 3);
        el.textContent = Math.floor(eased * target).toLocaleString() + suffix;
        if (progress < 1) requestAnimationFrame(step);
      }
      requestAnimationFrame(step);
    }

    var statObserver = new IntersectionObserver(function(entries) {
      entries.forEach(function(entry) {
        if (entry.isIntersecting) {
          animateCounter(entry.target);
          statObserver.unobserve(entry.target);
        }
      });
    }, { threshold: 0.5 });

    document.querySelectorAll('.stat-number').forEach(function(el) {
      statObserver.observe(el);
    });
  }

  // --- Scroll Progress Bar + Back to Top + Mobile Sticky CTA ---
  var scrollProgress = document.getElementById('scroll-progress');
  var backToTop = document.getElementById('back-to-top');

  // Update mobile sticky CTA link and text based on platform
  if (mobileCtaBtn) {
    var stickyIcon = detectedOS === 'ios'
      ? '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/></svg>'
      : '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>';
    mobileCtaBtn.innerHTML = stickyIcon + ' ' + getPrimaryCtaText('Download Free');
  }

  function onScroll() {
    var scrollTop = window.scrollY;
    var docHeight = document.documentElement.scrollHeight - window.innerHeight;
    // Scroll progress bar
    if (scrollProgress && docHeight > 0) {
      scrollProgress.style.width = (scrollTop / docHeight * 100) + '%';
    }
    // Back to top button
    if (backToTop) {
      backToTop.classList.toggle('visible', scrollTop > 400);
    }
    // Mobile sticky CTA — show after hero section
    if (mobileCta) {
      mobileCta.classList.toggle('visible', scrollTop > 500);
    }
  }

  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();

  if (backToTop) {
    backToTop.addEventListener('click', function () {
      window.scrollTo({ top: 0, behavior: 'smooth' });
    });
  }

  // --- Testimonial Carousel (mobile) ---
  var testimonialGrid = document.querySelector('.testimonials-grid');
  var carouselDots = document.querySelectorAll('.carousel-dot');

  if (testimonialGrid && carouselDots.length > 0) {
    var cards = testimonialGrid.querySelectorAll('.testimonial-card');
    var autoRotateTimer = null;

    function updateDots(idx) {
      carouselDots.forEach(function (d, i) {
        d.classList.toggle('active', i === idx);
      });
    }

    // Sync dots with scroll position
    testimonialGrid.addEventListener('scroll', function () {
      var scrollLeft = testimonialGrid.scrollLeft;
      var cardWidth = cards[0].offsetWidth + 16;
      var idx = Math.round(scrollLeft / cardWidth);
      updateDots(Math.min(idx, cards.length - 1));
    }, { passive: true });

    // Click/keyboard dots to scroll
    carouselDots.forEach(function (dot, i) {
      dot.setAttribute('tabindex', '0');
      function activateDot() {
        var cardWidth = cards[0].offsetWidth + 16;
        testimonialGrid.scrollTo({ left: i * cardWidth, behavior: 'smooth' });
        updateDots(i);
        resetAutoRotate();
      }
      dot.addEventListener('click', activateDot);
      dot.addEventListener('keydown', function (e) {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          activateDot();
        }
      });
    });

    // Auto-rotate every 5s (mobile only)
    function autoRotate() {
      autoRotateTimer = setInterval(function () {
        if (window.innerWidth > 768) return;
        var scrollLeft = testimonialGrid.scrollLeft;
        var cardWidth = cards[0].offsetWidth + 16;
        var idx = Math.round(scrollLeft / cardWidth);
        var next = (idx + 1) % cards.length;
        testimonialGrid.scrollTo({ left: next * cardWidth, behavior: 'smooth' });
        updateDots(next);
      }, 5000);
    }

    function resetAutoRotate() {
      clearInterval(autoRotateTimer);
      autoRotate();
    }

    // Pause on touch interaction
    testimonialGrid.addEventListener('touchstart', function () {
      clearInterval(autoRotateTimer);
    }, { passive: true });
    testimonialGrid.addEventListener('touchend', function () {
      resetAutoRotate();
    }, { passive: true });

    // Pause carousel on tab hidden
    document.addEventListener('visibilitychange', function () {
      if (document.hidden) { clearInterval(autoRotateTimer); }
      else if (!prefersReducedMotion) { autoRotate(); }
    });

    if (!prefersReducedMotion) autoRotate();
  }

  // --- Newsletter Form ---
  var newsletterForm = document.getElementById('newsletter-form');
  var newsletterMsg = document.getElementById('newsletter-msg');

  if (newsletterForm) {
    newsletterForm.addEventListener('submit', function (e) {
      e.preventDefault();
      var emailInput = document.getElementById('newsletter-email');
      if (!emailInput) return;
      var email = emailInput.value;
      if (!email) return;

      var submitBtn = newsletterForm.querySelector('button[type="submit"]');

      // Newsletter backend not yet connected — show honest message
      if (newsletterMsg) {
        newsletterMsg.textContent = 'Newsletter coming soon! Follow us on X for updates.';
        newsletterMsg.className = 'newsletter-msg';
      }
      emailInput.value = '';
      submitBtn.textContent = 'Coming Soon';
      submitBtn.disabled = true;
      setTimeout(function () {
        submitBtn.textContent = 'Subscribe';
        submitBtn.disabled = false;
        if (newsletterMsg) newsletterMsg.textContent = '';
      }, 4000);
    });
  }

  // --- Cursor Glow on CTA Buttons ---
  document.querySelectorAll('.btn-primary').forEach(function(btn) {
    btn.addEventListener('mousemove', function(e) {
      var rect = btn.getBoundingClientRect();
      btn.style.setProperty('--glow-x', (e.clientX - rect.left) + 'px');
      btn.style.setProperty('--glow-y', (e.clientY - rect.top) + 'px');
    }, { passive: true });
  });

  // --- Cookie Consent Banner ---
  var cookieBanner = document.getElementById('cookie-consent');
  var cookieAccept = document.getElementById('cookie-accept');

  if (cookieBanner && !localStorage.getItem('ssvid-cookie-consent')) {
    setTimeout(function () {
      cookieBanner.classList.add('visible');
    }, 2000);
  }

  if (cookieAccept) {
    cookieAccept.addEventListener('click', function () {
      localStorage.setItem('ssvid-cookie-consent', '1');
      cookieBanner.classList.remove('visible');
    });
  }

  var cookieDismiss = document.getElementById('cookie-dismiss');
  if (cookieDismiss) {
    cookieDismiss.addEventListener('click', function () {
      cookieBanner.classList.remove('visible');
    });
  }

  // --- Stripe Web Checkout ---
  var CHECKOUT_API = 'https://api.ssvid.app/api/v1/premium/stripe/web-checkout';

  // --- Toast Notifications (replaces alert()) ---
  var toastContainer = null;
  function showToast(message, type) {
    if (!toastContainer) {
      toastContainer = document.createElement('div');
      toastContainer.className = 'toast-container';
      toastContainer.setAttribute('role', 'status');
      toastContainer.setAttribute('aria-live', 'polite');
      document.body.appendChild(toastContainer);
    }
    var toast = document.createElement('div');
    toast.className = 'toast toast-' + (type || 'info');
    var icon = type === 'error'
      ? '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>'
      : '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2"><polyline points="20 6 9 17 4 12"/></svg>';
    toast.innerHTML = '<span class="toast-icon">' + icon + '</span><span class="toast-message"></span><button class="toast-close" aria-label="Close">&times;</button>';
    toast.querySelector('.toast-message').textContent = message;
    toastContainer.appendChild(toast);
    // Trigger entrance animation
    requestAnimationFrame(function () { toast.classList.add('toast-show'); });
    // Close button
    var closeBtn = toast.querySelector('.toast-close');
    var dismiss = function () {
      toast.classList.remove('toast-show');
      setTimeout(function () { toast.remove(); }, 250);
    };
    closeBtn.addEventListener('click', dismiss);
    // Auto-dismiss after 6s
    setTimeout(dismiss, 6000);
  }

  window.startCheckout = function (btn) {
    if (btn.disabled) return;

    // Determine billing cycle
    var plan = btn.dataset.plan; // lifetime buttons
    if (!plan) {
      // Premium subscription — depends on toggle state
      plan = isYearly ? btn.dataset.planYearly : btn.dataset.planMonthly;
    }
    if (!plan) return;

    // Loading state
    var originalText = btn.textContent;
    btn.disabled = true;
    btn.textContent = btn.dataset.loadingLabel || 'Redirecting...';

    var controller = new AbortController();
    var timeoutId = setTimeout(function () { controller.abort(); }, 15000);

    fetch(CHECKOUT_API, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ billingCycle: plan }),
      signal: controller.signal
    })
      .then(function (res) {
        clearTimeout(timeoutId);
        if (!res.ok) {
          if (res.status === 404) throw new Error('Payment endpoint not available. The server may be updating — please try again in a few minutes.');
          if (res.status === 503) throw new Error('Payment service is temporarily unavailable. Please try again later.');
          if (res.status >= 500) throw new Error('Server error. Please try again later.');
          return res.json().then(function (data) {
            throw new Error((data.error && data.error.message) || 'Payment request failed (HTTP ' + res.status + ').');
          });
        }
        return res.json();
      })
      .then(function (data) {
        if (data.success && data.data && data.data.checkoutUrl) {
          var url = data.data.checkoutUrl;
          if (url.indexOf('https://checkout.stripe.com') === 0 || url.indexOf('https://pay.stripe.com') === 0) {
            window.location.href = url;
          } else {
            showToast('Unexpected payment URL. Please contact support.', 'error');
            btn.disabled = false;
            btn.textContent = originalText;
          }
        } else {
          var msg = (data.error && data.error.message) || 'Payment service unavailable. Please try again.';
          showToast(msg, 'error');
          btn.disabled = false;
          btn.textContent = originalText;
        }
      })
      .catch(function (err) {
        var msg = err.name === 'AbortError'
          ? 'Request timed out. Please try again.'
          : err.message || 'Could not connect to payment server. Please try again later.';
        showToast(msg, 'error');
        btn.disabled = false;
        btn.textContent = originalText;
      });
  };

  // --- Language Dropdown ---
  var langDropdown = document.getElementById('lang-dropdown');
  var langToggle = document.getElementById('lang-toggle');
  if (langDropdown && langToggle) {
    langToggle.addEventListener('click', function (e) {
      e.stopPropagation();
      var isOpen = langDropdown.classList.toggle('open');
      langToggle.setAttribute('aria-expanded', isOpen);
    });
    document.addEventListener('click', function (e) {
      if (!langDropdown.contains(e.target)) {
        langDropdown.classList.remove('open');
        langToggle.setAttribute('aria-expanded', 'false');
      }
    });
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && langDropdown.classList.contains('open')) {
        langDropdown.classList.remove('open');
        langToggle.setAttribute('aria-expanded', 'false');
        langToggle.focus();
      }
    });
  }

  // --- GitHub Stars Social Proof ---
  var githubStars = document.getElementById('github-stars');
  if (githubStars) {
    fetch('https://api.github.com/repos/mydinh-studio/ssvid-releases')
      .then(function(r) { return r.json(); })
      .then(function(data) {
        if (data.stargazers_count > 0) {
          githubStars.textContent = data.stargazers_count.toLocaleString();
          githubStars.parentElement.style.display = '';
        }
      }).catch(function() {});
  }

  // --- Download Count (from releases) ---
  var downloadCount = document.getElementById('download-count');
  if (downloadCount) {
    fetch('https://api.github.com/repos/mydinh-studio/ssvid-releases/releases')
      .then(function(r) { return r.json(); })
      .then(function(releases) {
        if (!Array.isArray(releases)) return;
        var total = 0;
        releases.forEach(function(rel) {
          if (rel.assets) rel.assets.forEach(function(a) { total += a.download_count || 0; });
        });
        if (total > 0) {
          downloadCount.textContent = total >= 1000 ? Math.floor(total / 1000) + 'K+' : total.toLocaleString();
          downloadCount.parentElement.style.display = '';
        }
      }).catch(function() {});
  }

  // --- Smooth scroll for anchor links ---
  document.querySelectorAll('a[href^="#"]').forEach(function(link) {
    link.addEventListener('click', function(e) {
      var target = document.querySelector(this.getAttribute('href'));
      if (target) {
        e.preventDefault();
        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
        history.pushState(null, '', this.getAttribute('href'));
      }
    });
  });

  // --- Service Worker Registration ---
  if ('serviceWorker' in navigator) {
    window.addEventListener('load', function() {
      navigator.serviceWorker.register('/sw.js').catch(function() {});
    });
  }

  // --- Dynamic copyright year ---
  var copyrightYear = document.getElementById('copyright-year');
  if (copyrightYear) copyrightYear.textContent = new Date().getFullYear();

  // --- Hero Animated Mockup ---
  var heroMockup = document.querySelector('.hero-mockup');

  if (heroMockup && !prefersReducedMotion) {
    var mockScenes = heroMockup.querySelectorAll('.mockup-scene');
    var mockTabs = heroMockup.querySelectorAll('.mockup-nav-tab');
    var mockIdx = 0;
    var mockPaused = false;
    var mockTimer = null;
    var typeTimer = null;
    var dlTimer = null;

    // Scene durations (ms): URL typing, quality view, download progress, library grid
    var sceneDurations = [3500, 2800, 3200, 3500];

    // Tab mapping: which tab is active for each scene
    var sceneTabMap = ['home', 'home', 'home', 'library'];

    function mockShowScene(idx) {
      mockScenes.forEach(function (s) { s.classList.remove('is-active'); });
      mockScenes[idx].classList.add('is-active');

      // Update nav tabs
      var activeTab = sceneTabMap[idx];
      mockTabs.forEach(function (t) {
        t.classList.toggle('is-active', t.dataset.tab === activeTab);
      });

      mockIdx = idx;

      // Scene-specific logic
      if (idx === 0) mockTypeUrl();
      if (idx === 2) mockAnimateProgress();
    }

    function mockNext() {
      if (mockPaused) return;
      mockShowScene((mockIdx + 1) % mockScenes.length);
      mockSchedule();
    }

    function mockSchedule() {
      clearTimeout(mockTimer);
      mockTimer = setTimeout(mockNext, sceneDurations[mockIdx]);
    }

    // Typewriter effect for URL scene
    function mockTypeUrl() {
      var el = document.getElementById('hero-typed');
      if (!el) return;
      var url = 'https://youtube.com/watch?v=dQw4...';
      var ci = 0;
      el.textContent = '';
      clearInterval(typeTimer);
      typeTimer = setInterval(function () {
        if (ci < url.length) {
          el.textContent += url[ci];
          ci++;
        } else {
          clearInterval(typeTimer);
        }
      }, 55);
    }

    // Progress bar animation for download scene
    function mockAnimateProgress() {
      var fill = document.getElementById('hero-dl-fill');
      var pct = document.getElementById('hero-dl-pct');
      var rate = document.getElementById('hero-dl-rate');
      if (!fill) return;

      var progress = 0;
      fill.style.width = '0%';
      if (pct) pct.textContent = '0%';
      clearInterval(dlTimer);

      dlTimer = setInterval(function () {
        progress += 2;
        if (progress > 100) progress = 100;
        fill.style.width = progress + '%';
        if (pct) pct.textContent = progress >= 100 ? 'Done!' : progress + '%';
        if (rate) rate.textContent = progress >= 100 ? 'Complete' : (8 + Math.random() * 12).toFixed(1) + ' MB/s';
        if (progress >= 100) clearInterval(dlTimer);
      }, 55);
    }

    // Start the loop
    mockShowScene(0);
    mockSchedule();

    // Pause when out of viewport
    if ('IntersectionObserver' in window) {
      var mockObs = new IntersectionObserver(function (entries) {
        mockPaused = !entries[0].isIntersecting;
        if (!mockPaused) {
          // Reset to URL scene on re-enter for fresh impression
          clearInterval(typeTimer);
          clearInterval(dlTimer);
          mockShowScene(0);
          mockSchedule();
        } else {
          clearTimeout(mockTimer);
          clearInterval(typeTimer);
          clearInterval(dlTimer);
        }
      }, { threshold: 0.15 });
      mockObs.observe(heroMockup);
    }

    // Pause on tab hidden
    document.addEventListener('visibilitychange', function () {
      if (document.hidden) {
        mockPaused = true;
        clearTimeout(mockTimer);
        clearInterval(typeTimer);
        clearInterval(dlTimer);
      } else {
        mockPaused = false;
        mockSchedule();
      }
    });
  }

  // Reduced motion: show library scene statically
  if (heroMockup && prefersReducedMotion) {
    heroMockup.querySelectorAll('.mockup-scene').forEach(function (s) { s.classList.remove('is-active'); });
    var libScene = heroMockup.querySelector('[data-scene="library"]');
    if (libScene) libScene.classList.add('is-active');
    heroMockup.querySelectorAll('.mockup-nav-tab').forEach(function (t) {
      t.classList.toggle('is-active', t.dataset.tab === 'library');
    });
  }

  /* ── Product Showcase Tabs ── */
  var showcaseTabs = document.querySelectorAll('.showcase-tab');
  var showcasePanels = document.querySelectorAll('.showcase-panel');

  if (showcaseTabs.length) {
    showcaseTabs.forEach(function (tab) {
      tab.addEventListener('click', function () {
        var target = tab.dataset.showcase;
        showcaseTabs.forEach(function (t) {
          t.classList.toggle('is-active', t.dataset.showcase === target);
          t.setAttribute('aria-selected', t.dataset.showcase === target ? 'true' : 'false');
        });
        showcasePanels.forEach(function (p) {
          p.classList.toggle('is-active', p.dataset.showcasePanel === target);
        });
      });
    });
  }

})();
