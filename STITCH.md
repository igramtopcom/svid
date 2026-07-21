# STITCH.md — SSvid Design Registry

> Persistent index of all Google Stitch projects. Every Claude session reads this to know the full design landscape.
> Direction: **Nocturne Cinematic** (SSvid: Obsidian Wine) | **Arctic Command** (VidCombo: Nordic Ice)
> Updated: 2026-04-15 (YouTube Spotter's Desk + Subscriptions Signal Array added)

## Active Projects

### SSvid Subscriptions — The Signal Array
- **ID**: `10180581056454570888`
- **Created**: 2026-04-15
- **Status**: ACTIVE — Subscriptions tab redesign exploration
- **Design Systems**:
  - Nocturne Cinematic — Obsidian Wine (Dark): `11126556967397991109`
  - Nocturne Morning Shift (Light, auto-generated): `0343c5e5d33e4133b2bdaa48f2fc8980`
- **Screens** (3):

| Screen | ID | Mode | Status | Notes |
|--------|----|------|--------|-------|
| The Signal Array — Dashboard | `b50123fc294b4853a9bbe85fcd4b9ba9` | Dark | Draft — Pending review | 228 feeds filled state, surveillance metaphor, monospace counters, 2px wine indicator bars |
| The Signal Array — Dead Air | `6b1ba9e9193a4ff79c00ef538123f433` | Dark | Draft — Pending review | Empty state with radar well + sweep line, "DEAD AIR" headline, noir narration |
| The Signal Array — Morning Shift | `c85262b7f87f48899b6bd33ec60d61ab` | Light | Draft — Pending review | Warm paper #F8F2EE + blush dawn glow, same operator morning shift |

### SSvid YouTube — The Spotter's Desk
- **ID**: `2557576779655913525`
- **Created**: 2026-04-15
- **Status**: ACTIVE — YouTube tab redesign (Discovery + Autocomplete). Port existing Command Center (`a063b031939c49249f0b95f3b5cff657`) for Results.
- **Design Systems**:
  - Nocturne Cinematic — Spotter's Desk (Dark): `14767587490940941477`
  - Nocturne Morning (Light, auto-generated): `cb312a1c86c44061a906e168768e8668`
- **Screens** (3):

| Screen | ID | Mode | Status | Notes |
|--------|----|------|--------|-------|
| The Spotter's Desk — Discovery | `97f531f026e64b3ea0c4aa8f89a841e7` | Dark | Draft — Pending review | Command header, category rail, recent queries, trending signals (6 rows), tracked creators (8), category beats 2×2 grid |
| The Spotter's Desk — Morning Shift | `f57f19b20dec477da21d20dd731310dd` | Light | Draft — Pending review | Warm paper #F8F2EE base + blush rose dawn glow, same Discovery layout |
| Autocomplete Intelligence | `3a7f000b66e44afbaac1d46d88edfe33` | Dark | Draft — Pending review | Focused search field + dossier overlay: MATCHED IN ARCHIVE / TRENDING NOW / YOUR HISTORY sections, keyboard nav rail, 30% dimmed Discovery behind |

### SSvid Desktop — Final UI Design (Dark + Light)
- **ID**: `10022260214920217805`
- **Created**: 2026-03-24
- **Status**: ACTIVE — omnibus project for core screens
- **Screens** (81):

#### Core App Screens (14) — Finals + Implemented

| Screen | ID | Mode | Status |
|--------|----|------|--------|
| First-Time Setup | `348c739741514417823e166bc9cb4a27` | Dark | **Implemented** |
| SSvid Setup (Light) | `a4da878dbb6e4b76a2b5899a0ec5c398` | Light | **Implemented** |
| SSvid Flagship Dashboard | `a9e49dc6235941b7b7cacc9009fc591b` | Dark | Final |
| SSvid Home Dashboard (Light Refined) | `5882025024a048cb8c194f12e4c7b61f` | Light | Final |
| SSvid Settings - Quality & Format | `996478f1821d42b49b5ffdf95d3416d8` | Dark | Final |
| SSvid AI Assistant (Zen Noir) | `871de3ebf1844dbb971f893686e91d99` | Dark | Superseded — see Intelligence Hub |
| Premium Membership Management | `e27d2d04a5d348c5bbd504997b8d782a` | Dark | Final |
| SSvid Premium Membership Upgrade | `13a120d3889c4a2b89479136989dbf0c` | Dark | Final |
| Members Lounge v2 (Transaction+Devices) | `5c30c1e05fcd45fbb0fde5e941d1c15a` | Dark | **Implemented** |
| Stripe Checkout Dialog | `346e2d7244b142f499a0a74a6037de81` | Dark | **Implemented** |
| SSvid Notification Center (Dark) | `e629b606fa99411f9a7420977e1a1572` | Dark | Final |
| SSvid Support Center (old) | `dcb06b7e079347e4b09aedd81e4a82a1` | Dark | Superseded |
| Support Center — Concierge Lounge | `47374b6627c04c2db63cc1e3e445a024` | Dark | **Final** ✅ |
| SSvid Desktop App Home (V2-Edit) | `4abf727dabc04d05859bcf97493ab4df` | Dark | Reference |
| Download Detail — The Dossier | `666accda142f46818a38afca1c91fa0f` | Dark | **Implemented** |
| Download Detail — The Dossier (Light) | `1a93bab3bdbc4d62b2f012b5037ec152` | Light | **Implemented** |
| Quick Start — The Briefing | `773b5c1ae6b84c5aa6d1a18286a41db1` | Dark | Superseded |
| Quick Start — The Briefing (Light) | `701d7a2cc67f4391855574ddcd1616cd` | Light | Superseded |
| Clipboard Intelligence Surface | `e83b58f6d99c4a6cb8feee501d54d7f6` | Dark | **Implemented** |
| The Evidence Room v1 | `afe9fa75ba654c089737ba629bed2246` | Dark | Superseded |
| The Evidence Room v2 — States Showcase | `9e803ae8c4b44982942aed880188893e` | Dark | **Implemented** |

#### YouTube Explore Screens (11) — Command Center Redesign

**FINAL (implement this):**

| Screen | ID | Mode | Status | Notes |
|--------|----|------|--------|-------|
| YouTube Search Command Center | `a063b031939c49249f0b95f3b5cff657` | Dark | **FINAL** ✅ | 65/35 master-detail split, search+filters left, preview+quality picker right. Full-page YouTube tab. |

**Reference (design exploration):**

| Screen | ID | Mode | Status | Notes |
|--------|----|------|--------|-------|
| YouTube Intelligence Hub | `2727e2abfad54b7ea641fe5d20471161` | Dark | Reference | Creative brief breakthrough — hero+categories too discovery-focused, but quality picker + metadata grid adopted |
| YouTube Download Workstation (B) | `c030f34eaf23432e833834c9a8da5047` | Dark | Reference | Inline accordion expansion — good "GET 4K/HD/SD" labels adopted, but accordion disrupts scroll position |

**Superseded (older iterations):**

| Screen | ID | Mode | Status |
|--------|----|------|--------|
| YouTube Explore — Discovery | `1b679801cd0949d89f6541ac1a9cbbb6` | Dark | Superseded — trending/categories concept rejected for SSvid |
| YouTube Search Results (70/30) | `341a9953abfd4f84ae45d5e29ba3e70d` | Dark | Superseded — replaced by Command Center |
| YouTube Autocomplete State | `123a3a9c23154ef88586bc4384775059` | Dark | Superseded — autocomplete will be inline in Command Center search |
| Explore YouTube (old) | `5f2623a18b084bae8bcd98e260ac08d1` | Dark | Superseded — no trending content |
| Explore YouTube (Light Mode) | `9ae187581add45a8a1cd4a6e8be7a0db` | Light | Superseded — will regenerate light after dark impl |
| YouTube Search Results v2 | `54acfbbe233743e698ad7fb647e25ae5` | Dark | Superseded — no quality panel |
| YouTube Search Results v1 | `86814427cd154ed6becb123b18043f7b` | Dark | Superseded — nav was 88px |
| YouTube Search Results (Light) | `a4f0ce3b11f3418bb4a04f01132afe02` | Light | Superseded — will regenerate light after dark impl |

#### Audio Player — The Listening Room (2)

| Screen | ID | Mode | Status |
|--------|----|------|--------|
| The Listening Room — Audio Player | `24ef46d1023f425abec6451bc4c64c49` | Dark | **Implemented** |
| The Listening Room (Light Mode) | `34229afb501f48ce9dc66bb0ee59bf4a` | Light | **Implemented** |

#### Image Viewer — The Private Gallery (4)

| Screen | ID | Mode | Status |
|--------|----|------|--------|
| The Private Gallery v2: Image Viewer | `96b16448a1b14d5cbb0c8d5c3243158e` | Dark | **Implemented** |
| The Private Gallery v2 (Light) | `dd5d5f06b59147269f4f0a23c9ae4521` | Light | **Implemented** |
| The Private Gallery v1 (old) | `0cce2c6f0a0a4a57bdc8899ce6e49c27` | Dark | Superseded |
| The Private Gallery v1 Light (old) | `0318482385e44c31a0cf7e17d009178f` | Light | Superseded |

#### AI Assistant Intelligence Hub (6) — Dark + Light

| Screen | ID | Mode | Status |
|--------|----|------|--------|
| AI Welcome "The Intelligence Chamber" | `8c2cb1d09ab04547b83687a525878567` | Dark | **Final** |
| AI Chat "The Dialogue" | `1bbe5d45847a415d83374e505ba02239` | Dark | **Final** |
| AI History "The Case Files" | `04335502606f4e9ca4ed40576aef3803` | Dark | **Final** |
| AI Welcome Light | `06ce3d6d7ca648f784e240d8e8526579` | Light | **Final** |
| AI Chat Light | `e71c2c68299348a8a083b4eeaabaf958` | Light | **Final** |
| AI History Light | `5b11a19d5db34d628f9a5a7c2e955e8f` | Light | **Final** |

**Note**: Supersedes old `SSvid AI Assistant (Zen Noir)` (`871de3ebf1844dbb971f893686e91d99`).

#### Settings — The Control Room (9) — Comprehensive Settings Redesign

| Screen | ID | Mode | Status | Section |
|--------|----|------|--------|---------|
| The Control Room (General) | `3bb93717928a4ef7ba791a866c7c1bc5` | Dark | **Final** | General — theme, language, notifications |
| The Control Room (Light) | `a5c4e1315d444d96957ed4ac094b1fd5` | Light | **Final** | General — light variant |
| The Armory (Downloads) | `1dbb68375dc94cdea22238558443aadc` | Dark | **Final** | Downloads — location, concurrency, bandwidth, cleanup |
| The Armory (Light) | `86ee198310be4b04b86e794635700c26` | Light | **Final** | Downloads — light variant |
| The Switchboard (Network & Proxy) | `642c3ebac3d24ba3a0e0f38d884aa1cf` | Dark | **Final** | Network — proxy, geo-bypass, quiet hours, tuning, templates |
| The Switchboard (Light) | `b81e60f21ab64f9b95696f864cc30e37` | Light | **Final** | Network — light variant |
| The Engine Bay (Components) | `179a106cd1184015a725c299f24302c1` | Dark | **Final** | Engine — yt-dlp, FFmpeg, FFprobe diagnostics |
| The Engine Bay (Light) | `5fc56ec0909f4da7876f366ce4204334` | Light | **Final** | Engine — light variant |
| The Dossier (About & Support) | `78fd8a558dd14cadb5a91871bbb99429` | Dark | **Final** | About — usage stats, backup/restore, device registration |

**Note**: Existing `SSvid Settings - Quality & Format` (`996478f1821d42b49b5ffdf95d3416d8`) covers the Quality section. Together with these 9, all 9 settings sections now have design coverage.

**Layout pattern**: Master-detail (220px sidebar + 680px scrollable content). Same sidebar across all sections with brand accent left-bar active indicator. Each section uses `settingsCard()` with brand-aware radius and conditional borders (SSvid: 3px + border, VidCombo: 12px + no border).

#### The Network — Channel Subscriptions (2)

| Screen | ID | Mode | Status |
|--------|----|------|--------|
| The Network Dashboard | `b3b3c4c49a014c4ba3ad2b86598c6a47` | Dark | **Implemented** |
| The Dossier — Channel Intelligence | `aeb19b1031ea45b4b26f3cfbf57f0cc6` | Dark | **Implemented** |

#### Browser — The Observatory (15) — Signal Intelligence Redesign

**FINAL (implementing):**

| Screen | ID | Mode | Status | Notes |
|--------|----|------|--------|-------|
| The Observatory v2 (Surveillance Console) | `5400a12f2f5a4be3b55ecc4c5488ac14` | Dark | **FINAL** | Right-side media panel, merged tabs. CTO pick. |
| The Observatory v2 Color Refined | `ce31cebb34174d80a450d5bf6f3d79a1` | Dark | **Implementing** | Nocturne tokens locked, purple incognito |
| The Launch Pad (New Tab) | `8d08c6986221405a8778883d1e18918e` | Dark | **Implementing** | Platform-colored grid, crimson branding |
| Signal Intelligence v2 (Hierarchical) | `ee0e375ef30745ee842ef2cd0805b8a9` | Dark | **FINAL** | Accordion categories, Download All footer |
| Signal Intelligence v2 Color Refined | `0554d1b487634caf94a84bdce5428d3e` | Dark | **Implementing** | Right drawer, crimson buttons locked |

**Browser Components (5) — v3 Upgrade (Superseded by v4 Breakthrough):**

| Screen | ID | Mode | Status | Notes |
|--------|----|------|--------|-------|
| Signal Intelligence v3 (Thumbnails) | `59b3f15479624a1997baa2a73f187ed9` | Dark | Superseded | Replaced by Radar v4 Tactical Dossier |
| Investigation Log (History) | `e41aa27df1af4a9baeb709b891c2658e` | Dark | **Implementing** | Date-grouped sections, platform icons, time-ago, hover delete, search |
| Intelligence Archive (Bookmarks) | `2164b68ce8f64068a9e6f8ca9295b4f4` | Dark | **Implementing** | Search, platform icons, import/export menu, hover delete |
| The Command Palette (Context+Batch) | `8111d72335e94526a6951a7ab3095528` | Dark | **Implementing** | Context menu + Batch dialog side-by-side, shortcut badges, platform badges |
| The Oracle (Autocomplete) | `d6d7c5d333a94f5790347ab07c388d20` | Dark | **Implementing** | Platform icons, SAVED/HISTORY badges, crimson cursor |

**Browser Breakthrough (6+6 variants) — v4 Tier-SSS Upgrade:**

PRIMARY WINNERS (implement these):

| Screen | ID | Mode | Status | Notes |
|--------|----|------|--------|-------|
| Mission Control (New Tab) | `5062e1af817c44539c8000494b45ea3e` | Dark | **FINAL** ✅ | Command center new tab: search hero, recent downloads, trending, platform grid, system telemetry |
| Quality Theater (Film Strip) | `645d70e1b97f43efa6312870014c0cbd` | Dark | **FINAL** ✅ | Cinematic quality selector modal: 4K/1080p/720p hierarchy, EXECUTE DOWNLOAD CTA, file path |
| Radar v4 (Tactical Dossier) | `fddb40e77cce49ee876830e9f6530783` | Dark | **FINAL** ✅ | Signal panel as intel dossier: primary target vs secondary assets, ACQUIRE SIGNAL, quality badges |

CONCEPT REFERENCES (inform implementation):

| Screen | ID | Mode | Status | Notes |
|--------|----|------|--------|-------|
| The Moment of Truth (Toast) | `5cdfd25774754221adab27c2c5b7f212` | Dark | Concept | Floating contextual download toast over video — non-intrusive detection |
| The Quality Theater (Original) | `a8b99a56927547c8951fa036e24efe77` | Dark | Concept | Original inline quality selector — has sidebar (violation) |
| Platform Chameleon | `888fdc0324fc430db7d46f04feaac183` | Dark | Concept | Platform-adaptive UX: YouTube quality grid, IG save reel, TikTok watermark toggle |
| The Radar (Original) | `ee37516281e944a3bd9fb640d1bdd0cd` | Dark | Concept | Original signal panel with tabs — evolved into Tactical Dossier |
| Heads-Up Display (HUD) | `c79db5a6e50a4ff58746d75cbb414a5b` | Dark | Concept | Floating HUD cards over video + INTERCEPT toolbar button |

VARIANT EXPLORATIONS (rejected but preserved):

| Screen | ID | Notes |
|--------|----|----|
| Radar V1 (Grid Stream) | `8dde2ab5b83043d692c838d52ee084f1` | Too dense grid layout |
| Radar V2 (Holographic) | `889440e6ee424426997f413063086e4e` | Good but V3 superior |
| QT V2 (Projectionist Console) | `1f20b63418e24777be9390ac9f16ad98` | 2x2 grid kills hierarchy |
| QT V3 (Dial Selector) | `2d55b2aadd164af1968a83f3e7ca1601` | Lens metaphor too abstract |

**Reference (design exploration):**

| Screen | ID | Mode | Status |
|--------|----|------|--------|
| The Observatory (original) | `01832b15629e4f36af7f7481abb8b675` | Dark | Reference — bottom panel layout |
| Signal Intelligence (original) | `e407a6c896e44b59b7ad7ffe53b37433` | Dark | Reference — horizontal cards |
| Observatory v1 (Investigation Dashboard) | `dd007a02a5c6407e89eedf28ae674974` | Dark | Superseded — lost browser shell |
| Observatory v3 (Editor's Workspace) | `1f9e5ee6609f43dc9d95c589a0782595` | Dark | Reference — Asset Bin concept |
| Observatory v2 Color Refined v2 | `a8c92d470aa0410fa3fe5678a55b0fdc` | Dark | Reference |
| Signal Intelligence v1 (Brutalist) | `bd03c3eff30d4aef9933e5fd82f8ef19` | Dark | Reference — CLI-style cards |
| Signal Intelligence v3 (Command Center) | `6564bb5d06a544528aa61ce389fa0719` | Dark | Reference — tab categories |
| Signal Intelligence v2 Color Refined v2 | `052506a5990f44b6b84b4d99a4498590` | Dark | Reference |

#### Home — The Cockpit (3) — Implementation Reference

| Screen | ID | Mode | Status |
|--------|----|------|--------|
| The Cockpit Home (Dark) | `1274fae240f5428c91ca5ad47e42c860` | Dark | **Final** — Implementation reference for Downloads feature Nocturne upgrade |
| Command Bar & Control Strip | `dcde0cb73e7346e9b4e2c0e080aa29fc` | Dark | **Implemented** — URL input, YouTube actions, platform pills, filter toolbar |
| The Flight Deck Strip (Nav Bar) | `7e113f6249964850b0b0b687d479d69a` | Dark | **Implemented** — Breakthrough nav bar: remove +New/search, promote Browser to tab, labeled utilities |

#### Download Cards — Stitch Component Showcase (5)

| Screen | ID | Mode | Status |
|--------|----|------|--------|
| Download Card States (List, v1) | `64e72962de824d67841cb45d0921c64d` | Dark | Superseded — initial generation |
| Download Card States Refined (List) | `1131daaddd1640a2ac1a0e6cffadc71e` | Dark | **Implemented** — status colors fixed, crimson progress glow |
| Download Grid: All States (v1) | `045e22a6ff5c4ba3b00f55a0398b79a8` | Dark | Superseded — initial generation |
| Download Grid: Color Refined (v1) | `72c0ea3ed02c444ca58d7281267e7ae0` | Dark | Reference — Nocturne color fix |
| Download Grid: Color Refined (v2) | `0420b37ba2b4404897a4d750dfa22762` | Dark | **Implemented** — brand wine nav, exact status colors |

#### Snackbar / Toast Notifications — Component Showcase (1)

| Screen | ID | Mode | Status |
|--------|----|------|--------|
| Snackbar Component Showcase | `20fb86fe5633475fb930b0592085a1a0` | Dark | **Implemented** — 5 variants: success/error/warning/info/premium upsell |

#### Home Style Variants (11) — Creative Exploration

| Screen | ID | Status |
|--------|----|----|
| Mission Briefing Home | `cda8f9bfa9344a0b95310d6a53d018e5` | Variant |
| The Apothecary Home Screen | `cc45c1b96ce64a4c847f61d7154e1c0a` | Variant |
| The Screening Room Home | `d676a52c0b2844a3a0f517382a980483` | Variant |
| Deep Sea Station Home | `ed6c4aa2cad94462831df1a79775b56b` | Variant |
| The Observatory Home | `c5daaac8278941d69a5a66bbd2144d8d` | Variant |
| Brutalist Terminal Home | `379db23d33964258a842a95c038fa999` | Variant |
| SSvid Control Tower Home | `19d756dc41ef4685ba7b556b0bbbd52f` | Variant |
| SSvid Blueprint Home | `674ff189eb3f47579fab5414f9b89874` | Variant |
| SSvid Home — The Editorial | `a63af07794bb40db9ee174bffcf71d40` | Variant |
| SSvid Home - The Jazz Club | `8dd93eded36b41f89f2538446b3150e4` | Variant |
| Notifications Continuity Log | `498e0d9371c6435ba5fbd51a6c234669` | Variant |

#### Broken / To Delete (1)

| Screen | ID | Note |
|--------|----|------|
| First-Time Setup (no screenshot) | `f911aec3cb184414806239cc42e587cd` | Failed generation, no preview |

## AI Agent Vision Project

### SSvid AI Agent — Ambient Intelligence Vision
- **ID**: `5406376482235302882`
- **Created**: 2026-04-03
- **Status**: ACTIVE — v2.0.0 AI Agent design exploration
- **Design System**: "Nocturne Intelligence" (evolved from Nocturne Cinematic for agent experience)
  - Asset: `535798104583869010`
  - Stitch also auto-generated: "The Obsidian Intelligence Framework" / "The Silent Operative" (`a0c1f82005a5410794a61b95e0bd90a0`)
- **Purpose**: Design the paradigm shift from "chatbot with tools" to "ambient intelligence layer"
- **Screens** (17 + 3 variants):

#### Agent Core Experience (7)

| # | Screen | ID | Purpose |
|---|--------|----|---------|
| 1 | Activity Feed — Mission Control | `5aecbb376c0a44d5abc57a1121dacaed` | Replaces chat as primary view — timeline of agent intelligence |
| 2 | Clipboard Intelligence Widget | `15ce6e21b6d24bd594a1579996078aa4` | Zero-chat interaction — floating download widget |
| 3 | Command Bar (Cmd+K) | `ff4873404333452b9f94413aad3c2b77` | Spotlight-like overlay for instant actions |
| 4 | Self-Healing Download | `8df86fe7ca164832a976723982c7902c` | Agent recovery timeline on Downloads page |
| 5 | Agent Preferences Dashboard | `5acb5d7d9b734e6281c336740bcb5da5` | Learned preferences with confidence bars |
| 6 | Persistent Goals | `f25b8ecd17144275a39501dfa094da92` | Recurring downloads, channel monitoring |
| 7 | Browser Contextual Intelligence | `83dc18fdd5194b249bb7c5dbf9fb01cd` | Agent detection bar on in-app browser |

#### Breakthrough Features (2+)

| # | Screen | ID | Purpose |
|---|--------|----|---------|
| 8 | Video DNA — Intelligence Dossier | `a6220d02363b46a2842fff4bcc5f55bb` | Deep video analysis — format graph, quality timeline, codec breakdown |
| 9 | Smart Media Library | `2249a15c20d9450d9fcce47e3fb7fe9f` | AI-organized archive with auto-tags, semantic search, collections |
| 10 | Download Flow Visualization | `0e25ccc9f9404d3f9ea73faf90b8e867` | Neural network view — Sankey flow from sources to destinations, live bandwidth |
| 11 | AI Video Summary — Intelligence Brief | `61bf3dda610540208dbf29f70d9c0102` | Pre-download AI analysis — content summary, chapters, smart quality selection |
| 12 | Batch Intelligence — Playlist War Room | `e7fa5452b5c64dd1a18ebe25bc242217` | Strategic batch operations — 3-phase plan, battle timeline, autonomous mode |

#### User Journey & Configuration (3+)

| # | Screen | ID | Purpose |
|---|--------|----|---------|
| 13 | Agent Onboarding — The Awakening | `c9e4607ee0ec49918d69351d759abce9` | First-run experience — cinematic agent activation, permission toggles, trust intro |
| 14 | Error Diagnostics — The Forensics Lab | `303bb85cce4841f29619c56801af01a1` | AI error analysis — pattern detection, root cause, recommended actions, history |
| 15 | Agent Control Panel — The Nervous System | `194533b61d664edf85059d88588991a4` | Settings → Agent — perception/autonomy/learning config, trust score, performance data |
| 16 | Smart Notifications — The Digest | `ec91d97e31a34d8fbf671870c6936351` | AI-batched notifications — toast + notification center, grouped intelligence briefings |
| 17 | Expert Chat — Nocturne Intelligence | `f6968115bf0446bface00a1aac4d8651` | Chat as fallback — context panel, structured options, tool cards, goal creation inline |

#### Variant Explorations (3)

| Variant | Source Screen | ID | Approach |
|---------|--------------|-----|----------|
| Activity Feed — Twitter Live Feed | #1 Activity Feed | `17ff9d52721e4f1290da9a62e492ea3d` | Single-column chronological posts, compact sidebar |
| Activity Feed — Kanban Board | #1 Activity Feed | `fc1e671d8bce4f83b99a81af38672547` | Columns: Pending Input / In Progress / Resolved / Needs Attention |
| Activity Feed — Notification Drawer | #1 Activity Feed | `0c6e6f913b22479a98650f90b80eaf08` | Collapsed/expandable drawer, badge count, quick actions |

## VidCombo Design Project

### VidCombo Desktop — Arctic Command UI
- **ID**: `1278872591090747452`
- **Created**: 2026-04-12
- **Status**: ACTIVE — VidCombo brand visual identity exploration
- **Design System**: Arctic Command (DM Sans, 12px rounded, elevated borderless cards)
- **Note**: 12 screens generated for brand identity differentiation vs SSvid. All screens use DM Sans font, rounded shapes, floating card style, blue/cyan accents.

## Archive Projects

### SSvid Desktop UI Redesign 2026
- **ID**: `9746799973876268727`
- **Created**: 2026-03-23
- **Status**: ARCHIVE — 33 screens, old exploration
- **Note**: Bulk design exploration before consolidation. Contains older YouTube designs (e.g. "Explore YouTube - Definitive Redesign"). Do NOT generate new screens here.

### Phoenix-Websites (renamed from Tier-S Dashboard)
- **ID**: `10555815442131873265`
- **Created**: 2026-03-19
- **Status**: REFERENCE — 10 screens, style exploration
- **Note**: Earliest project. Wide style exploration (Neo-Brutalist, Pop-Vibe, Audiophile, etc.) before settling on Nocturne Cinematic.

### SSvid Landing Page — Product Shots
- **ID**: `4515629105610136291`
- **Created**: 2026-03-24
- **Status**: REFERENCE — 11 screens, landing page assets
- **Screens**:
  - App in Action (hero): `e8c3a75a209040e59793e8aeb9de9edd`
  - Library View: `20356d21b45a4fc1b72cd1a59124002e`
  - Player + PiP: `3a420ef7b29a44039723fb1c90d6ab1c`
  - + 8 other product shots

## Design Direction: Two Brands, Maximum Opposition

### SSvid — Nocturne Cinematic (Obsidian Wine)
- **Dark-first**: Deep blacks with tonal layering (no flat #000000)
- **Accent**: Wine red → Crimson gradient
- **Typography**: Inter (humanist, sharp terminals)
- **Shape**: 3px angular, flat + bordered cards
- **Aesthetic**: No shadows — tonal elevation + hairline borders define edges
- **Inspiration**: Cinema noir, wine cellar, architectural precision

### VidCombo — Arctic Command (Nordic Ice)
- **Dark-first**: Cool arctic slate (no warm tint)
- **Accent**: Blue → Cyan gradient
- **Typography**: DM Sans (geometric, clear bold)
- **Shape**: 12px rounded cards, 999px pill buttons, 8px inputs
- **Aesthetic**: Floating elevated cards — shadow defines edges, no borders
- **Inspiration**: Nordic command center, ice station, approachable clarity

See `DESIGN.md` for exact tokens, `brand_config.dart` for runtime values.

## Workflow Rules

1. **New screens** → generate ONLY in Active project (`10022260214920217805`)
2. **Archive projects** → read-only reference, never generate new screens
3. **Always generate both** Dark + Light mode for every screen
4. **Naming convention**: `SSvid [ScreenName] [Dark|Light] [vN]`
5. **Model**: Use `GEMINI_3_1_PRO` for final quality, `GEMINI_3_FLASH` for quick drafts
6. **Cleanup**: Stitch API has NO delete — use Playwright MCP on stitch.withgoogle.com
7. **After generating**: Update this file with new screen IDs and status
8. **CRITICAL**: TopNavigationBar (52px top bar) — NO sidebar, NO bottom navigation in any prompt
