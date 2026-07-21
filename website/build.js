#!/usr/bin/env node
/**
 * SSvid Landing Page — Static Site Builder
 * Zero dependencies. Pure Node.js.
 *
 * Features:
 *   {{t.key}}          — Translation lookup (dot notation)
 *   {{var}}             — Variable substitution
 *   {{> partial_name}}  — Include partial from _partials/
 *   {{#if var}}...{{/if}}           — Conditional block
 *   {{#unless var}}...{{/unless}}   — Inverse conditional
 *   {{#each items}}...{{/each}}     — Loop ({{.}} for current item)
 *
 * Usage: node build.js [--watch] [--minify]
 */

const fs = require('fs');
const path = require('path');

// ─── Config ────────────────────────────────────────────────────
const SRC = path.join(__dirname, 'src');
const DIST = path.join(__dirname, 'dist');
const TEMPLATES_DIR = path.join(SRC, 'templates');
const PARTIALS_DIR = path.join(TEMPLATES_DIR, '_partials');
const I18N_DIR = path.join(SRC, 'i18n');
const ASSETS_DIRS = ['css', 'js', 'assets'];
const BASE_URL = 'https://ssvid.app';
const OS_KEYWORDS = ['macos', 'windows', 'linux', 'iphone', 'ipad', 'ios', 'android', 'desktop', 'mobile'];
const SOURCE_KEYWORDS = ['youtube', 'tiktok', 'instagram', 'facebook', 'twitter', 'twitter/x', 'x', 'reddit', 'vimeo', 'dailymotion', 'soundcloud', 'pinterest'];

const SHOULD_MINIFY = !process.argv.includes('--no-minify');
const SHOULD_WATCH = process.argv.includes('--watch');

// ─── Languages ─────────────────────────────────────────────────
const LANGUAGES = [
  { code: 'en', name: 'English', locale: 'en_US', dir: 'ltr', isDefault: true },
  { code: 'vi', name: 'Tiếng Việt', locale: 'vi_VN', dir: 'ltr' },
  { code: 'ja', name: '日本語', locale: 'ja_JP', dir: 'ltr' },
  { code: 'ko', name: '한국어', locale: 'ko_KR', dir: 'ltr' },
  { code: 'zh', name: '中文', locale: 'zh_CN', dir: 'ltr' },
  { code: 'es', name: 'Español', locale: 'es_ES', dir: 'ltr' },
  { code: 'pt', name: 'Português', locale: 'pt_BR', dir: 'ltr' },
  { code: 'fr', name: 'Français', locale: 'fr_FR', dir: 'ltr' },
  { code: 'de', name: 'Deutsch', locale: 'de_DE', dir: 'ltr' },
  { code: 'id', name: 'Bahasa Indonesia', locale: 'id_ID', dir: 'ltr' },
  { code: 'th', name: 'ไทย', locale: 'th_TH', dir: 'ltr' },
  { code: 'tr', name: 'Türkçe', locale: 'tr_TR', dir: 'ltr' },
  { code: 'ru', name: 'Русский', locale: 'ru_RU', dir: 'ltr' },
  { code: 'ar', name: 'العربية', locale: 'ar_SA', dir: 'rtl' },
  { code: 'hi', name: 'हिन्दी', locale: 'hi_IN', dir: 'ltr' },
];

// Pages generated for ALL languages (fully translated: titles, headings, body, CTAs)
const I18N_PAGES = [
  'index.html',
  'download/macos.html', 'download/windows.html', 'download/linux.html',
];

// Pages generated English-only for now (i18n-ready templates, will promote when translations complete)
// These use {{t.*}} template vars but only render with English translations to avoid mixed-language UX.
const ENGLISH_ONLY_PAGES = [
  'download/index.html',
  'pricing.html',
  'privacy.html',
  'terms.html',
  'changelog.html',
  'how-to/download-youtube-videos.html', 'how-to/download-tiktok-videos.html',
  'how-to/download-instagram-videos.html', 'how-to/download-facebook-videos.html',
  'how-to/download-twitter-videos.html', 'how-to/download-reddit-videos.html',
  'how-to/download-vimeo-videos.html', 'how-to/download-soundcloud-music.html',
  'how-to/download-pinterest-videos.html', 'how-to/download-dailymotion-videos.html',
  'blog/download-tiktok-no-watermark.html', 'blog/download-youtube-playlist.html',
  'blog/private-instagram-download.html',
  'compare/vs-4k-downloader.html', 'compare/vs-online-converters.html',
  'guide.html',
];

// All i18n-capable pages (used for sitemap hreflang when translations are ready)
const ALL_I18N_CAPABLE = [...I18N_PAGES, ...ENGLISH_ONLY_PAGES];

// Utility pages are rendered from templates but intentionally excluded from sitemap/indexing.
const UTILITY_PAGES = [
  'account.html',
  'restore.html',
];

// Pages generated once (English only) — legacy glob pattern
const STATIC_PAGES_GLOB = [
  // Replaced by ENGLISH_ONLY_PAGES
];

// ─── Helpers ───────────────────────────────────────────────────

/** Deep get value from object by dot-notation key */
function deepGet(obj, keyPath) {
  return keyPath.split('.').reduce((o, k) => (o && o[k] !== undefined ? o[k] : undefined), obj);
}

/** Read file with cache */
const fileCache = new Map();
function readFile(filePath) {
  if (!fileCache.has(filePath)) {
    fileCache.set(filePath, fs.readFileSync(filePath, 'utf8'));
  }
  return fileCache.get(filePath);
}

