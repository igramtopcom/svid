#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const DIST = path.join(ROOT, 'dist');
const DOCS = path.join(ROOT, 'docs');
const TODAY = new Date().toISOString().slice(0, 10);
const SCORECARD_LATEST = path.join(DOCS, 'landing-scorecard-latest.md');
const SCORECARD_DATED = path.join(DOCS, `landing-scorecard-${TODAY}-baseline.md`);
const FORBIDDEN_CLAIMS = readListFile(path.join(DOCS, 'forbidden-claims.txt'));
const TRACKER_WHITELIST = readListFile(path.join(DOCS, 'tracker-whitelist.txt'));
const METADATA_EXCEPTIONS = new Set(readListFile(path.join(DOCS, 'metadata-exceptions.txt')));

const OS_KEYWORDS = ['macos', 'windows', 'linux', 'iphone', 'ipad', 'android', 'desktop', 'mobile'];
const SOURCE_KEYWORDS = ['youtube', 'tiktok', 'instagram', 'facebook', 'twitter', 'x', 'reddit', 'vimeo', 'dailymotion', 'soundcloud', 'pinterest'];
const TRUST_SENSITIVE_PATTERNS = [
  { label: 'virus-free', pattern: /\bvirus[- ]free\b/i },
  { label: 'open-source engine', pattern: /\bopen[- ]source engine\b/i },
  { label: '1000+ platform claim', pattern: /\b1000\+\s+(sites|platforms)\b/i },
  { label: 'fastest claim', pattern: /\bfastest\b/i },
];
const TRACKER_PATTERNS = [
  { label: 'Google Tag Manager', pattern: /googletagmanager\.com/i },
  { label: 'Google Analytics', pattern: /google-analytics\.com/i },
  { label: 'GA bootstrap', pattern: /gtag\/js/i },
  { label: 'GA measurement ID', pattern: /G-ZTHSEN0SZ3/i },
  { label: 'window.gtag runtime', pattern: /window\.gtag/i },
  { label: 'analytics event beacon', pattern: /api\/v1\/analytics\/events/i },
  { label: 'Segment', pattern: /cdn\.segment\.com|segment\.io/i },
  { label: 'Mixpanel', pattern: /mixpanel/i },
  { label: 'Hotjar', pattern: /hotjar/i },
  { label: 'FullStory', pattern: /fullstory/i },
];
const LOCALE_CODES = ['ar', 'de', 'es', 'fr', 'hi', 'id', 'ja', 'ko', 'pt', 'ru', 'th', 'tr', 'vi', 'zh'];

main();

