#!/usr/bin/env node

/**
 * extract-translations.js
 *
 * Extracts translatable text from SSvid landing page HTML files into JSON.
 * All 15 language variants share the same HTML structure — only text differs.
 * Uses CSS class/ID-based extraction (robust across comment variations).
 *
 * Usage: node extract-translations.js
 * Output: website/src/i18n/{langcode}.json
 */

const fs = require('fs');
const path = require('path');

const WEBSITE_DIR = __dirname;
const OUTPUT_DIR = path.join(WEBSITE_DIR, 'src', 'i18n');

const LANGUAGES = [
  { code: 'en', file: 'index.html' },
  { code: 'vi', file: 'vi/index.html' },
  { code: 'ja', file: 'ja/index.html' },
  { code: 'ko', file: 'ko/index.html' },
  { code: 'zh', file: 'zh/index.html' },
  { code: 'es', file: 'es/index.html' },
  { code: 'pt', file: 'pt/index.html' },
  { code: 'fr', file: 'fr/index.html' },
  { code: 'de', file: 'de/index.html' },
  { code: 'id', file: 'id/index.html' },
  { code: 'th', file: 'th/index.html' },
  { code: 'tr', file: 'tr/index.html' },
  { code: 'ru', file: 'ru/index.html' },
  { code: 'ar', file: 'ar/index.html' },
  { code: 'hi', file: 'hi/index.html' },
];

// ─── Helpers ────────────────────────────────────────────────────────────────

function textOf(html, pattern) {
  const m = html.match(pattern);
  return m ? m[1].trim() : '';
}

function metaContent(html, nameOrProp, attr = 'name') {
  const escaped = nameOrProp.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(`<meta\\s+(?:${attr}="${escaped}"\\s+content="([^"]*?)"|content="([^"]*?)"\\s+${attr}="${escaped}")`, 'i');
  const m = html.match(re);
  return m ? (m[1] || m[2] || '') : '';
}

function allMatches(html, re, group = 1) {
  const results = [];
  let m;
  while ((m = re.exec(html)) !== null) {
    results.push(m[group].trim());
  }
  return results;
}

function stripTags(s) {
  return s.replace(/<[^>]+>/g, '').trim();
}

/**
 * Extract section between two regex markers.
 * Uses class/ID patterns instead of HTML comments for robustness.
 */
function sectionBetween(html, startRe, endRe) {
  const startM = html.match(startRe);
  if (!startM) return '';
  const startIdx = startM.index + startM[0].length;
  const rest = html.slice(startIdx);
  const endM = rest.match(endRe);
  if (!endM) return rest;
  return rest.slice(0, endM.index);
}

// ─── Extraction ─────────────────────────────────────────────────────────────