/** Resolve partials recursively */
function resolvePartials(html) {
  return html.replace(/\{\{>\s*(\w+)\s*\}\}/g, (match, name) => {
    const partialPath = path.join(PARTIALS_DIR, `${name}.html`);
    if (!fs.existsSync(partialPath)) {
      console.warn(`  [WARN] Partial not found: ${name}`);
      return `<!-- partial "${name}" not found -->`;
    }
    // Recurse to resolve nested partials
    return resolvePartials(readFile(partialPath));
  });
}

/** Process conditionals: {{#if var}}...{{/if}} and {{#unless var}}...{{/unless}} */
function processConditionals(html, context) {
  // {{#if var}}...{{/if}}
  html = html.replace(/\{\{#if\s+(\S+?)\}\}([\s\S]*?)\{\{\/if\}\}/g, (match, key, content) => {
    const val = deepGet(context, key);
    return val ? content : '';
  });
  // {{#unless var}}...{{/unless}}
  html = html.replace(/\{\{#unless\s+(\S+?)\}\}([\s\S]*?)\{\{\/unless\}\}/g, (match, key, content) => {
    const val = deepGet(context, key);
    return val ? '' : content;
  });
  return html;
}

/** Process loops: {{#each items}}...{{/each}} */
function processLoops(html, context) {
  return html.replace(/\{\{#each\s+(\S+?)\}\}([\s\S]*?)\{\{\/each\}\}/g, (match, key, body) => {
    const arr = deepGet(context, key);
    if (!Array.isArray(arr)) return '';
    return arr.map((item, i) => {
      let result = body;
      if (typeof item === 'string') {
        result = result.replace(/\{\{\.\}\}/g, item);
      } else if (typeof item === 'object') {
        // Process conditionals within loop body using item properties
        result = result.replace(/\{\{#if\s+(\S+?)\}\}([\s\S]*?)\{\{\/if\}\}/g, (m, k, content) => {
          return item[k] ? content : '';
        });
        result = result.replace(/\{\{#unless\s+(\S+?)\}\}([\s\S]*?)\{\{\/unless\}\}/g, (m, k, content) => {
          return item[k] ? '' : content;
        });
        // Substitute item variables
        Object.keys(item).forEach(k => {
          result = result.replace(new RegExp(`\\{\\{${k}\\}\\}`, 'g'), item[k]);
        });
      }
      result = result.replace(/\{\{@index\}\}/g, String(i));
      return result;
    }).join('');
  });
}

/** Substitute all {{key}} and {{t.key}} variables */
function substituteVars(html, context) {
  return html.replace(/\{\{([^#/>][^}]*?)\}\}/g, (match, key) => {
    key = key.trim();
    const val = deepGet(context, key);
    if (val === undefined) {
      // Don't warn for JSON-LD content or JS template literals
      if (!key.startsWith('@') && !key.includes('"')) {
        // Only warn in verbose mode to avoid noise
      }
      return match; // Leave as-is if not found
    }
    return String(val);
  });
}

/** Basic HTML minification */
function minifyHTML(html) {
  if (!SHOULD_MINIFY) return html;
  return html
    .replace(/<!--(?!\[if)[\s\S]*?-->/g, '') // Remove comments (keep IE conditionals)
    .replace(/^\s+/gm, '') // Remove leading whitespace
    .replace(/\n\s*\n/g, '\n') // Collapse blank lines
    .replace(/>\s+</g, '> <'); // Reduce whitespace between tags (preserve single space)
}

/** Build context object for a given language */
function buildContext(lang, translations, pageMeta = {}) {
  const isDefault = lang.code === 'en';
  const langPrefix = isDefault ? '' : `/${lang.code}`;
  const canonical = `${BASE_URL}${langPrefix}${pageMeta.path || '/'}`;
  const assetPrefix = isDefault ? '' : '..';
  const pageId = pageMeta.page || '';

  const site = {
    url: BASE_URL,
    canonical,
    assetPrefix,
    title: translations.meta?.title || 'SSvid',
    description: translations.meta?.description || '',
    keywords: translations.meta?.keywords || '',
    ogTitle: translations.og?.title || translations.meta?.title || 'SSvid',
    ogDescription: translations.og?.description || translations.meta?.description || '',
    twitterTitle: translations.twitter?.title || translations.meta?.title || 'SSvid',
    twitterDescription: translations.twitter?.description || translations.meta?.description || '',
  };

  if (!isDefault) {
    site.ogTitle = site.title;
    site.twitterTitle = site.title;
    if (pageId === 'index') {
      site.description = stripPlatformMixingSentences(site.description);
      site.ogDescription = stripPlatformMixingSentences(site.ogDescription);
      site.twitterDescription = stripPlatformMixingSentences(site.twitterDescription);
    }
  }

  const copy = buildPageCopy(lang, translations, pageId);

  return {
    t: translations,
    lang: {
      code: lang.code,
      name: lang.name,
      locale: lang.locale,
      dir: lang.dir,
      isDefault,
      prefix: langPrefix,
    },
    site,
    copy,
    languages: LANGUAGES.map(l => ({
      code: l.code,
      name: l.name,
      href: l.isDefault ? '/' : `/${l.code}/`,
      active: l.code === lang.code ? 'active' : '',
      isRTL: l.dir === 'rtl',
    })),
    // Hreflang links (only for pages that exist in multiple languages)
    hreflangTags: (() => {
      const rawPage = pageMeta.page || '';
      const slug = (!rawPage || rawPage === 'index') ? '/' : `/${rawPage}`;
      const htmlPage = rawPage === 'index' ? 'index.html' : `${rawPage}.html`;
      const isMultiLang = I18N_PAGES.includes(htmlPage);

      if (!isMultiLang) {
        // English-only page — self-referencing hreflang only
        return `<link rel="alternate" hreflang="en" href="${BASE_URL}${slug}">\n  <link rel="alternate" hreflang="x-default" href="${BASE_URL}${slug}">`;
      }

      return LANGUAGES.map(l => {
        const href = l.isDefault ? `${BASE_URL}${slug}` : `${BASE_URL}/${l.code}${slug}`;
        return `<link rel="alternate" hreflang="${l.code}" href="${href}">`;
      }).concat([`<link rel="alternate" hreflang="x-default" href="${BASE_URL}${slug}">`]).join('\n  ');
    })(),
    // Build metadata
    build: {
      timestamp: new Date().toISOString(),
      version: getVersion(),
      releaseDate: getReleaseDate(),
      heroVideoWebm: fs.existsSync(path.join(__dirname, 'src/assets/videos/hero-demo.webm')),
      heroVideoMp4: fs.existsSync(path.join(__dirname, 'src/assets/videos/hero-demo.mp4')),
      heroVideoAvailable: fs.existsSync(path.join(__dirname, 'src/assets/videos/hero-demo.webm')) || fs.existsSync(path.join(__dirname, 'src/assets/videos/hero-demo.mp4')),
    },
    ...pageMeta,
  };
}

function buildPageCopy(lang, translations, pageId) {
  if (!pageId.startsWith('download/')) {
    return {};
  }

  const platform = pageId.split('/')[1];
  const source = translations.dl?.[platform];
  if (!source) {
    return {};
  }

  const sanitizeDownloadCopy = value => lang.isDefault
    ? value
    : stripPlatformMixingSentences(value, { removeSourceOnly: true });

  return {
    title: source.pageTitle || '',
    description: sanitizeDownloadCopy(source.pageDesc || ''),
    heroSubtitle: sanitizeDownloadCopy(source.heroSubtitle || ''),
  };
}

/** Read version from version.json */
function getVersion() {
  try {
    const vj = JSON.parse(fs.readFileSync(path.join(__dirname, 'version.json'), 'utf8'));
    return vj.version || '0.0.0';
  } catch {
    return '0.0.0';
  }
}

/** Read release date from version.json */
function getReleaseDate() {
  try {
    const vj = JSON.parse(fs.readFileSync(path.join(__dirname, 'version.json'), 'utf8'));
    return vj.release_date || '';
  } catch {
    return '';
  }
}

/** Load translations for a language, falling back to English */
function loadTranslations(langCode) {
  const enPath = path.join(I18N_DIR, 'en.json');
  const langPath = path.join(I18N_DIR, `${langCode}.json`);

  let en = {};
  let lang = {};

  if (fs.existsSync(enPath)) {
    en = JSON.parse(readFile(enPath));
  }
  if (langCode !== 'en' && fs.existsSync(langPath)) {
    lang = JSON.parse(readFile(langPath));
  }

  // Deep merge: lang overrides en
  return deepMerge(en, lang);
}

/** Deep merge two objects */
function deepMerge(target, source) {
  const result = { ...target };
  for (const key of Object.keys(source)) {
    if (source[key] && typeof source[key] === 'object' && !Array.isArray(source[key])) {
      result[key] = deepMerge(result[key] || {}, source[key]);
    } else {
      result[key] = source[key];
    }
  }
  return result;
}

function splitSentences(value) {
  return String(value || '')
    .split(/(?<=[.!?。！？।॥؟])\s*/)
    .map(part => part.trim())
    .filter(Boolean);
}

function containsAny(text, keywords) {
  const lower = String(text || '').toLowerCase();
  return keywords.some(keyword => {
    if (keyword === 'x') return /\b(?:x|twitter\/x)\b/i.test(text);
    return lower.includes(keyword);
  });
}

function stripPlatformMixingSentences(value, options = {}) {
  const { removeSourceOnly = false } = options;
  const original = String(value || '').trim();
  const sentences = splitSentences(original);
  if (!sentences.length) return value;

  const kept = sentences.filter(sentence => {
    const hasOs = containsAny(sentence, OS_KEYWORDS);
    const hasSource = containsAny(sentence, SOURCE_KEYWORDS);
    if (removeSourceOnly && hasSource) return false;
    if (hasOs && hasSource) return false;
    return true;
  });

  const normalized = kept.join(' ').replace(/\s+([.!?。！？।॥؟])/g, '$1').trim();
  if (normalized) return normalized;

  if (removeSourceOnly && containsAny(original, SOURCE_KEYWORDS)) {
    const trimmedAtSeparator = original.split(/\s+[—–-]\s+/)[0].trim();
    if (trimmedAtSeparator && trimmedAtSeparator !== original) {
      return trimmedAtSeparator;
    }
  }

  return value;
}

/**
 * Parse frontmatter block from template:
 *   <!--@page
 *     title: ...
 *     description: ...
 *     canonical: /download/macos
 *     ogTitle: ...
 *     ogDescription: ...
 *     keywords: ...
 *   -->
 * Returns { meta, body }. `meta` is an object; `body` is the template with the
 * frontmatter block stripped.
 */
function parsePageMeta(html) {
  const m = html.match(/^\s*<!--@page\s*([\s\S]*?)\s*-->/);
  if (!m) return { meta: {}, body: html };
  const meta = {};
  const lines = m[1].split('\n');
  for (const raw of lines) {
    const line = raw.trim();
    if (!line) continue;
    const sep = line.indexOf(':');
    if (sep === -1) continue;
    const key = line.slice(0, sep).trim();
    const val = line.slice(sep + 1).trim();
    meta[key] = val;
  }
  const body = html.slice(m[0].length);
  return { meta, body };
}

/** Render a template with full pipeline */
function render(templatePath, context) {
  let html = readFile(templatePath);
  const parsed = parsePageMeta(html);
  if (Object.keys(parsed.meta).length) {
    // Allow translation lookups inside meta values: title: {{t.download.macos.title}}
    const resolved = {};
    for (const [k, v] of Object.entries(parsed.meta)) {
      resolved[k] = substituteVars(v, context);
    }
    context.page = { ...(context.page || {}), ...resolved };
    // Auto-derive canonical URL when path is provided (prepend lang prefix for i18n pages)
    if (resolved.canonical) {
      const langPrefix = context.lang.isDefault ? '' : `/${context.lang.code}`;
      context.site = {
        ...context.site,
        canonical: resolved.canonical.startsWith('http')
          ? resolved.canonical
          : BASE_URL + langPrefix + resolved.canonical,
      };
    }
    // Override site.title / description / keywords for head partial reuse
    if (resolved.title) context.site = { ...context.site, title: resolved.title };
    if (resolved.description) context.site = { ...context.site, description: resolved.description };
    if (resolved.keywords) context.site = { ...context.site, keywords: resolved.keywords };
  }
  html = parsed.body;
  html = resolvePartials(html);
  html = processLoops(html, context);
  html = processConditionals(html, context);
  html = substituteVars(html, context);
  html = minifyHTML(html);
  return html;
}

/** Write file, creating directories as needed */
function writeOutput(filePath, content) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, content, 'utf8');
}

/** Glob-like pattern matching for static pages */
function resolveStaticPages() {
  const pages = [];
  for (const pattern of STATIC_PAGES_GLOB) {
    if (pattern.includes('*')) {
      const dir = path.join(TEMPLATES_DIR, path.dirname(pattern));
      if (fs.existsSync(dir)) {
        const ext = path.extname(pattern);
        fs.readdirSync(dir)
          .filter(f => f.endsWith(ext) && !f.startsWith('_'))
          .forEach(f => pages.push(path.join(path.dirname(pattern), f)));
      }
    } else {
      const fullPath = path.join(TEMPLATES_DIR, pattern);
      if (fs.existsSync(fullPath)) {
        pages.push(pattern);
      }
    }
  }
  return pages;
}

/** Copy static assets (css, js, fonts, images) */
function copyAssets() {
  for (const dir of ASSETS_DIRS) {
    const srcDir = path.join(SRC, dir);
    const destDir = path.join(DIST, dir === 'assets' ? '' : dir);

    if (!fs.existsSync(srcDir)) continue;

    copyDirRecursive(srcDir, destDir);
  }

  // Copy root-level static files
  const rootFiles = [
    'CNAME', 'robots.txt', 'version.json', 'manifest.json',
    'site.webmanifest', '.nojekyll', '_headers',
    'd13ff0a680a641a1a82fb5c927aea2d0.txt', // IndexNow verification key
  ];
  for (const file of rootFiles) {
    const src = path.join(__dirname, file);
    if (fs.existsSync(src)) {
      fs.copyFileSync(src, path.join(DIST, file));
    }
  }

  // Copy Google Search Console verification file (google*.html) if present
  for (const entry of fs.readdirSync(__dirname, { withFileTypes: true })) {
    if (entry.isFile() && entry.name.startsWith('google') && entry.name.endsWith('.html')) {
      fs.copyFileSync(path.join(__dirname, entry.name), path.join(DIST, entry.name));
    }
  }
}

/** Legacy compat: mirror styles.css and main.js to root paths expected by un-migrated pages */
function writeLegacyAliases() {
  const cssSrc = path.join(SRC, 'css', 'styles.css');
  const jsSrc = path.join(SRC, 'js', 'main.js');
  if (fs.existsSync(cssSrc)) {
    const css = SHOULD_MINIFY
      ? minifyCSS(fs.readFileSync(cssSrc, 'utf8'))
      : fs.readFileSync(cssSrc, 'utf8');
    fs.writeFileSync(path.join(DIST, 'styles.css'), css);
  }
  if (fs.existsSync(jsSrc)) {
    const js = SHOULD_MINIFY
      ? minifyJS(fs.readFileSync(jsSrc, 'utf8'))
      : fs.readFileSync(jsSrc, 'utf8');
    // Legacy pages reference script.js — provide both names
    fs.writeFileSync(path.join(DIST, 'script.js'), js);
  }
}

/** Copy legacy static HTML pages (not yet migrated to template system) */
function copyLegacyPages() {
  const legacyPages = [
    '404.html',
    'launch.html',
  ];
  const legacyDirs = ['payment']; // download/, how-to/ now template-migrated
  const legacyAssets = [
    'launch.js',
    'payment/success.js',
  ];

  const copied = [];
  for (const file of legacyPages) {
    const src = path.join(__dirname, file);
    if (fs.existsSync(src)) {
      fs.copyFileSync(src, path.join(DIST, file));
      copied.push(file);
    }
  }
  for (const dir of legacyDirs) {
    const src = path.join(__dirname, dir);
    if (!fs.existsSync(src)) continue;
    for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
      if (entry.isFile() && entry.name.endsWith('.html')) {
        fs.mkdirSync(path.join(DIST, dir), { recursive: true });
        fs.copyFileSync(path.join(src, entry.name), path.join(DIST, dir, entry.name));
        copied.push(`${dir}/${entry.name}`);
      }
    }
  }
  for (const asset of legacyAssets) {
    const src = path.join(__dirname, asset);
    if (!fs.existsSync(src)) continue;
    writeOutput(path.join(DIST, asset), fs.readFileSync(src, 'utf8'));
    copied.push(asset);
  }
  return copied;
}

/** Generate redirect HTML pages for old indexed URLs (SEO recovery).
 *  GitHub Pages doesn't support 301 redirects, so we use
 *  <meta http-equiv="refresh"> + canonical + JS fallback.
 *  Google treats meta-refresh 0 as a 301 equivalent for ranking purposes. */
function generateRedirects() {
  const REDIRECTS = {
    // Old numbered language paths → new equivalents
    'en82/index.html': '/',
    'en81/index.html': '/',
    'en80/index.html': '/',
    'en46/index.html': '/',
    'en/index.html': '/',
    // Old service pages → new how-to guides
    'en81/youtube-to-mp3.html': '/how-to/download-youtube-videos',
    'en81/youtube-to-mp4.html': '/how-to/download-youtube-videos',
    'en/youtube-downloader.html': '/how-to/download-youtube-videos',
    'en80/youtube-downloader.html': '/how-to/download-youtube-videos',
    'en81/youtube-downloader.html': '/how-to/download-youtube-videos',
    'en82/youtube-downloader.html': '/how-to/download-youtube-videos',
    'en81/tiktok-downloader.html': '/how-to/download-tiktok-videos',
    'en81/instagram-downloader.html': '/how-to/download-instagram-videos',
    'en81/facebook-downloader.html': '/how-to/download-facebook-videos',
    'en81/twitter-downloader.html': '/how-to/download-twitter-videos',
    'en81/linkedin-video-downloader.html': '/',
    'en82/9gag-downloader.html': '/',
    // Old utility pages → new equivalents
    'en82/contact-us.html': '/',
    'en46/privacy-policy.html': '/privacy',
    'en81/privacy-policy.html': '/privacy',
    'en82/privacy-policy.html': '/privacy',
    'en/terms-of-service.html': '/terms',
  };

  let count = 0;
  for (const [oldPath, newUrl] of Object.entries(REDIRECTS)) {
    const fullUrl = BASE_URL + newUrl;
    const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><title>Redirecting…</title><link rel="canonical" href="${fullUrl}"><meta http-equiv="refresh" content="0;url=${fullUrl}"><meta name="robots" content="noindex"></head><body><p>Moved to <a href="${fullUrl}">${fullUrl}</a></p><script>window.location.replace("${fullUrl}")</script></body></html>`;
    writeOutput(path.join(DIST, oldPath), html);
    count++;
  }
  return count;
}

/** Basic CSS minification */
function minifyCSS(css) {
  return css
    .replace(/\/\*[\s\S]*?\*\//g, '') // Remove comments
    .replace(/\s*([{}:;,>+~])\s*/g, '$1') // Whitespace around symbols
    .replace(/;}/g, '}') // Drop trailing semicolons
    .replace(/\s+/g, ' ') // Collapse whitespace
    .trim();
}

/** Basic JS minification (whitespace + comments only — safe) */
function minifyJS(js) {
  return js
    .replace(/^\s*\/\/[^\n]*$/gm, '') // Comment-only lines (won't break URLs in strings)
    .replace(/\/\*[\s\S]*?\*\//g, '') // Block comments
    .replace(/^\s+/gm, '') // Leading whitespace
    .replace(/\n\s*\n/g, '\n'); // Blank lines
}

/** Recursively copy directory */
function copyDirRecursive(src, dest) {
  fs.mkdirSync(dest, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);
    if (entry.isDirectory()) {
      copyDirRecursive(srcPath, destPath);
    } else if (SHOULD_MINIFY && entry.name.endsWith('.css')) {
      fs.writeFileSync(destPath, minifyCSS(fs.readFileSync(srcPath, 'utf8')));
    } else if (SHOULD_MINIFY && entry.name.endsWith('.js') && !entry.name.endsWith('.min.js')) {
      fs.writeFileSync(destPath, minifyJS(fs.readFileSync(srcPath, 'utf8')));
    } else {
      fs.copyFileSync(srcPath, destPath);
    }
  }
}

/** Generate sitemap.xml */
function generateSitemap(generatedPages) {
  const today = new Date().toISOString().split('T')[0];

  let xml = '<?xml version="1.0" encoding="UTF-8"?>\n';
  xml += '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"\n';
  xml += '        xmlns:xhtml="http://www.w3.org/1999/xhtml">\n';

  // i18n pages — with full hreflang clusters (only fully-translated pages)
  for (const page of I18N_PAGES) {
    const slug = page.replace(/\.html$/, '').replace(/index$/, '');
    const isHome = page === 'index.html';
    const basePriority = isHome ? '1.0' : '0.9';
    const altPriority = isHome ? '0.9' : '0.85';

    for (const lang of LANGUAGES) {
      const loc = lang.isDefault
        ? `${BASE_URL}/${slug}`
        : `${BASE_URL}/${lang.code}/${slug}`;
      xml += '  <url>\n';
      xml += `    <loc>${loc}</loc>\n`;
      for (const l of LANGUAGES) {
        const href = l.isDefault
          ? `${BASE_URL}/${slug}`
          : `${BASE_URL}/${l.code}/${slug}`;
        xml += `    <xhtml:link rel="alternate" hreflang="${l.code}" href="${href}"/>\n`;
      }
      xml += `    <xhtml:link rel="alternate" hreflang="x-default" href="${BASE_URL}/${slug}"/>\n`;
      xml += `    <lastmod>${today}</lastmod>\n`;
      xml += `    <changefreq>weekly</changefreq>\n`;
      xml += `    <priority>${lang.isDefault ? basePriority : altPriority}</priority>\n`;
      xml += '  </url>\n';
    }
  }

  // Static pages (English only)
  for (const page of generatedPages) {
    const urlPath = page.replace(/\.html$/, '').replace(/index$/, '');
    const loc = `${BASE_URL}/${urlPath}`;
    let priority = '0.6';
    if (page.startsWith('download/')) priority = '0.9';
    else if (page === 'guide.html') priority = '0.85';
    else if (page.startsWith('how-to/')) priority = '0.8';
    else if (page.startsWith('compare/')) priority = '0.7';
    else if (page.startsWith('blog/')) priority = '0.75';
    xml += '  <url>\n';
    xml += `    <loc>${loc}</loc>\n`;
    xml += `    <lastmod>${today}</lastmod>\n`;
    xml += `    <changefreq>monthly</changefreq>\n`;
    xml += `    <priority>${priority}</priority>\n`;
    xml += '  </url>\n';
  }

  xml += '</urlset>\n';
  return xml;
}

// ─── Main Build ────────────────────────────────────────────────

function build() {
  const startTime = Date.now();
  fileCache.clear();

  console.log('\n  SSvid Landing Page Builder');
  console.log('  ─────────────────────────\n');

  // Clean dist
  if (fs.existsSync(DIST)) {
    fs.rmSync(DIST, { recursive: true });
  }
  fs.mkdirSync(DIST, { recursive: true });

  let pageCount = 0;
  const staticPages = [];

  // 1. Build fully-translated i18n pages (all languages)
  for (const page of I18N_PAGES) {
    const templatePath = path.join(TEMPLATES_DIR, page);
    if (!fs.existsSync(templatePath)) {
      console.warn(`  [WARN] Template not found: ${page}`);
      continue;
    }

    for (const lang of LANGUAGES) {
      const translations = loadTranslations(lang.code);
      const context = buildContext(lang, translations, { page: page.replace('.html', '') });
      const html = render(templatePath, context);

      const outputPath = lang.isDefault
        ? path.join(DIST, page)
        : path.join(DIST, lang.code, page);

      writeOutput(outputPath, html);
      pageCount++;
    }
    console.log(`  [i18n] ${page} × ${LANGUAGES.length} languages`);
  }

  // 2. Build English-only content pages (i18n-ready templates, English translations only)
  const enTranslations = loadTranslations('en');
  const enLang = LANGUAGES.find(l => l.code === 'en');

  for (const page of ENGLISH_ONLY_PAGES) {
    const templatePath = path.join(TEMPLATES_DIR, page);
    if (!fs.existsSync(templatePath)) {
      console.warn(`  [WARN] Template not found: ${page}`);
      continue;
    }

    const context = buildContext(enLang, enTranslations, { page: page.replace('.html', '') });
    const html = render(templatePath, context);

    writeOutput(path.join(DIST, page), html);
    staticPages.push(page);
    pageCount++;
  }
  if (ENGLISH_ONLY_PAGES.length) {
    console.log(`  [content] ${ENGLISH_ONLY_PAGES.length} English-only pages`);
  }

  // 2b. Build English-only utility pages (rendered from templates, excluded from sitemap)
  for (const page of UTILITY_PAGES) {
    const templatePath = path.join(TEMPLATES_DIR, page);
    if (!fs.existsSync(templatePath)) {
      console.warn(`  [WARN] Utility template not found: ${page}`);
      continue;
    }

    const context = buildContext(enLang, enTranslations, { page: page.replace('.html', '') });
    const html = render(templatePath, context);

    writeOutput(path.join(DIST, page), html);
    pageCount++;
  }
  if (UTILITY_PAGES.length) {
    console.log(`  [utility] ${UTILITY_PAGES.length} utility pages`);
  }

  // 3. Build legacy static pages (glob patterns)
  const resolvedStatic = resolveStaticPages();
  for (const page of resolvedStatic) {
    const templatePath = path.join(TEMPLATES_DIR, page);
    const context = buildContext(enLang, enTranslations, { page: page.replace('.html', '') });
    const html = render(templatePath, context);

    writeOutput(path.join(DIST, page), html);
    staticPages.push(page);
    pageCount++;
  }
  if (resolvedStatic.length) {
    console.log(`  [static] ${resolvedStatic.length} pages`);
  }

  // 3. Copy assets
  copyAssets();
  console.log('  [assets] Copied css, js, fonts, images');

  // 3b. Copy legacy static HTML pages (not yet migrated to templates)
  const legacyPages = copyLegacyPages();
  if (legacyPages.length) {
    writeLegacyAliases();
    // Add legacy pages to sitemap (excluding utility pages like 404, launch, restore, payment)
    const sitemapWorthy = legacyPages.filter(p =>
      !p.startsWith('404') && !p.startsWith('launch') && !p.startsWith('restore') && !p.startsWith('payment/') && !p.startsWith('account')
    );
    staticPages.push(...sitemapWorthy);
    pageCount += legacyPages.length;
    console.log(`  [legacy] Copied ${legacyPages.length} static pages + CSS/JS aliases`);
  }

  // 3c. Generate 301-style redirects for old indexed URLs (SEO recovery)
  const redirectCount = generateRedirects();
  if (redirectCount) {
    console.log(`  [redirects] ${redirectCount} old URL redirects`);
  }

  // 4. Generate sitemap
  const sitemap = generateSitemap(staticPages);
  writeOutput(path.join(DIST, 'sitemap.xml'), sitemap);
  console.log('  [sitemap] Generated sitemap.xml');

  // 5. Copy service worker (needs to be at root)
  // Cache name = version + build timestamp (epoch seconds) to bust stale caches
  // on every dev build, not just on version bump.
  const swSrc = path.join(SRC, 'sw.js');
  if (fs.existsSync(swSrc)) {
    const cacheStamp = `ssvid-v${getVersion()}-${Math.floor(Date.now() / 1000)}`;
    const swContent = readFile(swSrc).replace(
      /CACHE_NAME\s*=\s*'[^']*'/,
      `CACHE_NAME = '${cacheStamp}'`
    );
    writeOutput(path.join(DIST, 'sw.js'), swContent);
    console.log(`  [sw] Service worker (cache: ${cacheStamp})`);
  }

  const elapsed = Date.now() - startTime;
  console.log(`\n  Done! ${pageCount} pages in ${elapsed}ms\n`);

  // Post-build verification — NEVER skip
  verify();
}

// ─── Post-Build Verification ──────────────────────────────────
// Automated safety net. Build FAILS if any check fails.
// This exists because a regex bug in minifyJS once killed all JS
// in production — no amount of HTTP 200 checks would catch that.

function verify() {
  const vm = require('vm');
  const errors = [];
  const warnings = [];

  // 1. JS syntax validation — parse every .js in dist/
  const jsFiles = [];
  function findJS(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) findJS(full);
      else if (entry.name.endsWith('.js')) jsFiles.push(full);
    }
  }
  findJS(DIST);

  for (const file of jsFiles) {
    const code = fs.readFileSync(file, 'utf8');
    try {
      new vm.Script(code, { filename: file });
    } catch (e) {
      errors.push(`JS SYNTAX ERROR in ${path.relative(DIST, file)}: ${e.message}`);
    }
  }

  // 2. URL integrity — check no truncated URLs (https: without //)
  for (const file of jsFiles) {
    const code = fs.readFileSync(file, 'utf8');
    const truncated = code.match(/'https?:\s*$/gm) || code.match(/"https?:\s*$/gm);
    if (truncated) {
      errors.push(`TRUNCATED URL in ${path.relative(DIST, file)}: ${truncated[0]}`);
    }
  }

  // 3. Template leak — no unresolved {{}} in any HTML
  const htmlFiles = [];
  function findHTML(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) findHTML(full);
      else if (entry.name.endsWith('.html')) htmlFiles.push(full);
    }
  }
  findHTML(DIST);

  for (const file of htmlFiles) {
    const html = fs.readFileSync(file, 'utf8');
    const leaks = html.match(/\{\{[^}]+\}\}/g);
    if (leaks) {
      const unique = [...new Set(leaks)].slice(0, 5);
      errors.push(`TEMPLATE LEAK in ${path.relative(DIST, file)}: ${unique.join(', ')}`);
    }
  }

  // 4. Homepage structural check — critical sections must exist
  const homepage = path.join(DIST, 'index.html');
  if (fs.existsSync(homepage)) {
    const html = fs.readFileSync(homepage, 'utf8');
    const required = [
      ['navbar', 'class="navbar"'],
      ['hero section', 'id="hero"'],
      ['features section', 'id="features"'],
      ['pricing section', 'id="pricing"'],
      ['FAQ section', 'id="faq"'],
      ['footer', 'class="footer"'],
      ['schema markup', 'application/ld+json'],
      ['hreflang', 'hreflang='],
      ['canonical', 'rel="canonical"'],
    ];
    for (const [name, pattern] of required) {
      if (!html.includes(pattern)) {
        errors.push(`MISSING ${name} in homepage (expected: ${pattern})`);
      }
    }
  } else {
    errors.push('MISSING homepage: dist/index.html not found');
  }

  // 5. CSS sanity — files must not be empty or trivially small
  function findCSS(dir) {
    const files = [];
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) files.push(...findCSS(full));
      else if (entry.name.endsWith('.css')) files.push(full);
    }
    return files;
  }
  for (const file of findCSS(DIST)) {
    const size = fs.statSync(file).size;
    if (size < 100) {
      warnings.push(`CSS file suspiciously small: ${path.relative(DIST, file)} (${size}B)`);
    }
  }

  // 6. Tracking regression guard — banned trackers must never reappear in dist/
  const bannedPatterns = [
    ['Google Tag Manager', /googletagmanager\.com/i],
    ['Google Analytics', /google-analytics\.com/i],
    ['GA bootstrap', /gtag\/js/i],
    ['GA measurement ID', /G-ZTHSEN0SZ3/i],
    ['window.gtag runtime', /window\.gtag/i],
    ['analytics event beacon', /api\/v1\/analytics\/events/i],
  ];
  const verifyFiles = [...new Set([...htmlFiles, ...jsFiles, ...findCSS(DIST)])];
  for (const file of verifyFiles) {
    const content = fs.readFileSync(file, 'utf8');
    for (const [label, pattern] of bannedPatterns) {
      if (pattern.test(content)) {
        errors.push(`BANNED TRACKER MATCH in ${path.relative(DIST, file)}: ${label}`);
      }
    }
  }

  // 7. Trust/commercial copy assertions — prevent old contradictory copy from returning
  const contentAssertions = [
    {
      file: 'index.html',
      mustContain: [
        'og:image:alt',
        'twitter:image:alt',
        'iPhone',
        'Android',
        'feature-platform-list',
      ],
      mustNotMatch: [],
    },
    {
      file: 'privacy.html',
      mustContain: [
        'analytics cookies or advertising cookies',
        'Cloudflare cookies',
        'Local browser storage',
      ],
      mustNotMatch: [],
    },
    {
      file: 'terms.html',
      mustContain: [
        '5 downloads per day',
        '30-day money-back guarantee',
        'Payments are processed securely by',
      ],
      mustNotMatch: [
        ['outdated free plan limit', /3 downloads per day/i],
        ['outdated refund window', /7[- ]day/i],
        ['unsupported crypto checkout copy', /cryptocurrenc/i],
      ],
    },
    {
      // W1.2/W1.3 magic-link flow: account.html now issues a single-use email
      // link instead of returning the portal URL directly. Verifier text moved
      // from "Open billing portal" to "Send me the link" / "Manage Subscription".
      file: 'account.html',
      mustContain: ['noindex, nofollow', 'Manage Subscription', 'Send me the link'],
      mustNotMatch: [],
    },
    {
      // restore.html also moved to magic-link flow.
      file: 'restore.html',
      mustContain: ['noindex, nofollow', 'Restore your license', 'Send me the link'],
      mustNotMatch: [],
    },
    {
      file: 'launch.html',
      mustContain: ['launch.js'],
      mustNotMatch: [],
    },
    {
      file: 'payment/success.html',
      mustContain: ['success.js'],
      mustNotMatch: [],
    },
    {
      file: 'site.webmanifest',
      mustContain: [
        '"name": "SSvid Video Downloader"',
        'iPhone, and Android',
      ],
      mustNotMatch: [],
    },
  ];

  for (const assertion of contentAssertions) {
    const file = path.join(DIST, assertion.file);
    if (!fs.existsSync(file)) {
      errors.push(`MISSING critical page: ${assertion.file}`);
      continue;
    }
    const content = fs.readFileSync(file, 'utf8');
    for (const snippet of assertion.mustContain) {
      if (!content.includes(snippet)) {
        errors.push(`MISSING REQUIRED COPY in ${assertion.file}: ${snippet}`);
      }
    }
    for (const [label, pattern] of assertion.mustNotMatch) {
      if (pattern.test(content)) {
        errors.push(`OUTDATED COPY in ${assertion.file}: ${label}`);
      }
    }
  }

  const requiredStaticAssets = [
    'launch.js',
    'payment/success.js',
  ];
  for (const relPath of requiredStaticAssets) {
    if (!fs.existsSync(path.join(DIST, relPath))) {
      errors.push(`MISSING legacy support asset in dist: ${relPath}`);
    }
  }

  const forbiddenRootFiles = [
    'account.html',
    'changelog.html',
    'guide.html',
    'index.html',
    'pricing.html',
    'privacy.html',
    'restore.html',
    'script.js',
    'sitemap.xml',
    'styles.css',
    'sw.js',
    'terms.html',
    'favicon-16.png',
    'favicon-32.png',
    'favicon.svg',
    'logo.png',
    'og-image.png',
  ];
  for (const filename of forbiddenRootFiles) {
    if (fs.existsSync(path.join(__dirname, filename))) {
      errors.push(`FORBIDDEN root mirror still present: ${filename}`);
    }
  }

  const forbiddenRootDirs = [
    'ar',
    'blog',
    'compare',
    'css',
    'de',
    'download',
    'en',
    'en46',
    'en80',
    'en81',
    'en82',
    'es',
    'fonts',
    'fr',
    'hi',
    'how-to',
    'id',
    'ja',
    'js',
    'ko',
    'pt',
    'ru',
    'th',
    'tr',
    'vi',
    'zh',
  ];
  for (const dirname of forbiddenRootDirs) {
    if (fs.existsSync(path.join(__dirname, dirname))) {
      errors.push(`FORBIDDEN root mirror directory still present: ${dirname}/`);
    }
  }

  // Report
  if (warnings.length) {
    console.log(`  [verify] ⚠ ${warnings.length} warning(s):`);
    warnings.forEach(w => console.log(`    → ${w}`));
  }

  if (errors.length) {
    console.error(`\n  ✖ BUILD VERIFICATION FAILED — ${errors.length} error(s):\n`);
    errors.forEach(e => console.error(`    ✖ ${e}`));
    console.error('\n  Build output is UNSAFE for deployment. Fix errors and rebuild.\n');
    process.exit(1);
  }

  console.log(`  [verify] ✓ ${jsFiles.length} JS, ${htmlFiles.length} HTML — all checks passed`);
}

// ─── Watch Mode ────────────────────────────────────────────────

function watch() {
  build();
  console.log('  Watching for changes...\n');

  let debounce = null;
  const rebuild = () => {
    clearTimeout(debounce);
    debounce = setTimeout(() => {
      console.log('  [rebuild] Change detected...');
      build();
    }, 200);
  };

  // Watch src/ directory
  fs.watch(SRC, { recursive: true }, rebuild);
  // Watch root config files
  ['version.json', 'CNAME', 'robots.txt'].forEach(f => {
    const p = path.join(__dirname, f);
    if (fs.existsSync(p)) fs.watch(p, rebuild);
  });
}

// ─── Entry Point ───────────────────────────────────────────────

if (SHOULD_WATCH) {
  watch();
} else {
  build();
}