function main() {
  ensureDir(DOCS);
  const htmlFiles = listFiles(DIST, file => file.endsWith('.html'))
    .map(file => path.relative(DIST, file).replaceAll(path.sep, '/'))
    .filter(file => !/hero-(mobile-cards|replica)\.html$/i.test(file))
    .filter(file => !/^google[a-z0-9]+\.html$/i.test(file));

  const pages = htmlFiles.map(file => {
    const fullPath = path.join(DIST, file);
    const html = fs.readFileSync(fullPath, 'utf8');
    return {
      file,
      html,
      title: extractTitle(html),
      ogTitle: extractMeta(html, 'property', 'og:title'),
      twitterTitle: extractMeta(html, 'name', 'twitter:title'),
      description: extractMeta(html, 'name', 'description'),
      ogDescription: extractMeta(html, 'property', 'og:description'),
      twitterDescription: extractMeta(html, 'name', 'twitter:description'),
      h1: extractFirstTagText(html, 'h1'),
      navHtml: extractFirst(html, /<nav\b[\s\S]*?<\/nav>/i),
    };
  });
  const englishPages = pages.filter(page => !isLocalizedPage(page.file));
  const localizedPages = pages.filter(page => isLocalizedPage(page.file));

  const homepage = englishPages.find(page => page.file === 'index.html');
  if (!homepage) {
    throw new Error('Homepage dist/index.html not found');
  }

  const decision1 = auditCanonicalVerbSystem(homepage, englishPages);
  const decision2 = auditPlatformTaxonomy(homepage, englishPages);
  const decision3 = auditHeroContract(homepage);
  const decision4 = auditDownloadArchitecture(englishPages, homepage);
  const decision5 = auditTrustArchitecture(englishPages);
  const decision6 = auditMetadataDiscipline(englishPages);
  const decision7 = auditProofHierarchy(homepage);
  const localeDebt = auditLocaleDebt(localizedPages);

  const decisions = [
    ['Decision 1', 'Canonical verb system', decision1],
    ['Decision 2', 'Platform taxonomy separation', decision2],
    ['Decision 3', 'Hero contract', decision3],
    ['Decision 4', 'Download as first-class IA', decision4],
    ['Decision 5', 'Trust architecture', decision5],
    ['Decision 6', 'Metadata discipline', decision6],
    ['Decision 7', 'Proof hierarchy', decision7],
  ];

  const foundation = auditFoundation(decision4, decision5, decision6);
  const strategic = round(decisions.reduce((sum, [, , result]) => sum + result.score, 0) / decisions.length);
  const overall = round((foundation * 0.4) + (strategic * 0.6));
  const treeState = auditTreeState();

  const report = buildMarkdown({
    generatedAt: new Date().toISOString(),
    decisions,
    foundation,
    strategic,
    overall,
    treeState,
    localeDebt,
  });

  fs.writeFileSync(SCORECARD_LATEST, report);
  fs.writeFileSync(SCORECARD_DATED, report);

  console.log(`  [audit] Wrote ${path.relative(ROOT, SCORECARD_LATEST)}`);
  console.log(`  [audit] Wrote ${path.relative(ROOT, SCORECARD_DATED)}`);
  console.log(`  [audit] Foundation ${foundation}% · Strategic ${strategic}% · Overall ${overall}%`);
}

function auditCanonicalVerbSystem(homepage, pages) {
  const hero = extractHero(homepage.html);
  const primaryCta = normalizeText(extractFirst(hero, /<a\b[^>]*class="[^"]*\bbtn-primary\b[^"]*"[^>]*>([\s\S]*?)<\/a>/i));
  const checks = [
    makeCheck('Homepage title uses outcome language', /\bsave\b/i.test(homepage.title)),
    makeCheck('Homepage H1 uses outcome language', /\bsave\b/i.test(homepage.h1)),
    makeCheck('Homepage primary CTA uses action language', /\bdownload\b/i.test(primaryCta)),
    makeCheck('No page title uses "keep" framing', pages.every(page => !/\bkeep\b/i.test(page.title))),
  ];
  return summarizeChecks(checks);
}

function auditPlatformTaxonomy(homepage, pages) {
  const violations = [];
  const desktopMobileTitle = /\bdesktop\b/i.test(homepage.title) && /\bmobile\b/i.test(homepage.title);
  if (desktopMobileTitle) {
    violations.push('Homepage title still uses broad "desktop/mobile" taxonomy instead of explicit install surfaces.');
  }

  for (const page of pages) {
    const surfaces = [
      ['title', page.title],
      ['description', page.description],
      ['og:description', page.ogDescription],
      ['twitter:description', page.twitterDescription],
      ['h1', page.h1],
    ];
    for (const [surface, value] of surfaces) {
      const text = normalizeText(value);
      if (!text) continue;
      for (const sentence of splitSentences(text)) {
        if (containsAny(sentence, OS_KEYWORDS) && containsAny(sentence, SOURCE_KEYWORDS)) {
          violations.push(`${page.file} mixes OS + source platforms in ${surface}: "${sentence}"`);
          break;
        }
      }
    }
  }

  const score = clamp(100 - (desktopMobileTitle ? 20 : 0) - Math.min(60, violations.length * 10), 0, 100);
  return {
    score,
    summary: violations.length
      ? `${violations.length} taxonomy violation(s) found across titles/descriptions.`
      : 'OS support and source platform support are separated in audited surfaces.',
    evidence: violations.slice(0, 8),
  };
}

