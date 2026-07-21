# Svid v2.2 Floating Capture — Stitch Creative Brief

**For:** Stitch Creative Director (Gemini 3.1 Pro)
**Project:** Svid Desktop — Final UI Design (ID: 10022260214920217805)
**Author:** CTO Frontend (Desktop)
**Date:** 2026-05-07
**Version:** v1.1 (post ultra self-review)
**Companion to:** [Svid_v2_2_FloatingCapture_Improvement_Spec.md](Svid_v2_2_FloatingCapture_Improvement_Spec.md)

**v1.0 → v1.1 changelog:**
- VidCombo accent color corrected: `#0066CC` Ocean Blue + `#03BEFE` Cyan (verified `brand_config.dart:795` — em đoán sai `#2E7CD6` ở v1.0)
- State 9 form factor: separate 300×120 design entity (M8 fix — KHÔNG phải variant chung 300×420)
- Queue strip metaphor: "browser tabs" (m3 — film-negative metaphor không universal)
- State 4 channel avatar fallback: text-only chip + platform logo (m4 — YouTube oEmbed channels rarely returns avatar)
- State 6 auto-close: 4s (was 2s — m2 too rushed for non-English readers)
- Stitch generation order: hero (State 2 Svid) → review → State 2 VidCombo → review → 18 còn lại parallel (M9 — batch with checkpoints)
- VidCombo paywall flow: Stripe checkout (B4 — `hasStripeCheckout: true` confirmed)

---

## 0. Read-First Context

Đây là creative brief cho **redesign popup floating capture v2.2** — không phải spec UI thuần. Stitch hiểu Visual Descriptions tốt hơn technical specs.

**Active Stitch project**: "Svid Desktop — Final UI Design" (ID: 10022260214920217805) — design system đã setup. Brief này thêm 20 screens mới (10 variants × 2 brands).