function extractTranslations(html) {
  const t = {};

  // ── 1. Meta tags ──────────────────────────────────────────────────────
  t.meta = {
    title: textOf(html, /<title>([^<]+)<\/title>/),
    description: metaContent(html, 'description'),
    keywords: metaContent(html, 'keywords'),
  };

  // ── 2. OG tags ────────────────────────────────────────────────────────
  t.og = {
    title: metaContent(html, 'og:title', 'property'),
    description: metaContent(html, 'og:description', 'property'),
  };

  // ── 3. Twitter tags ───────────────────────────────────────────────────
  t.twitter = {
    title: metaContent(html, 'twitter:title'),
    description: metaContent(html, 'twitter:description'),
  };

  // ── 4. Nav + a11y ─────────────────────────────────────────────────────
  const navSection = sectionBetween(html, /id="nav-links"/, /<\/div>/);
  const navLinks = allMatches(navSection, /<a[^>]*>([^<]+)<\/a>/g);

  const skipLinkM = html.match(/<a[^>]*class="skip-link"[^>]*>([^<]+)<\/a>/);
  const langSwitchLabel = (html.match(/class="lang-switch"[^>]*aria-label="([^"]+)"/) || [])[1] || '';
  const themeToggleLabel = (html.match(/id="theme-toggle"[^>]*aria-label="([^"]+)"/) || [])[1] || '';
  const mobileMenuLabel = (html.match(/id="mobile-menu-btn"[^>]*aria-label="([^"]+)"/) || [])[1] || '';

  t.nav = {
    features: navLinks[0] || '',
    pricing: navLinks[1] || '',
    faq: navLinks[2] || '',
    downloadFree: textOf(html, /<a[^>]*id="nav-download-btn"[^>]*>([^<]+)<\/a>/),
  };

  t.a11y = {
    skipLink: skipLinkM ? skipLinkM[1].trim() : '',
    langSwitchLabel,
    themeToggleLabel,
    mobileMenuLabel,
  };

  // ── 5. Hero ───────────────────────────────────────────────────────────
  const badgeM = html.match(/<div class="hero-badge">[^]*?<\/span>\s*\n?\s*([^<]+)/);
  const h1M = html.match(/<h1>([^<]*)<span class="text-gradient">([^<]+)<\/span><\/h1>/);
  const subtitleM = html.match(/<p class="hero-subtitle">\s*([\s\S]*?)\s*<\/p>/);
  const downloadLabelM = html.match(/id="download-label">([^<]+)<\/span>/);
  const downloadMetaM = html.match(/id="download-meta">([^<]+)<\/span>/);
  const viewPricingM = html.match(/class="btn-text-link">([^<]+)/);
  const proofTextM = html.match(/class="proof-text">\s*<svg[^>]*>[^]*?<\/svg>\s*\n?\s*([\s\S]*?)\s*<\/span>/);

  const trustSection = sectionBetween(html, /class="trust-badges"/, /class="hero-platforms"/);
  const trustTexts = allMatches(trustSection, /class="trust-badge">\s*<svg[^]*?<\/svg>\s*\n?\s*([^<]+)/g);
  const alsoAvailM = html.match(/class="platform-label">([^<]+)<\/span>/);

  t.hero = {
    badge: badgeM ? badgeM[1].trim() : '',
    title1: h1M ? h1M[1].trim() : '',
    titleGradient: h1M ? h1M[2].trim() : '',
    subtitle: subtitleM ? subtitleM[1].replace(/\s+/g, ' ').trim() : '',
    downloadBtn: downloadLabelM ? downloadLabelM[1].trim() : '',
    downloadMeta: downloadMetaM ? downloadMetaM[1].trim() : '',
    viewPricing: viewPricingM ? viewPricingM[1].trim() : '',
    socialProof: proofTextM ? proofTextM[1].replace(/\s+/g, ' ').trim() : '',
    trustNoTracking: trustTexts[0] ? trustTexts[0].trim() : '',
    trustCodeSigned: trustTexts[1] ? trustTexts[1].trim() : '',
    trustVirusFree: trustTexts[2] ? trustTexts[2].trim() : '',
    alsoAvailable: alsoAvailM ? alsoAvailM[1].trim() : '',
  };

  // ── 6. Hero mock app labels ───────────────────────────────────────────
  const mockLabels = allMatches(html, /class="mock-nav-item[^"]*"\s+data-label="([^"]+)"/g);
  const mockBadgeM = html.match(/class="mock-badge">([^<]+)<\/div>/);
  t.heroMock = {
    navDownloads: mockLabels[0] || '',
    navBrowser: mockLabels[1] || '',
    navPlayer: mockLabels[2] || '',
    navHistory: mockLabels[3] || '',
    navSettings: mockLabels[4] || '',
    completed: mockBadgeM ? mockBadgeM[1].trim() : '',
  };

  // ── 7. Platform strip ─────────────────────────────────────────────────
  const stripLabelM = html.match(/class="strip-label[^"]*">([^<]+)<\/p>/);
  t.platformStrip = {
    label: stripLabelM ? stripLabelM[1].trim() : '',
  };

  // ── 8. Stats ──────────────────────────────────────────────────────────
  const statNumbers = allMatches(html, /class="stat-number">([^<]+)<\/div>/g);
  const statLabels = allMatches(html, /class="stat-label">([^<]+)<\/div>/g);
  t.stats = {
    number1: statNumbers[0] || '',
    label1: statLabels[0] || '',
    number2: statNumbers[1] || '',
    label2: statLabels[1] || '',
    number3: statNumbers[2] || '',
    label3: statLabels[2] || '',
    number4: statNumbers[3] || '',
    label4: statLabels[3] || '',
  };

  // ── 9. Features (use class="features" section) ────────────────────────
  // Boundary: from <section class="features" to <section class="product-showcase"
  const featuresSection = sectionBetween(html, /<section class="features"/, /<section class="product-showcase"/);

  const featHeaderH2 = featuresSection.match(/<h2>([\s\S]*?)<\/h2>/);
  const featHeaderP = featuresSection.match(/class="section-header[\s\S]*?<p>([^<]+)<\/p>/);
  const featTitles = allMatches(featuresSection, /class="feature-card[\s\S]*?<h3>([^<]+)<\/h3>/g);
  const featDescs = allMatches(featuresSection, /class="feature-card[\s\S]*?<\/h3>\s*\n?\s*<p>([^<]+)<\/p>/g);

  t.features = {
    title: featHeaderH2 ? stripTags(featHeaderH2[1]).trim() : '',
    subtitle: featHeaderP ? featHeaderP[1].trim() : '',
    card1Title: featTitles[0] || '',
    card1Desc: featDescs[0] || '',
    card2Title: featTitles[1] || '',
    card2Desc: featDescs[1] || '',
    card3Title: featTitles[2] || '',
    card3Desc: featDescs[2] || '',
    card4Title: featTitles[3] || '',
    card4Desc: featDescs[3] || '',
    card5Title: featTitles[4] || '',
    card5Desc: featDescs[4] || '',
    card6Title: featTitles[5] || '',
    card6Desc: featDescs[5] || '',
  };

  // ── 10. Product Showcase ──────────────────────────────────────────────
  const showcaseSection = sectionBetween(html, /<section class="product-showcase"/, /<section class="privacy-statement"/);

  const showcaseH2 = showcaseSection.match(/<h2>([\s\S]*?)<\/h2>/);
  const showcaseP = showcaseSection.match(/class="section-header[\s\S]*?<p>([^<]+)<\/p>/);
  const showcaseTitles = allMatches(showcaseSection, /class="showcase-label">\s*<h3>([^<]+)<\/h3>/g);
  const showcaseDescs = allMatches(showcaseSection, /class="showcase-label">[\s\S]*?<p>([^<]+)<\/p>/g);

  t.showcase = {
    title: showcaseH2 ? stripTags(showcaseH2[1]).trim() : '',
    subtitle: showcaseP ? showcaseP[1].trim() : '',
    item1Title: showcaseTitles[0] || '',
    item1Desc: showcaseDescs[0] || '',
    item2Title: showcaseTitles[1] || '',
    item2Desc: showcaseDescs[1] || '',
  };

  // ── 11. Privacy Statement ─────────────────────────────────────────────
  const privacyM = html.match(/class="privacy-statement-text[^"]*">([\s\S]*?)<\/p>/);
  t.privacy = {
    text: privacyM ? privacyM[1].replace(/<br\s*\/?>/g, '\n').replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim() : '',
  };

  // ── 12. How It Works ──────────────────────────────────────────────────
  const hiwSection = sectionBetween(html, /<section class="how-it-works"/, /<section class="comparison"/);

  const hiwH2M = hiwSection.match(/<h2>([\s\S]*?)<\/h2>/);
  const hiwPM = hiwSection.match(/class="section-header[\s\S]*?<p>([^<]+)<\/p>/);
  const stepTitles = allMatches(hiwSection, /class="step-item[\s\S]*?<h3>([^<]+)<\/h3>/g);
  const stepDescs = allMatches(hiwSection, /class="step-item[\s\S]*?<\/h3>\s*\n?\s*<p>([^<]+)<\/p>/g);

  t.howItWorks = {
    title: hiwH2M ? stripTags(hiwH2M[1]).trim() : '',
    subtitle: hiwPM ? hiwPM[1].trim() : '',
    step1Title: stepTitles[0] || '',
    step1Desc: stepDescs[0] || '',
    step2Title: stepTitles[1] || '',
    step2Desc: stepDescs[1] || '',
    step3Title: stepTitles[2] || '',
    step3Desc: stepDescs[2] || '',
  };

  // ── 13. Comparison ────────────────────────────────────────────────────
  const compSection = sectionBetween(html, /<section class="comparison"/, /<section class="pricing"/);

  const compH2M = compSection.match(/<h2>([\s\S]*?)<\/h2>/);
  const compPM = compSection.match(/class="section-header[\s\S]*?<p>([^<]+)<\/p>/);
  const thValues = allMatches(compSection, /<th[^>]*>([^<]+)<\/th>/g);

  const rows = [];
  const tbodyM = compSection.match(/<tbody>([\s\S]*?)<\/tbody>/);
  if (tbodyM) {
    const rowReInner = /<tr>\s*([\s\S]*?)\s*<\/tr>/g;
    let rowM;
    while ((rowM = rowReInner.exec(tbodyM[1])) !== null) {
      const cells = allMatches(rowM[1], /<td[^>]*>([\s\S]*?)<\/td>/g);
      rows.push(cells.map(c => stripTags(c).trim()));
    }
  }

  t.comparison = {
    title: compH2M ? stripTags(compH2M[1]).trim() : '',
    subtitle: compPM ? compPM[1].trim() : '',
    colFeature: thValues[0] || '',
    colSsvid: thValues[1] || '',
    colExtensions: thValues[2] || '',
    colOnline: thValues[3] || '',
  };

  for (let i = 0; i < rows.length; i++) {
    const r = rows[i];
    t.comparison[`row${i + 1}Label`] = r[0] || '';
    t.comparison[`row${i + 1}Ssvid`] = r[1] || '';
    t.comparison[`row${i + 1}Extensions`] = r[2] || '';
    t.comparison[`row${i + 1}Online`] = r[3] || '';
  }

  // ── 14. Pricing ───────────────────────────────────────────────────────
  const pricingSection = sectionBetween(html, /<section class="pricing"/, /<section class="testimonials"/);

  const pricingH2M = pricingSection.match(/<h2>([\s\S]*?)<\/h2>/);
  const pricingPM = pricingSection.match(/class="section-header[\s\S]*?<p>([^<]+)<\/p>/);
  const billingMonthlyM = pricingSection.match(/data-interval="monthly">([^<]+)<\/span>/);
  const yearlyTextM = pricingSection.match(/data-interval="yearly">([^<]+)/);
  const saveBadgeM = pricingSection.match(/class="save-badge">([^<]+)<\/span>/);
  const ribbonM = pricingSection.match(/class="price-ribbon">([^<]+)<\/div>/);

  // Free plan: first price-card (NOT recommended)
  const freeCardM = pricingSection.match(/class="price-card reveal[^"]*">([\s\S]*?)(?=<div class="price-card recommended|$)/);
  // Fallback: try without "reveal"
  const freeCardContent = freeCardM ? freeCardM[1] :
    (pricingSection.match(/class="price-card(?:\s+reveal[^"]*)?"\s*>([\s\S]*?)(?=<div class="price-card recommended|$)/) || [])[1] || '';

  const freeTitleM = freeCardContent.match(/<h3>([^<]+)<\/h3>/);
  const freeDescM = freeCardContent.match(/class="price-desc">([^<]+)/);
  const freePeriodM = freeCardContent.match(/class="price-period">([^<]+)/);
  const freeFeatures = allMatches(freeCardContent, /<li>[^]*?<\/svg>([^<]+)<\/li>/g);
  const freeBtnM = freeCardContent.match(/class="btn btn-outline btn-block">([^<]+)/);

  // Premium plan: price-card recommended
  const premCardFullM = pricingSection.match(/class="price-card recommended[\s\S]*?(?=<div class="lifetime-section|<\/div>\s*<\/div>\s*<div class="lifetime|$)/);
  const premCardContent = premCardFullM ? premCardFullM[0] : '';

  const premTitleM = premCardContent.match(/<h3>([^<]+)<\/h3>/);
  const premDescM = premCardContent.match(/class="price-desc">([^<]+)/);
  const premPeriodM = premCardContent.match(/class="price-period">([^<]+)/);
  const premBilledM = premCardContent.match(/class="price-billed-yearly"[^>]*>([^<]+)/);
  const premDevicesM = premCardContent.match(/class="price-devices"[^>]*>([^<]+)/);
  const premDevicesYearlyM = premCardContent.match(/class="price-devices"[^>]*data-yearly="([^"]+)"/);
  const premFeaturesListM = premCardContent.match(/<ul class="price-features">([\s\S]*?)<\/ul>/);
  const premFeatures = premFeaturesListM ? allMatches(premFeaturesListM[1], /<li>[^]*?<\/svg>([^<]+)<\/li>/g) : [];
  const premBtnM = premCardContent.match(/class="btn[^"]*btn-primary btn-block[^"]*"[^>]*>([^<]+)/);

  // Lifetime
  const lifetimeSection = sectionBetween(pricingSection, /class="lifetime-section/, /<\/section>/);
  const lifetimeTitleM = lifetimeSection.match(/class="lifetime-title">([^<]+)/);
  const lifetimeNames = allMatches(lifetimeSection, /class="lifetime-name">([^<]+)<\/div>/g);
  const lifetimeDetails = allMatches(lifetimeSection, /class="lifetime-detail">([^<]+)<\/div>/g);
  const lifetimeBadgeM = lifetimeSection.match(/class="lifetime-badge">([^<]+)<\/div>/);
  const lifetimeNoteM = lifetimeSection.match(/class="lifetime-note">([^<]+)/);
  const lifetimeBuyBtns = allMatches(lifetimeSection, /class="btn[^"]*checkout-btn"[^>]*>([^<]+)<\/button>/g);

  t.pricing = {
    title: pricingH2M ? stripTags(pricingH2M[1]).trim() : '',
    subtitle: pricingPM ? pricingPM[1].trim() : '',
    billingMonthly: billingMonthlyM ? billingMonthlyM[1].trim() : '',
    billingYearly: yearlyTextM ? yearlyTextM[1].trim() : '',
    billingSave: saveBadgeM ? saveBadgeM[1].trim() : '',
    ribbon: ribbonM ? ribbonM[1].trim() : '',
    freeTitle: freeTitleM ? freeTitleM[1].trim() : '',
    freeDesc: freeDescM ? freeDescM[1].trim() : '',
    freePeriod: freePeriodM ? freePeriodM[1].trim() : '',
    freeFeature1: freeFeatures[0] || '',
    freeFeature2: freeFeatures[1] || '',
    freeFeature3: freeFeatures[2] || '',
    freeFeature4: freeFeatures[3] || '',
    freeBtn: freeBtnM ? freeBtnM[1].trim() : '',
    premiumTitle: premTitleM ? premTitleM[1].trim() : '',
    premiumDesc: premDescM ? premDescM[1].trim() : '',
    premiumPeriod: premPeriodM ? premPeriodM[1].trim() : '',
    premiumBilledYearly: premBilledM ? premBilledM[1].trim() : '',
    premiumDevices: premDevicesM ? premDevicesM[1].trim() : '',
    premiumDevicesYearly: premDevicesYearlyM ? premDevicesYearlyM[1].trim() : '',
    premiumFeature1: premFeatures[0] || '',
    premiumFeature2: premFeatures[1] || '',
    premiumFeature3: premFeatures[2] || '',
    premiumFeature4: premFeatures[3] || '',
    premiumFeature5: premFeatures[4] || '',
    premiumFeature6: premFeatures[5] || '',
    premiumFeature7: premFeatures[6] || '',
    premiumBtn: premBtnM ? premBtnM[1].trim() : '',
    lifetimeTitle: lifetimeTitleM ? lifetimeTitleM[1].trim() : '',
    lifetimeBadge: lifetimeBadgeM ? lifetimeBadgeM[1].trim() : '',
    lifetimeName1: lifetimeNames[0] || '',
    lifetimeDetail1: lifetimeDetails[0] || '',
    lifetimeBuy1: lifetimeBuyBtns[0] || '',
    lifetimeName2: lifetimeNames[1] || '',
    lifetimeDetail2: lifetimeDetails[1] || '',
    lifetimeBuy2: lifetimeBuyBtns[1] || '',
    lifetimeName3: lifetimeNames[2] || '',
    lifetimeDetail3: lifetimeDetails[2] || '',
    lifetimeBuy3: lifetimeBuyBtns[2] || '',
    lifetimeNote: lifetimeNoteM ? lifetimeNoteM[1].trim() : '',
  };

  // ── 15. Testimonials / Use Cases ──────────────────────────────────────
  const testimSection = sectionBetween(html, /<section class="testimonials"/, /<section class="changelog"/);

  const testimH2M = testimSection.match(/<h2>([\s\S]*?)<\/h2>/);
  const testimPM = testimSection.match(/class="section-header[\s\S]*?<p>([^<]+)<\/p>/);
  const testimTexts = allMatches(testimSection, /class="testimonial-text">([^<]+)<\/p>/g);
  const authorNames = allMatches(testimSection, /class="author-name">([^<]+)<\/div>/g);
  const authorRoles = allMatches(testimSection, /class="author-role">([^<]+)<\/div>/g);

  t.testimonials = {
    title: testimH2M ? stripTags(testimH2M[1]).trim() : '',
    subtitle: testimPM ? testimPM[1].trim() : '',
    card1Text: testimTexts[0] || '',
    card1Name: authorNames[0] || '',
    card1Role: authorRoles[0] || '',
    card2Text: testimTexts[1] || '',
    card2Name: authorNames[1] || '',
    card2Role: authorRoles[1] || '',
    card3Text: testimTexts[2] || '',
    card3Name: authorNames[2] || '',
    card3Role: authorRoles[2] || '',
  };

  // ── 16. Changelog ─────────────────────────────────────────────────────
  const changelogSection = sectionBetween(html, /<section class="changelog"/, /<section class="faq"/);

  const clH2M = changelogSection.match(/<h2>([\s\S]*?)<\/h2>/);
  const clPM = changelogSection.match(/class="section-header[\s\S]*?<p>([^<]+)<\/p>/);
  const clTags = allMatches(changelogSection, /class="changelog-tag[^"]*">([^<]+)<\/span>/g);
  const clTitles = allMatches(changelogSection, /class="changelog-title">([^<]+)<\/h3>/g);
  const clDescs = allMatches(changelogSection, /class="changelog-desc">([^<]+)<\/p>/g);

  t.changelog = {
    title: clH2M ? stripTags(clH2M[1]).trim() : '',
    subtitle: clPM ? clPM[1].trim() : '',
  };

  for (let i = 0; i < clTitles.length; i++) {
    t.changelog[`entry${i + 1}Tag`] = clTags[i] || '';
    t.changelog[`entry${i + 1}Title`] = clTitles[i] || '';
    t.changelog[`entry${i + 1}Desc`] = clDescs[i] || '';
  }

  // ── 17. FAQ ───────────────────────────────────────────────────────────
  const faqSection = sectionBetween(html, /<section class="faq"/, /<section class="tech-section"/);

  const faqH2M = faqSection.match(/<h2>([\s\S]*?)<\/h2>/);
  const faqPM = faqSection.match(/class="section-header[\s\S]*?<p>([^<]+)<\/p>/);
  const faqQuestions = allMatches(faqSection, /<summary>\s*<span>([^<]+)<\/span>/g);
  const faqAnswers = allMatches(faqSection, /class="faq-answer">\s*<p>([^<]+)<\/p>/g);

  t.faq = {
    title: faqH2M ? stripTags(faqH2M[1]).trim() : '',
    subtitle: faqPM ? faqPM[1].trim() : '',
  };

  for (let i = 0; i < faqQuestions.length; i++) {
    t.faq[`q${i + 1}`] = faqQuestions[i] || '';
    t.faq[`a${i + 1}`] = faqAnswers[i] || '';
  }

  // ── 18. Tech Section ──────────────────────────────────────────────────
  const techSection = sectionBetween(html, /<section class="tech-section"/, /<section class="final-cta"/);

  const techH2M = techSection.match(/<h2[^>]*>([\s\S]*?)<\/h2>/);
  const techPM = techSection.match(/class="section-header">\s*<h2[\s\S]*?<\/h2>\s*<p[^>]*>([^<]+)<\/p>/);
  const techTitles = allMatches(techSection, /class="tech-card">\s*<div class="tech-icon">[\s\S]*?<\/div>\s*<h3>([^<]+)<\/h3>/g);
  const techDescs = allMatches(techSection, /class="tech-card">[\s\S]*?<\/h3>\s*<p>([^<]+)<\/p>/g);

  t.tech = {
    title: techH2M ? stripTags(techH2M[1]).trim() : '',
    subtitle: techPM ? techPM[1].trim() : '',
    card1Title: techTitles[0] || '',
    card1Desc: techDescs[0] || '',
    card2Title: techTitles[1] || '',
    card2Desc: techDescs[1] || '',
    card3Title: techTitles[2] || '',
    card3Desc: techDescs[2] || '',
    card4Title: techTitles[3] || '',
    card4Desc: techDescs[3] || '',
  };

  // ── 19. Final CTA ─────────────────────────────────────────────────────
  const ctaSection = sectionBetween(html, /<section class="final-cta"/, /<\/main>/);

  const ctaH2M = ctaSection.match(/<h2[^>]*>([\s\S]*?)<\/h2>/);
  const ctaPM = ctaSection.match(/<h2[\s\S]*?<\/h2>\s*<p[^>]*>([^<]+)<\/p>/);
  const ctaBtnM = ctaSection.match(/class="btn btn-primary btn-lg[^"]*">\s*<svg[\s\S]*?<\/svg>\s*\n?\s*([^<]+)/);
  const ctaFounderM = ctaSection.match(/class="final-cta-founder[^"]*">([\s\S]*?)<\/p>/);

  t.cta = {
    title: ctaH2M ? stripTags(ctaH2M[1]).trim() : '',
    subtitle: ctaPM ? ctaPM[1].trim() : '',
    btn: ctaBtnM ? ctaBtnM[1].trim() : '',
    founder: ctaFounderM ? ctaFounderM[1].replace(/\s+/g, ' ').trim() : '',
  };

  // ── 20. Footer ────────────────────────────────────────────────────────
  const footerSection = sectionBetween(html, /<footer class="footer"/, /<\/footer>/);

  const communityH3M = footerSection.match(/class="newsletter-info">\s*<h3>([^<]+)<\/h3>/);
  const communityPM = footerSection.match(/class="newsletter-info">[\s\S]*?<p>([^<]+)<\/p>/);
  const starGithubM = footerSection.match(/class="btn btn-primary btn-sm"[^>]*>[\s\S]*?<\/svg>\s*\n?\s*([^<]+)\s*<\/a>/);
  const followXM = footerSection.match(/class="btn btn-outline btn-sm"[^>]*>[\s\S]*?<\/svg>\s*\n?\s*([^<]+)\s*<\/a>/);

  const taglineM = footerSection.match(/class="footer-tagline">([\s\S]*?)<\/p>/);
  const taglineText = taglineM ? taglineM[1].replace(/<br\s*\/?>/g, '\n').replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim() : '';

  const footerLinkGroups = [];
  const groupRe = /class="footer-links">\s*<h4>([^<]+)<\/h4>([\s\S]*?)(?=<\/div>\s*(?:<div class="footer-links">|<div class="footer-bottom"))/g;
  let gm;
  while ((gm = groupRe.exec(footerSection)) !== null) {
    footerLinkGroups.push({
      title: gm[1].trim(),
      links: allMatches(gm[2], /<a[^>]*>([^<]+)<\/a>/g),
    });
  }

  const copyrightM = footerSection.match(/class="footer-bottom">\s*<p>([\s\S]*?)<\/p>/);
  const copyrightText = copyrightM ? stripTags(copyrightM[1]).replace(/\s+/g, ' ').trim() : '';
  const statusM = footerSection.match(/class="footer-status">[\s\S]*?<span>([^<]+)<\/span>/);

  t.footer = {
    communityTitle: communityH3M ? communityH3M[1].trim() : '',
    communityDesc: communityPM ? communityPM[1].trim() : '',
    starGithub: starGithubM ? starGithubM[1].trim() : '',
    followX: followXM ? followXM[1].trim() : '',
    tagline: taglineText,
    copyright: copyrightText,
    allSystems: statusM ? statusM[1].trim() : '',
  };

  const groupKeys = ['product', 'download', 'guides', 'support', 'legal'];
  for (let i = 0; i < footerLinkGroups.length; i++) {
    const key = groupKeys[i] || `group${i + 1}`;
    t.footer[`${key}Title`] = footerLinkGroups[i].title;
    footerLinkGroups[i].links.forEach((link, j) => {
      t.footer[`${key}Link${j + 1}`] = link;
    });
  }

  // ── 21. Mobile sticky CTA ─────────────────────────────────────────────
  const mobileCTAM = html.match(/id="mobile-sticky-cta"[\s\S]*?class="btn[^"]*">\s*<svg[\s\S]*?<\/svg>\s*\n?\s*([^<]+)/);
  t.mobileCta = {
    btn: mobileCTAM ? mobileCTAM[1].trim() : '',
  };

  // ── 22. Cookie consent ────────────────────────────────────────────────
  const cookieSection = sectionBetween(html, /id="cookie-consent"/, /<script/);
  let cookieMsg = '';
  const cookieTextM = cookieSection.match(/class="cookie-content">\s*<p>([\s\S]*?)<\/p>/);
  if (cookieTextM) {
    cookieMsg = cookieTextM[1]
      .replace(/<a[^>]*>([^<]+)<\/a>/, '$1')
      .replace(/\s+/g, ' ')
      .trim();
  }
  const cookiePrivacyLinkM = cookieSection.match(/<a[^>]*>([^<]+)<\/a>/);
  const cookieAcceptM = cookieSection.match(/id="cookie-accept">([^<]+)<\/button>/);
  const cookieDismissM = cookieSection.match(/id="cookie-dismiss"[^>]*>([^<]+)<\/button>/);

  t.cookie = {
    message: cookieMsg,
    privacyLink: cookiePrivacyLinkM ? cookiePrivacyLinkM[1].trim() : '',
    accept: cookieAcceptM ? cookieAcceptM[1].trim() : '',
    dismiss: cookieDismissM ? cookieDismissM[1].trim() : '',
  };

  return t;
}

// ─── Count keys recursively ─────────────────────────────────────────────────

function countKeys(obj) {
  let count = 0;
  for (const key of Object.keys(obj)) {
    if (typeof obj[key] === 'object' && obj[key] !== null && !Array.isArray(obj[key])) {
      count += countKeys(obj[key]);
    } else {
      count++;
    }
  }
  return count;
}

function countEmpty(obj) {
  let count = 0;
  for (const key of Object.keys(obj)) {
    if (typeof obj[key] === 'object' && obj[key] !== null && !Array.isArray(obj[key])) {
      count += countEmpty(obj[key]);
    } else if (obj[key] === '') {
      count++;
    }
  }
  return count;
}

// ─── Main ───────────────────────────────────────────────────────────────────

function main() {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });

  console.log('SSvid Translation Extractor');
  console.log('==========================\n');

  const results = [];

  for (const lang of LANGUAGES) {
    const filePath = path.join(WEBSITE_DIR, lang.file);

    if (!fs.existsSync(filePath)) {
      console.log(`  [SKIP] ${lang.code}: file not found at ${filePath}`);
      continue;
    }

    const html = fs.readFileSync(filePath, 'utf8');
    const translations = extractTranslations(html);
    const totalKeys = countKeys(translations);
    const emptyKeys = countEmpty(translations);

    const outputPath = path.join(OUTPUT_DIR, `${lang.code}.json`);
    fs.writeFileSync(outputPath, JSON.stringify(translations, null, 2) + '\n', 'utf8');

    results.push({ code: lang.code, total: totalKeys, empty: emptyKeys });
    console.log(`  [OK] ${lang.code}: ${totalKeys} keys extracted (${emptyKeys} empty) -> src/i18n/${lang.code}.json`);
  }

  console.log('\n-- Summary ------------------------------------------');
  console.log(`  Languages processed: ${results.length}`);
  console.log(`  Keys per language:   ${results[0]?.total || 0}`);

  const withEmpty = results.filter(r => r.empty > 0);
  if (withEmpty.length > 0) {
    console.log('\n  Languages with empty keys:');
    for (const r of withEmpty) {
      console.log(`    ${r.code}: ${r.empty} empty`);
    }
  } else {
    console.log('  All keys populated across all languages.');
  }

  console.log('\nDone.');
}

main();