function auditHeroContract(homepage) {
  const hero = extractHero(homepage.html);
  const heroContent = extractFirst(
    hero,
    /<div\b[^>]*class="[^"]*\bhero-content\b[^"]*"[^>]*>([\s\S]*?)<\/div>\s*<div\b[^>]*class="[^"]*\bhero-visual\b/i,
  ) || hero;
  const heroText = normalizeText(stripTags(heroContent));
  const subtitle = normalizeText(extractFirst(hero, /<p\b[^>]*class="[^"]*\bhero-subtitle\b[^"]*"[^>]*>([\s\S]*?)<\/p>/i));
  const trustBadgeCount = countMatches(hero, /class="trust-badge"/g);
  const proofTextCount = countMatches(hero, /class="proof-text/g);
  const primaryCtaCount = countMatches(hero, /class="[^"]*\bbtn-primary\b[^"]*"/g);
  const secondaryCtaCount = countMatches(hero, /class="[^"]*\bbtn-text-link\b[^"]*"/g);

  const checks = [
    makeCheck('Exactly one H1 in hero', countMatches(hero, /<h1\b/gi) === 1),
    makeCheck('Hero subtitle stays under 220 characters', subtitle.length > 0 && subtitle.length <= 220),
    makeCheck('Hero uses one primary CTA', primaryCtaCount === 1),
    makeCheck('Hero uses at most one secondary CTA', secondaryCtaCount <= 1),
    makeCheck('Hero trust badges stay within 3 items', trustBadgeCount <= 3),
    makeCheck('Hero proof microcopy stays within 2 units', proofTextCount <= 2),
    makeCheck('Hero text stays under 500 characters', heroText.length <= 500),
  ];
  return summarizeChecks(checks);
}

function auditDownloadArchitecture(pages, homepage) {
  const missingNav = pages
    .filter(page => !page.file.startsWith('payment/'))
    .filter(page => !isRedirectPage(page.html))
    .filter(page => !isUtilityPage(page.html))
    .filter(page => !hasDownloadEntryPoint((page.navHtml || '').trim() ? page.navHtml : page.html))
    .map(page => page.file);

  const downloadHubExists = pages.some(page => page.file === 'download/index.html' || page.file === 'download.html');
  const osPages = ['download/macos.html', 'download/windows.html', 'download/linux.html'];
  const osChecks = osPages.map(file => {
    const page = pages.find(entry => entry.file === file);
    if (!page) {
      return makeCheck(`${file} exists`, false);
    }
    const html = page.html;
    const hasVersion = /v\d+\.\d+\.\d+/i.test(html) || /Version/i.test(html);
    const hasChecksum = /SHA[- ]?256|checksum/i.test(html);
    const hasReleaseDate = /released|release date|last updated/i.test(html);
    return makeCheck(`${file} includes version + checksum + release date`, hasVersion && hasChecksum && hasReleaseDate);
  });

  const heroPrimaryHref = extractPrimaryCtaHref(extractHero(homepage.html));
  const checks = [
    makeCheck('Download route exists', downloadHubExists),
    makeCheck('Homepage primary CTA points to a download target', /download|github\.com/i.test(heroPrimaryHref)),
    makeCheck('Primary nav exposes a download entry point on every English public page', missingNav.length === 0),
    ...osChecks,
  ];

  const result = summarizeChecks(checks);
  if (missingNav.length) {
    result.evidence.push(`Pages missing nav Download CTA: ${missingNav.slice(0, 10).join(', ')}`);
  }
  return result;
}