**Trước khi đọc tiếp**: Stitch hãy lướt qua `STITCH.md` (registry) + `DESIGN.md` (design tokens) trong root repo. Brand identity 2 dòng:
- **Svid**: "Nocturne Cinematic" — dark wine red (#8D021F) + crimson (#C41E3A), Inter font, tonal layering, "blood-dark wine red for tension"
- **VidCombo**: "Arctic Command" — cool arctic blue, white-on-deep-blue, calmer mood

---

## 1. The Story

### What this popup IS

Một **moment** giữa user và app. User đang xem video trên YouTube/TikTok/IG, tay copy URL, popup xuất hiện như **phản xạ** — không phải interruption. User có 2 lựa chọn primary: tải ngay (1 click → xong, app im lặng download nền) hoặc "tôi muốn chọn format" (mở app đầy đủ).

Popup không cố gắng thay app. Nó là **bàn tay phụ thứ ba** — user vẫn ở browser, video vẫn đang phát, popup tự đến tự đi.

### Reference benchmark

- **Downie 4** (Mac, $30): copy-to-popup là single feature, đã thắng thị trường nhờ làm 1 thứ cực tốt
- **Maccy** (free): popup 200×400, neutral, không brand-heavy, focus vào content
- **Raycast**: popup không activate underlying window — feels like extension of OS, không phải separate app
- **1Password Mini**: brand identity giữ trong popup nhưng không "shouty" — accent dot + typography đủ

### What this popup is NOT

- ❌ Mini version của main app — không cố cram features
- ❌ Persistent dock companion — phải tự biến mất sau 60s idle
- ❌ Notification center — không lưu history popup
- ❌ Cố giành attention — KHÔNG steal focus, KHÔNG bring browser xuống

---

## 2. Visual Direction

### Form factor

**300 × 420 pt portrait** (collapsed — default).
**300 × 560 pt portrait** (expanded — khi queue > 1).

Floating panel — corner-rounded **16pt**, drop shadow soft (như "whisper-soft"), no titlebar chrome (custom drag region top 24pt), backdrop opaque (NOT translucent — translucent thường gây lag perception trên Windows + readability kém trên dark wallpaper).

### Brand Svid — "Nocturne Cinematic"

```
Background:     Pressurized void  #121212  (almost-black, NOT pure black)
Surface:        Onyx              #1A1A1A  (cards, button bg)
Surface elev:   Graphite          #242424  (hover, queue strip)
Border:         Smoke             rgba(255,255,255,0.06)
Text primary:   Bone              #F5F5F5
Text secondary: Ash               #A0A0A0
Text tertiary:  Charcoal          #6E6E6E

Accent primary: Wine Red          #8D021F  (Download Now button bg)
Accent hover:   Crimson           #C41E3A
Accent fg:      Pure white        #FFFFFF

Success:        Soft green        #4ADE80  (Download Complete ✓)
Warning:        Amber             #FBBF24  (Quota warning, Snoozed)
Error:          Coral             #F87171  (Download Failed ✗)
```

**Vibe direction**: như "đọc credits cuối phim noir" — text hierarchy confident, không jarring. Wine Red dùng tiết kiệm, chỉ cho 1 primary action — tension đến khi cần, không spread đều mọi nơi.

### Brand VidCombo — "Arctic Command" (verified colors `brand_config.dart:795`)

```
Background:     Deep ocean        #0E1B2C  (cool dark, không warm)
Surface:        Slate             #1A2A40
Surface elev:   Navy steel        #243752
Border:         Frost             rgba(255,255,255,0.08)
Text primary:   Glacier           #F0F6FA
Text secondary: Mist              #9DB2C7
Text tertiary:  Steel             #6B7F94

Accent primary: Ocean Blue        #0066CC  (Download Now button bg) ← VERIFIED
Accent hover:   Cyan              #03BEFE  (button hover, brand dot in top bar) ← VERIFIED
Accent fg:      Pure white        #FFFFFF

Success:        Mint              #5EEAD4
Warning:        Pale gold         #FCD34D
Error:          Coral pink        #FB7185
```

**Note for Stitch**: Brand dot in top bar = Cyan `#03BEFE` (lighter, vibrant). Primary action button bg = Ocean Blue `#0066CC` (deeper, decisive). The 2-color play creates visual layering — dot is the "spark", button is the "mass".

**Vibe direction**: như "command center của icebreaker ship" — calmer, more procedural. Ocean Blue is decisive, less emotional than Wine Red. Cyan accents add "active circuitry" energy — VidCombo is "pro-grade tool", Svid is "cinematic experience". Same hierarchy structure, different temperature + slightly different brand personality.

### Typography (both brands)

- Font: **Inter** (already shipped)
- Weights used: 400 (body), 500 (button), 600 (title), 700 (action labels uppercase nếu có)
- Body: 13pt, line-height 1.4
- Title (video name): 14pt semibold, max 2 lines + ellipsis
- Meta (channel · duration · views): 11pt regular, secondary color
- Button label: 14pt medium
- Footer (quota): 11pt regular, tertiary color

### Iconography

- Lucide icons (already in app), 16pt size for inline, 20pt for action buttons
- Lightning bolt ⚡ for "Tải ngay" (energy = direct, immediate)
- Settings gear ⚙ for "Tuỳ chọn…" (configure = optional path)
- Snooze ⏰ for snooze (time = pause)
- Close ✕ for dismiss (small, top-right)
- Crown 👑 for upgrade (premium gating)
- Check ✓ for success states (mint/green)
- X-mark ✗ for error states (coral)

---

## 3. The 10 State Variants

Generate **10 screens × 2 brands = 20 total**. Naming convention:
`floating-popup-{state}-{brand}` (e.g., `floating-popup-loading-svid`).

### State 1 — Loading

**When:** User vừa copy URL, oEmbed/Tier A fetch chưa xong (<500ms typical, 5s timeout)

**Layout:**
- Top bar: brand dot (8pt) + brand name + ⚙ menu + ✕ dismiss
- 16:9 thumbnail area: skeleton shimmer (linear gradient pulse left-to-right, 1.5s loop)
- Title placeholder: 2 skeleton bars (full width + 60% width)
- Meta placeholder: 1 skeleton bar 40% width
- Action area: 2 buttons disabled state (greyed, không pulse)
- Footer: quota text "—" placeholder

**Vibe:** Anticipation. Not anxious. User biết popup đang load, không lo.

### State 2 — Video Preview (default success)

**When:** Tier A/B succeeded, có metadata đầy đủ

**Layout:**
- Top bar: brand dot + appName + ⚙ menu + ✕
- Thumbnail 16:9 with platform badge top-left corner (small pill, semi-transparent bg, platform logo + name)
- Title: 2 lines max, semibold
- Meta line: `{channel_name} · {duration} · {view_count}` — if oEmbed có; else gracefully degrade missing fields
- Primary action: **`⚡ Tải ngay`** (Wine Red bg / Arctic Blue bg)
- Secondary action: **`⚙ Tuỳ chọn…`** (transparent bg, border surface elev)
- Below actions: row of small affordances `[⏰ Tạm dừng]  [✕ Bỏ qua]` (text buttons, tertiary color)
- Footer: quota text "12 lượt còn lại hôm nay" (warning color khi <3)

**Vibe:** Confidence. User biết exactly mình đang download cái gì, primary action sáng rõ.

### State 3 — Fallback Preview (Tier C/D)

**When:** Tier C scrape success (OG image) hoặc Tier D (platform logo only)

**Layout (Tier C):**
- Same as State 2 but thumbnail có thể aspect ratio khác (square cho IG, vertical cho Threads)
- Subtle "Limited preview" microcopy below meta line
- Else identical

**Layout (Tier D):**
- Thumbnail area = solid color block (surface elev) + platform logo centered (40pt)
- Microcopy: "Preview not available" + URL truncated below
- Title field: hiển thị URL host + path (e.g., "instagram.com/p/Cabc123…")
- No channel/duration/views (none available)
- Same actions as State 2

**Vibe:** Honesty. Không giả vờ có metadata. Platform logo confirms "đây là feature limited cho platform này, không phải bug".

### State 4 — Non-Video URL (playlist / channel / search)

**When:** URL classifier nhận playlist / channel / search

**Layout:**
- Top bar identical
- Thumbnail area: stylized icon centered (40pt) — playlist icon for playlists, search magnifier for search, channel avatar shape for channels (m4 fix: YouTube oEmbed for channel rarely returns avatar — fallback to **stylized circular chip với initial letter from channel name** if available, else **platform logo** centered).
- Title: generated text — "YouTube Playlist (24 videos)" / "TikTok Channel @username" / "YouTube search" (use whatever metadata oEmbed returns; gracefully degrade fields)
- Meta line: link nguồn truncated to ~30 chars
- Primary action **CHANGES**: **`Mở trong Svid`** / **`Mở trong VidCombo`** (cùng button style as Tải ngay nhưng label khác — uses brand-aware appName substitution)
- Secondary action: ẩn (chỉ 1 primary — no "Tuỳ chọn" since this isn't a video)
- Footer: quota text persists

**Vibe:** Adaptive. Popup biết URL này không tải 1-click được, nó offer path đúng (mở app để chọn videos to download).

**Stitch note:** Em prefer Tier-D-style centered platform logo over channel avatar attempt — predictable, consistent, less janky than half-loaded avatar fallback.

### State 5 — Quota=0 Paywall

**When:** Free tier dùng hết quota daily (Svid: 15, VidCombo: 10)

**Layout:**
- Same skeleton as State 2 (thumbnail + title still shows)
- BUT primary button: **`👑 Nâng cấp Premium`** with subtle gold/amber gradient overlay (not garish)
- Below button: small text "Bạn đã dùng hết 15/15 lượt hôm nay" (Svid) / "10/10" (VidCombo)
- Secondary action: `Hôm nay đến đây thôi` (dismiss popup, accept rate limit)
- Footer: "Reset trong: 4h 23m" countdown (calculated from midnight reset)

**Vibe:** Warm pressure, không hostile. User chạm rate limit là moment teaching value. Crown icon + gold accent = upgrade is aspiration, not punishment.

### State 6 — Download Started

**When:** User đã click "Tải ngay", direct download path đã `enqueue` thành công + system notification fired

**Layout:**
- Top bar identical
- Thumbnail giữ nguyên + ✓ checkmark overlay top-right (animated 0.3s scale-in with subtle spring)
- Title giữ nguyên
- Replace 2-button row với **single status banner**:
  - Background: success/4 (subtle mint/green tint)
  - Icon: ✓ (mint color)
  - Text: "Đang tải xuống Downloads/" (primary text)
  - Subtext: tên file truncated nếu fit (tertiary text)
- Below banner: tiny progress bar (indeterminate, 2pt thick) — visual cue only (real progress in main app Downloads tab)
- **Auto-close timer: 4 seconds** (m2 fix — was 2s, too rushed for non-English readers)
- Countdown ring around small ✕ button top-right (alternative to progress dots — Stitch pick best metaphor) — **cancellable**: hover popup pauses countdown, click ✕ dismisses immediately

**Vibe:** Relief + momentum. Action confirmed, popup respectfully retreats — but gives user 4 seconds to see what just happened, with explicit cancel.

### State 7 — Download Complete (rare in popup — most users see auto-close before this)

**When:** User reopens popup từ tray sau khi download hoàn tất

**Layout:**
- Same as State 6 but text: "Tải xong!" + path link "Open in Finder" / "Open in Explorer"
- Single primary button: **`📁 Mở thư mục`**
- Secondary: **`✕ Đóng`**

**Vibe:** Closure. Popup acknowledges completion, gives 1 useful next-step.

### State 8 — Download Failed

**When:** Direct download path failed (extract error, format unavailable, network)

**Layout:**
- Same as State 6 but error tint
- Background banner: error/4 (subtle coral tint)
- Icon: ✗ (coral)
- Text: "Không tải được"
- Subtext: error message truncated 1 line (e.g., "yt-dlp: Video unavailable")
- Single primary button: **`Mở app để xem chi tiết`**
- Secondary: **`Bỏ qua`**

**Vibe:** Honest. Doesn't hide failure. Offers escalation path (open app for full error log).

### State 9 — Snoozed Banner (SEPARATE FORM FACTOR)

**Critical (M8 fix):** This is a **DIFFERENT popup form factor**, not a state of the default 300×420 popup. Stitch generate as separate design entity.

**Form factor:** **300×120 horizontal card** (different from default 300×420 vertical).

**When:** User force-show via tray icon click while snooze is active, OR triggered after user manually snoozes (toast-style confirmation)

**Layout:**
- Compact horizontal card 300×120
- Left: ⏰ icon (24pt) in muted accent color
- Right column (text):
  - Primary: "Floating capture đã tạm dừng"
  - Secondary: "Còn lại: 28 phút" / "Đến khi bạn bật lại"
- Bottom row: 2 inline text buttons `Bật lại ngay` (primary, accent color) + `Đóng` (secondary, tertiary text color)

**Vibe:** Subtle reminder, không pushy. User chủ động dismiss → này chỉ là "I see you, here's status", không cố giữ user.

**Implementation note:** Main popup engine resizes via `windowManager.setSize(Size(300, 120))` with 200ms ease animation when entering this state, restores to 300×420 on `resume`.

### State 10 — Offline / No Internet

**When:** oEmbed timeout 5s × 3 retries, no network detected

**Layout:**
- Same skeleton as State 3 Tier D
- Thumbnail area: stylized "wifi-off" icon centered, surface elev background
- Title: "Không có Internet"
- Subtext: "Không thể trích xuất metadata. URL đã sao chép vào clipboard."
- Primary action: **`Thử lại`** (retry oEmbed fetch)
- Secondary: **`Đóng`**
- Footer: "URL: youtube.com/watch?v=…" truncated for context

**Vibe:** Calm acknowledgment. Network error is not popup's fault — popup informs and offers retry, doesn't panic.

---

## 4. Microinteractions & Motion

**Critical rule**: motion should make popup feel **lighter than it is**, not heavier. Stitch lean toward subtle, fast (200-300ms), ease-out curves.

| Interaction | Animation |
|---|---|
| Popup spawn | Slide-up 12pt + fade-in, 250ms ease-out |
| Popup hide | Slide-down 8pt + fade-out, 200ms ease-in |
| Queue advance (next item) | Cross-fade 200ms |
| Button hover | Background tint shift 150ms, scale 1.0 → 1.02 |
| Button press | Scale 1.0 → 0.98 + accent darker 100ms |
| Action confirm (Download) | ✓ scale-in 300ms with spring overshoot 1.0 → 1.15 → 1.0 |
| Skeleton shimmer | Linear gradient sweep, 1.5s infinite |
| Idle timer countdown | Dots shrink linearly 2s before close |
| Drag move | Position follows cursor 1:1, no inertia |
| Queue thumbnail strip select | Dot indicator slide horizontally 200ms ease-out |

---

## 5. Queue Thumbnail Strip (when queue > 1)

**Goal**: User see queue length + current position glance, không cần navigate menu.

**Layout** (bottom of popup, ABOVE footer — quota footer always visible per §8 rule 8):
- Horizontal row of small thumbnails (32×24 each, 4pt gap), max 5
- Current item: full opacity + accent border 1.5pt + slight elevation (2pt shadow)
- Other items: 60% opacity, no border
- Below strip: text "3 of 5" centered, 11pt tertiary
- Click thumbnail → switch popup content to that item (200ms cross-fade)
- Tab indicator slides horizontally on switch (200ms ease-out)

**Metaphor (m3 fix):** **Browser tabs** — modern users grok this immediately (Chrome/Safari tab strip pattern). Each "tab" is a captured URL waiting for action. Em rejected "film negatives" — too obscure for younger users.

**Stitch may counter-propose:** "card stack" (peek + swipe) is alternative — works well on mobile pattern but desktop popup has more room for tabs strip. Em open to either.

---

## 6. Generated Image Prompts (cho Stitch tool calls)

Mỗi state generate qua `generate_screen_from_text` với prompt format dưới đây. Stitch dùng `apply_design_system` sau khi tạo design system entry để enforce consistency.

### Reusable design system prompt

```
DESIGN SYSTEM — Svid Floating Capture v2.2 / Svid brand:
- Platform: Desktop, Dark mode mandatory
- Form: Floating panel 300×420 portrait, 16pt corner radius, whisper-soft shadow
- Background: Pressurized void #121212, surface onyx #1A1A1A, elevated graphite #242424
- Border: smoke rgba(255,255,255,0.06)
- Text: Bone #F5F5F5 (primary), Ash #A0A0A0 (secondary), Charcoal #6E6E6E (tertiary)
- Accent: Wine Red #8D021F (use sparingly — single primary action only)
- Typography: Inter font, 13pt body, 14pt button, 14pt semibold title
- Vibe: nocturne cinematic — confident, restrained, tension-on-demand
- Generous breathing room: 16pt padding outer, 12pt inner gap

DESIGN SYSTEM — VidCombo brand variant:
- Same form factor
- Background: deep ocean #0E1B2C, slate #1A2A40, navy steel #243752
- Border: frost rgba(255,255,255,0.08)
- Text: Glacier #F0F6FA, Mist #9DB2C7, Steel #6B7F94
- Accent: Arctic Blue #2E7CD6
- Vibe: arctic command — calm, procedural, decisive
```

### Prompt template per state

```
[State name] of the Svid v2.2 floating capture popup.

CONTEXT: User just copied a {URL_TYPE} URL while browsing. Popup appears
in top-right corner of screen, floats above all other windows. This is
the {STATE_DESCRIPTION} state.

CONTENT:
- Top bar: 8pt brand dot ({brand color}), "{appName}" label,
  3-dot menu icon, X close icon
- {STATE-SPECIFIC CONTENT — see §3 above}
- Footer: "{QUOTA TEXT}"

EMPHASIZE:
- {state vibe word}
- Primary action stands out via accent color, secondary recedes
- No noise — every pixel earns its place

MOTION/INTERACTION (static screen — show resting state):
- {if applicable, e.g., "post-press button at 0.98 scale" or "skeleton mid-shimmer"}

DELIVER: Single PNG screen, 300×420 (or 300×560 if expanded state),
on dark mode wallpaper background to show floating panel context.
```

---

## 7. What I'm Looking For Stitch To Push Back On

Stitch là Creative Director, không phải executor. Specifically:

1. **Color temperature** — em đề xuất Wine Red (Svid) + Arctic Blue (VidCombo) nhưng Stitch có thể nhìn từ user emotional journey perspective (anxiety reduction khi click Download? tension build for upgrade?) → counter-propose nếu thấy Wine Red không đủ.

2. **Information density** — em propose "title + channel + duration + views" trong State 2 — Stitch có thể thấy quá nặng, propose strip xuống còn title + 1 meta line.

3. **Primary action label** — "Tải ngay" / "Tuỳ chọn…" có thể chưa optimal. Stitch suggest verb mạnh hơn / clearer differentiation 2 paths nếu cần.

4. **Queue visualization** — film negative metaphor là em throw out — Stitch có metaphor tốt hơn (carousel? card stack?).

5. **Microinteraction details** — em list ở §4 nhưng ý là defaults. Stitch propose signature interaction để popup feel nhẹ.

6. **State 5 (paywall)** — gold/amber accent có thể quá garish trên dark BG. Stitch propose alternative (subtle border glow? icon-only crown without color shift?).

7. **State 8 (failed)** — Coral error tint có thể clash với brand vibe. Stitch suggest approach khác (no color, just icon + text shift left-aligned?).

---

## 8. Constraints (MUST OBEY)

1. **No sidebar.** Đây là popup, không phải app — pattern không apply nhưng nhắc lại để rõ context.
2. **Brand-aware mọi UI surface.** Svid Wine Red KHÔNG được leak vào VidCombo. Stitch tạo separate screens per brand, không 1 set screens "swap colors".
3. **Inter font only.** Không google_fonts mới. Đã ship.
4. **No translucent backdrop.** Whisper-soft shadow OK. Vibrancy/blur thường gây lag perception.
5. **No emoji trong button label.** Use Lucide icons + text. (Spec dùng "⚡" ở đầu là illustrative; final dùng Lucide `Zap` icon.)
6. **Brand dot 8pt circle, không square, không rounded square.**
7. **Action button height 40pt minimum** — accessibility tap target.
8. **Footer quota text always visible** — không hide khi queue strip xuất hiện (thay vào đó, queue strip ở giữa, footer dưới).

---

## 9. Deliverables Expected

Stitch produce:

1. **1 design system entry**: "Svid Floating Capture v2.2 — Svid brand"
2. **1 design system entry**: "Svid Floating Capture v2.2 — VidCombo brand"
3. **20 screens**: 10 states × 2 brands, named per §3
4. **2-3 motion sketches** (optional): hover state transitions, ✓ scale-in animation as side-by-side mockup variants
5. **2 reference compositions** (optional): popup-in-context (popup floating over a YouTube browser tab screenshot) — 1 per brand — để Chairman thấy popup real-world feel

---

## 10. Process (M9 fix — batched with checkpoints to control compute cost)

Each Stitch generation = 30s-2min. 20 screens = 10-40 min total compute. Em pause at checkpoints below for Chairman review before next batch.

**Stage 1 — Foundation (1 generation × 2 design system entries)**
1. Stitch acknowledge brief understood, push back on §7 anywhere needed
2. Chairman approve Stitch pushbacks → final direction frozen
3. Stitch generate 2 design system entries (Svid + VidCombo)
   - **Cost:** ~1 minute total (DS entries are fast)
   - **Checkpoint:** Chairman review color tokens, font, roundness

**Stage 2 — Hero (2 generations)**
4. Stitch generate State 2 (default success) — Svid brand
   - **Checkpoint:** Chairman approve hero shot Svid before continuing
5. Stitch generate State 2 (default success) — VidCombo brand
   - **Checkpoint:** Chairman approve brand parity (Ocean Blue vs Wine Red feel right?)

**Stage 3 — Variant generation (parallel, 18 screens)**
6. Stitch parallel-generate States 1, 3, 4, 5, 6, 7, 8, 9 (separate form factor!), 10 — both brands
   - **Cost:** ~10-30 min depending on Stitch concurrency
   - **Checkpoint:** Chairman + CTO step through all 18 screens together

**Stage 4 — Export + Implement**
7. Stitch export design tokens (color hex, spacing scale, font sizes, shadow specs) for Flutter implementation
8. CTO implement Phase 2B per `Svid_v2_2_FloatingCapture_Improvement_Spec.md` §3.2B

**Pause point**: Chairman directed em report **before** invoking Stitch generation. Em deliver brief + spec → Chairman approves → em invoke Stage 1 + 2 with explicit cost expectation. Stage 3 only after Stage 2 hero approved.

---

## 11. Out of Scope (Phase 3+ deferred)

Stitch không cần touch:

- Onboarding screens (Accessibility permission prompt, hotkey customize)
- Settings card visual (dùng main app design system, đã có)
- Tray icon / menu visual
- macOS NSPanel proper subclass (engineering, no visual change)
- Drag-drop affordance visual (Phase 2C optional)
- Per-monitor saved position UX (engineering)
- Dailymotion + SoundCloud platform logos (asset sourcing)

---

## 12. Reference

- v2.2 Spec: [Svid_v2_2_FloatingCapture_Improvement_Spec.md](Svid_v2_2_FloatingCapture_Improvement_Spec.md)
- v2.1 Spec: [Svid_v2_1_FloatingCapture_Spec.md](Svid_v2_1_FloatingCapture_Spec.md)
- Active Stitch project: Svid Desktop — Final UI Design (ID: 10022260214920217805)
- Design tokens: [DESIGN.md](../DESIGN.md)
- Stitch registry: [STITCH.md](../STITCH.md)
- Brand identity: Svid "Nocturne Cinematic", VidCombo "Arctic Command"