function auditTrustArchitecture(pages) {
  const trackerHits = [];
  const trustHits = [];
  const claimHits = [];

  const files = publicDistFiles();
  for (const file of files) {
    const content = fs.readFileSync(file, 'utf8');
    const rel = path.relative(DIST, file).replaceAll(path.sep, '/');
    for (const tracker of TRACKER_PATTERNS) {
      if (tracker.pattern.test(content) && !TRACKER_WHITELIST.some(allowed => rel.includes(allowed) || content.includes(allowed))) {
        trackerHits.push(`${rel}: ${tracker.label}`);
      }
    }
    if (!isLocalizedPage(rel)) {
      for (const item of FORBIDDEN_CLAIMS) {
        const pattern = new RegExp(escapeRegExp(item), 'i');
        if (pattern.test(content)) {
          claimHits.push(`${rel}: ${item}`);
        }
      }
      for (const trustPattern of TRUST_SENSITIVE_PATTERNS) {
        if (trustPattern.pattern.test(content)) {
          trustHits.push(`${rel}: ${trustPattern.label}`);
        }
      }
    }
  }

  const privacyPage = pages.find(page => page.file === 'privacy.html');
  const checks = [
    makeCheck('No unapproved third-party trackers found in dist', trackerHits.length === 0),
    makeCheck('No forbidden claims found in dist', claimHits.length === 0),
    makeCheck('Privacy page exists', Boolean(privacyPage)),
    makeCheck('Privacy page states no tracking', Boolean(privacyPage && /\bno tracking\b/i.test(privacyPage.html))),
    makeCheck('Trust-sensitive claims stay narrow', trustHits.length <= 2),
  ];

  const result = summarizeChecks(checks);
  result.evidence.push(...trackerHits.slice(0, 5), ...claimHits.slice(0, 5), ...trustHits.slice(0, 5));
  return result;
}

function auditMetadataDiscipline(pages) {
  const mismatches = [];
  const seoTail = [];
  for (const page of pages) {
    const titles = [page.title, page.ogTitle, page.twitterTitle].map(normalizeText);
    const distinct = [...new Set(titles.filter(Boolean))];
    if (distinct.length > 1 && !METADATA_EXCEPTIONS.has(page.file)) {
      mismatches.push(`${page.file}: title="${page.title}" | og="${page.ogTitle}" | twitter="${page.twitterTitle}"`);
    }
    const combined = [page.title, page.description, page.ogDescription, page.twitterDescription].join(' ');
    if (/free video downloader|fastest video downloader|best video downloader/i.test(combined)) {
      seoTail.push(page.file);
    }
  }

  const titleMatches = pages.length ? pages.length - mismatches.length : 0;
  const consistencyScore = pages.length ? (titleMatches / pages.length) * 100 : 0;
  const seoPenalty = Math.min(35, seoTail.length * 8);
  const score = clamp(round(consistencyScore - seoPenalty), 0, 100);

  return {
    score,
    summary: `${titleMatches}/${pages.length} pages keep title, og:title, and twitter:title aligned.`,
    evidence: [
      ...mismatches.slice(0, 6),
      ...seoTail.slice(0, 6).map(file => `${file}: SEO-tail metadata needs cleanup`),
    ],
  };
}

function auditLocaleDebt(pages) {
  const taxonomyViolations = [];
  const metadataMismatches = [];
  for (const page of pages) {
    const surfaces = [
      ['title', page.title],
      ['description', page.description],
      ['og:description', page.ogDescription],
      ['twitter:description', page.twitterDescription],
    ];
    for (const [surface, value] of surfaces) {
      const text = normalizeText(value);
      if (!text) continue;
      for (const sentence of splitSentences(text)) {
        if (containsAny(sentence, OS_KEYWORDS) && containsAny(sentence, SOURCE_KEYWORDS)) {
          taxonomyViolations.push(`${page.file} mixes OS + source platforms in ${surface}`);
          break;
        }
      }
    }
    const titles = [page.title, page.ogTitle, page.twitterTitle].map(normalizeText);
    const distinct = [...new Set(titles.filter(Boolean))];
    if (distinct.length > 1 && !METADATA_EXCEPTIONS.has(page.file)) {
      metadataMismatches.push(page.file);
    }
  }
  return {
    localizedPageCount: pages.length,
    taxonomyViolations,
    metadataMismatches,
  };
}

function auditProofHierarchy(homepage) {
  const html = homepage.html;
  const indexOfAny = patterns => {
    const matches = patterns
      .map(pattern => html.search(pattern))
      .filter(index => index >= 0);
    return matches.length ? Math.min(...matches) : -1;
  };

  const featureIndex = indexOfAny([/id="features"/i, /class="features"/i]);
  const showcaseIndex = indexOfAny([/class="product-showcase"/i]);
  const privacyIndex = indexOfAny([/class="privacy"/i, /id="privacy"/i]);
  const comparisonIndex = indexOfAny([/class="comparison"/i, /id="comparison"/i]);
  const versionVisible = /v\d+\.\d+\.\d+/i.test(html);
  const installClarityVisible = /download\/macos|download\/windows|download\/linux|id="download-btn"/i.test(extractHero(html));

  const checks = [
    makeCheck('Product reality appears before comparison', featureIndex >= 0 && comparisonIndex >= 0 && featureIndex < comparisonIndex),
    makeCheck('Showcase exists before comparison', showcaseIndex >= 0 && comparisonIndex >= 0 && showcaseIndex < comparisonIndex),
    makeCheck('Privacy or trust proof appears before comparison', privacyIndex >= 0 && comparisonIndex >= 0 && privacyIndex < comparisonIndex),
    makeCheck('Install clarity is visible in hero', installClarityVisible),
    makeCheck('Release/version clarity is visible on homepage', versionVisible),
  ];
  return summarizeChecks(checks);
}

function auditFoundation(decision4, decision5, decision6) {
  const tree = auditTreeState();
  const buildPassed = fs.existsSync(path.join(DIST, 'index.html'));
  const routeCoverage = decision4.score;
  const trust = decision5.score;
  const metadata = decision6.score;
  const treeHygiene = clamp(
    100
      - (tree.untrackedRootDirectories.length * 6)
      - Math.min(20, tree.untrackedEntries.length * 0.4)
      - Math.min(30, tree.modifiedCount * 0.35),
    0,
    100,
  );
  return round(((buildPassed ? 100 : 0) + routeCoverage + trust + metadata + treeHygiene) / 5);
}

function auditTreeState() {
  let output = '';
  try {
    output = execSync('git -C .. status --short website', { cwd: ROOT, encoding: 'utf8' });
  } catch (error) {
    output = error.stdout || '';
  }
  const lines = output.split('\n').filter(Boolean);
  const untrackedEntries = [];
  const untrackedRootDirectories = [];
  let modifiedCount = 0;

  for (const line of lines) {
    if (line.startsWith('?? ')) {
      const rel = line.slice(3).trim();
      if (!rel.startsWith('website/')) continue;
      const relFromWebsite = rel.slice('website/'.length).replace(/\/$/, '');
      if (!relFromWebsite) continue;
      untrackedEntries.push(relFromWebsite);

      if (!relFromWebsite.includes('/')) {
        const full = path.join(ROOT, relFromWebsite);
        if (fs.existsSync(full) && fs.lstatSync(full).isDirectory()) {
          untrackedRootDirectories.push(relFromWebsite);
        }
      }
    } else {
      modifiedCount += 1;
    }
  }

  return {
    modifiedCount,
    untrackedEntries: [...new Set(untrackedEntries)].sort(),
    untrackedRootDirectories: [...new Set(untrackedRootDirectories)].sort(),
  };
}

function buildMarkdown({ generatedAt, decisions, foundation, strategic, overall, treeState, localeDebt }) {
  const lines = [];
  lines.push('# SSvid Landing Scorecard');
  lines.push('');
  lines.push(`Generated: ${generatedAt}`);
  lines.push(`Source: \`website/dist\``);
  lines.push('');
  lines.push('## Snapshot');
  lines.push('');
  lines.push(`- Foundation: **${foundation}%**`);
  lines.push(`- Strategic clarity: **${strategic}%**`);
  lines.push(`- Overall: **${overall}%**`);
  lines.push(`- Modified website entries in git status: **${treeState.modifiedCount}**`);
  lines.push(`- Untracked root dirs: **${treeState.untrackedRootDirectories.length}**`);
  lines.push(`- Untracked website entries: **${treeState.untrackedEntries.length}**`);
  lines.push(`- Localized pages audited separately: **${localeDebt.localizedPageCount}**`);
  lines.push('');
  lines.push('## Decision Scores');
  lines.push('');
  lines.push('| Decision | Score | Summary |');
  lines.push('|---|---:|---|');
  for (const [decisionId, label, result] of decisions) {
    lines.push(`| ${decisionId} — ${label} | ${result.score}% | ${escapePipes(result.summary)} |`);
  }
  lines.push('');
  lines.push('## Evidence');
  lines.push('');
  for (const [decisionId, label, result] of decisions) {
    lines.push(`### ${decisionId} — ${label}`);
    lines.push('');
    if (result.evidence.length) {
      for (const item of result.evidence) {
        lines.push(`- ${item}`);
      }
    } else {
      lines.push('- No major violations recorded by this audit pass.');
    }
    lines.push('');
  }
  lines.push('## Locale Debt');
  lines.push('');
  lines.push(`- Localized pages checked: ${localeDebt.localizedPageCount}`);
  lines.push(`- Taxonomy violations in localized pages: ${localeDebt.taxonomyViolations.length}`);
  lines.push(`- Metadata mismatches in localized pages: ${localeDebt.metadataMismatches.length}`);
  if (localeDebt.taxonomyViolations.length) {
    lines.push(`- Examples: ${localeDebt.taxonomyViolations.slice(0, 6).join('; ')}`);
  }
  if (localeDebt.metadataMismatches.length) {
    lines.push(`- Metadata examples: ${localeDebt.metadataMismatches.slice(0, 6).join(', ')}`);
  }
  lines.push('');
  lines.push('## Tree State');
  lines.push('');
  lines.push(`- Modified website entries: ${treeState.modifiedCount}`);
  if (treeState.untrackedRootDirectories.length) {
    lines.push(`- Untracked root dirs: ${treeState.untrackedRootDirectories.join(', ')}`);
  } else {
    lines.push('- Untracked root dirs: none');
  }
  if (treeState.untrackedEntries.length) {
    lines.push(`- Untracked entries (${treeState.untrackedEntries.length}): ${treeState.untrackedEntries.slice(0, 20).join(', ')}${treeState.untrackedEntries.length > 20 ? ', ...' : ''}`);
  } else {
    lines.push('- Untracked entries: none');
  }
  lines.push('');
  lines.push('## Method Notes');
  lines.push('');
  lines.push('- Scores are heuristic, but they are now repeatable.');
  lines.push('- Metadata discipline is computed from `<title>`, `og:title`, and `twitter:title` alignment across generated HTML.');
  lines.push('- Download IA checks nav presence, route existence, and OS-page install metadata.');
  lines.push('- Trust checks tracker regressions, forbidden claims, and privacy-page assertions.');
  lines.push('- This scorecard should replace ad-hoc progress percentages in future status reports.');
  lines.push('');
  return `${lines.join('\n')}\n`;
}

function summarizeChecks(checks) {
  const passed = checks.filter(check => check.passed);
  return {
    score: round((passed.length / Math.max(1, checks.length)) * 100),
    summary: `${passed.length}/${checks.length} audit checks passed.`,
    evidence: checks.filter(check => !check.passed).map(check => check.label),
  };
}

function makeCheck(label, passed) {
  return { label, passed };
}

function readListFile(file) {
  if (!fs.existsSync(file)) return [];
  return fs.readFileSync(file, 'utf8')
    .split('\n')
    .map(line => line.trim())
    .filter(line => line && !line.startsWith('#'));
}

function listFiles(dir, predicate) {
  if (!fs.existsSync(dir)) return [];
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...listFiles(fullPath, predicate));
    } else if (predicate(fullPath)) {
      files.push(fullPath);
    }
  }
  return files;
}

function extractTitle(html) {
  return normalizeText(extractFirst(html, /<title>([\s\S]*?)<\/title>/i));
}

function extractMeta(html, attribute, key) {
  const pattern = new RegExp(`<meta[^>]*${attribute}=(["'])${escapeRegExp(key)}\\1[^>]*content=(["'])([\\s\\S]*?)\\2[^>]*>`, 'i');
  const match = html.match(pattern);
  return normalizeText(match ? match[3] : '');
}

function extractFirstTagText(html, tag) {
  return normalizeText(extractFirst(html, new RegExp(`<${tag}\\b[^>]*>([\\s\\S]*?)<\\/${tag}>`, 'i')));
}

function extractHero(html) {
  return extractFirst(html, /<section\b[^>]*class="[^"]*\bhero\b[^"]*"[\s\S]*?<\/section>/i);
}

function extractPrimaryCtaHref(heroHtml) {
  const primaryAnchor = extractFirst(heroHtml, /<a\b[^>]*class="[^"]*\bbtn-primary\b[^"]*"[^>]*>[\s\S]*?<\/a>/i);
  return extractFirst(primaryAnchor, /href="([^"]+)"/i);
}

function hasDownloadEntryPoint(navHtml) {
  return /\bhref="[^"]*(?:\/download(?:\/|")|github\.com\/mydinh-studio\/ssvid-releases\/releases\/latest\/download)/i.test(navHtml)
    || /\bid="nav-download-btn"/i.test(navHtml)
    || /\bdownload free\b/i.test(navHtml);
}

function isLocalizedPage(file) {
  return LOCALE_CODES.some(code => file.startsWith(`${code}/`));
}

function isRedirectPage(html) {
  return /http-equiv="refresh"|window\.location\.replace\(/i.test(html);
}

function isUtilityPage(html) {
  return /<meta[^>]*name="robots"[^>]*content="[^"]*noindex/i.test(html);
}

function publicDistFiles() {
  return listFiles(DIST, file => !/hero-(mobile-cards|replica)\.html$/i.test(path.basename(file)));
}

function extractFirst(value, pattern) {
  const match = value.match(pattern);
  return match ? match[1] || match[0] : '';
}

function stripTags(value) {
  return value
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' ');
}

function normalizeText(value) {
  return decodeEntities(stripTags(String(value || '')))
    .replace(/\s+/g, ' ')
    .trim();
}

function decodeEntities(value) {
  return value
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/&rsquo;/gi, "'")
    .replace(/&ldquo;/gi, '"')
    .replace(/&rdquo;/gi, '"')
    .replace(/&middot;/gi, '·')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>');
}

function splitSentences(text) {
  return text
    .split(/(?<=[.!?。！？।॥؟])\s*/)
    .map(part => part.trim())
    .filter(Boolean);
}

function containsAny(text, keywords) {
  const lower = text.toLowerCase();
  return keywords.some(keyword => {
    if (keyword === 'x') return /\b(?:x|twitter\/x)\b/i.test(text);
    return lower.includes(keyword);
  });
}

function countMatches(value, pattern) {
  return (value.match(pattern) || []).length;
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function escapePipes(value) {
  return value.replace(/\|/g, '\\|');
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function round(value) {
  return Math.round(value);
}
