# Design prompt — Kushol Connect promotional landing page (`/`)

| | |
| --- | --- |
| **Status** | 🟢 Owner direction 2026-10-09 — supersedes the *Visual* and *Imagery* rows of `docs/design-reference/README.md` §7.1 **for the landing page only** |
| **Surface** | `applications/web` → `/` (and the matching `/download` look) |
| **Use with** | A design tool (Figma Make, Claude, v0, Stitch, Lovable…) or an AI coding agent. Paste everything from §1 down. A coding agent also follows §12 |
| **Unchanged** | The brand rules (logo, palette, typefaces — design-reference §1–§5), the Command Center look (§7.2), the never-fabricate rule |

---

## 1. Your role and the goal

You are a senior conversion designer and motion designer. Redesign the public landing page of
**Kushol Connect (কুশল কানেক্ট)** as a **modern, interactive, illustrated, feature-focused
promotional page** — a funnel that turns visitors into **pilot sign-ups (schools)**, **partner
applications** and **app downloads (guardians & students)**.

The page must feel alive (illustrated scenes that animate, sliders, interactive demos) and
**dense** (little dead white space, every scroll shows something useful), while staying credible
to a school principal in Bangladesh and fast on a low-end Android phone over 3G.

**What Kushol Connect is.** A school community platform for Bangladesh. It replaces chaotic
WhatsApp/Messenger groups with a verified, hierarchy-based network: **City → Institution →
Class/Section**. Students, guardians, teachers and school admins join only after the institution
verifies them, and are placed into the right class and section groups automatically. Official
notices reach exactly the right class. Later phases add AI study tools, a tuition marketplace,
campus commerce, fee payments and targeted campaigns for education brands.

## 2. Audiences and the one action for each

| Priority | Audience | Their question | Primary action |
| --- | --- | --- | --- |
| 1 | **School/college principals and admins** | "Will this bring order to our communication without work for my staff?" | **Join the pilot** (form, `#pilot`) |
| 2 | **Partners and education brands** (bookshops, uniform makers, coaching centres) | "Can I reach the right students and guardians in my city?" | **Apply as a partner** (form, `#partners`) |
| 3 | **Guardians and students** | "Is it safe, and where do I get the app?" | **Download the app** (`/download`) |
| — | Existing users | — | **Log in** (`/login`, secondary in the header) |

Every screen-height of scroll must offer a way to act: a primary CTA in the header, a
contextual CTA in every section, and a **sticky bottom CTA bar on mobile** (shows after the hero,
hides while a form is in view).

## 3. Brand system (binding — do not change)

| Element | Rule |
| --- | --- |
| Logo | Swirl + Bengali wordmark "কুশল" + "CONNECT" as one lockup, 28–32 px tall in the header. Never recolour, stretch, add effects or loop-animate the swirl (one ≤ 900 ms reveal is the maximum). White/knockout version only when supplied — never invert the PNG. Accessible name "Kushol Connect — Home" |
| Primary | Deep teal `#095777` — primary buttons, links, active states, key headings |
| Secondary | Slate teal `#386070` — secondary surfaces, icons, chart series |
| Swoosh gray | `#707070` — brand graphics only, never text |
| Neutrals | Paper `#FAFBFC` background, Ink `#111827` text (WCAG AA ≥ 4.5 : 1) |
| Tints/shades | A generated 50–950 scale of deep teal and slate teal — no one-off hex values |
| Promotional accent | **One** warm accent for highlights, illustration details and "new" badges — proposal **marigold `#F2A93B`** (`TODO: Confirm` with the owner). Never on body text; teal stays the CTA colour. No other hues (the current page's sky, purple, emerald and amber cards go) |
| Status | success `#15803D` · warning `#B45309` · danger `#B91C1C` — always with an icon or text, never colour alone |
| Type | **Hind Siliguri** for Bengali (display + UI), **Inter** for Latin and numbers. Never set Bengali in Inter. No all-caps for Bengali. Line-height: Bengali headings ≥ 1.3, Bengali body ≥ 1.6 (conjuncts and vowel signs need the room) |
| Shape | Cards 12–16 px radius, pill buttons and chips, 1 px borders at teal-100/slate-200, soft single-layer shadows; bigger radius (24 px) only for hero and feature panels |

## 4. Layout density — "less white space"

| Rule | Value |
| --- | --- |
| Section padding | 56–72 px desktop · 40–48 px mobile (the old 96 / 56 px rule is retired for the landing page) |
| Container | 1280 px max; illustrations, sliders and colour bands may bleed to the viewport edges |
| Section rhythm | Alternate surfaces (Paper → teal-50 → white → full-bleed deep-teal band) so sections read as distinct blocks without empty gaps |
| Overlap | Cards and illustrations may overlap a section edge by 32–64 px to tie sections together |
| Headings | Section intro = eyebrow chip + H2 + one line of body, max 2 lines total — no paragraph-long intros |
| Columns | Desktop sections use 2–3 columns or a split layout; never a narrow centred column surrounded by space |
| Readability floor | Body text max ~70 characters per line, 16 px minimum (15 px for Bengali captions is too small — keep 16) |

## 5. Illustration and art direction

- **Style:** original flat/semi-flat vector illustration with soft gradients and gentle depth —
  warm, optimistic, editorial, *not* childish or cartoon-mascot. Think "modern civic product",
  not "kids' game".
- **Bangladeshi context:** local school uniforms (white shirt with navy/teal, varied — with and
  without headscarf), a guardian with a phone at home or work, a teacher in a classroom, a school
  building with a courtyard, Chattogram/Dhaka streets as soft background shapes. Diverse,
  respectful, no stereotypes, no national monuments, flags or political symbols.
- **Palette:** only the teal scales, the one accent, neutrals and natural skin tones.
- **Recurring motifs:** chat bubbles turning into tidy cards, a hierarchy tree
  (City → Institution → Section) as connected nodes, verified tick badges, a notice "landing" on
  many phones at once, the brand swirl's curve as a background line (never the logo itself).
- **Ownership:** every illustration is newly made for Kushol (commissioned or generated and
  owned). Never use the CircleUp kit art, stock "happy students" photos or icon packs as
  illustrations.
- **Formats:** inline **SVG** with named layers/groups so parts can animate (target ≤ 30 KB
  gzipped each). Complex sequences may use **Lottie or Rive**, lazy-loaded below the fold, each
  ≤ 60 KB, with a static SVG poster frame. Every illustration has a static final frame for
  reduced motion.
- **Product UI:** where the page shows the app or the admin desk, use **real screenshots** of the
  current app or web console (in a device/browser frame), or a clearly stylised UI illustration
  built from the real screens. Never invent features the product doesn't have.

### Illustration set to produce

| # | Scene | Used in | Animation |
| --- | --- | --- | --- |
| I-1 | "Chaos → order": tangled WhatsApp-style bubbles and phones rearrange into a neat City → Institution → Section tree; the phone shows a class group with a pinned official notice | Hero | Plays once on load (≤ 1.6 s), then idle float ≤ 6 px |
| I-2 | Verified member: ID card + institution stamp + teal tick | Feature slide | Stamp lands, tick draws |
| I-3 | Auto-grouping: a roster sheet (CSV/Excel) splits into class and section groups | Feature slide, How it works | Rows fly into group cards |
| I-4 | One notice, right class: a notice card fans out to a cluster of phones of one section only | Feature slide | Fan-out + phones light up |
| I-5 | Safe chat: class group, clubs, DMs with a "Message request" gate | Feature slide | Bubbles appear; gate opens on accept |
| I-6 | School admin desk: laptop dashboard with roster, notices and sync status | Feature slide, Desk demo | Counters/rows populate |
| I-7 | AI study (coming soon): a phone scanning handwritten notes into a tagged card and MCQs | Feature slide | Scan line sweeps |
| I-8 | Tuition matching (coming soon): a requirement pin on a map matches nearby verified tutors | Feature slide | Radius ripple, matches pop in |
| I-9 | Campus store (coming soon): books, uniform, stationery on a school-scoped storefront | Feature slide, Partners | Items drop onto a shelf |
| I-10 | Targeted reach: audience filter chips (City → Class → Group) narrowing a crowd to a segment | Partners | Chips toggle, crowd narrows |
| I-11 | Guardian at home receiving a notice on a phone | Download/app promo | Notification slides in |
| I-12 | Teacher | Roles section | Static or subtle idle |
| I-13 | Principal/admin | Roles section | Static or subtle idle |
| I-14 | Small spot illustrations: empty FAQ, form success, 404 | Various | Static |

## 6. Page structure — the funnel, top to bottom

`bn` copy is primary; every string also exists in English. Headline lengths below are for
Bengali (usually 20–30 % longer than English).

| # | Section | Purpose | Content and layout | Interaction and motion |
| --- | --- | --- | --- | --- |
| 0 | **Announcement bar** (dismissible) | Urgency without hype | "পাইলট প্রোগ্রামে নিবন্ধন চলছে — প্রথম ২–৩টি প্রতিষ্ঠান" + link to `#pilot`. Thin, deep-teal | Slides down once; close (×) remembered for the session |
| 1 | **Header** (sticky, 64 px) | Navigation + always-visible CTA | Logo · Features · For institutions · For partners · Download · বাং/EN toggle · Log in (ghost) · **Join the pilot** (primary). Mobile: logo, toggle, menu button → full-height sheet | Shrinks to 56 px with a shadow after scroll; active section underline follows scroll |
| 2 | **Hero** | Attention: the promise in 5 seconds | Left: eyebrow chip, H1 (≤ 2 lines bn), one-line subhead, CTAs **Join the pilot** + **Download app**, 3 fact chips ("প্রতিষ্ঠান-যাচাইকৃত সদস্য", "বাংলা ও ইংরেজি", "স্কুলের জন্য বেসিক যোগাযোগ বিনামূল্যে"). Right: illustration I-1 with the real app screen inside the phone. Mobile: text first, illustration below at ~70 % width | I-1 sequence; floating notice and "verified" chips drift ≤ 6 px. **The H1, subhead and CTAs are visible on first paint — never fade them in** (they are the LCP) |
| 3 | **Before / After** | Interest: name the pain | Draggable comparison slider: left "আজকের WhatsApp গ্রুপ" (personal numbers exposed, notices buried, unknown members, no verification) vs right "কুশল কানেক্ট" (verified members, pinned official notices, section-scoped groups, no personal numbers shared). 4 contrast rows below | Drag handle (mouse, touch, ←/→ keys); a one-time hint nudges the handle when in view |
| 4 | **Features slider** — the centrepiece | Desire: show everything the platform does | See §7 | Auto + manual slider (§7) |
| 5 | **How it works** | Remove effort fear | 3 steps in a row (stacked on mobile): ① register and upload the roster (CSV/Excel or LMS sync) ② verified members land in class and section groups automatically ③ send notices and chat. Each step = small illustration + title + one line | A connecting path draws itself as you scroll; step numbers count in |
| 6 | **Built for everyone on campus** | Self-identification | Tabs: Guardians & students · Teachers · Institutions · Partners. Each panel: role illustration, 3 benefits with ticks, one role CTA (download / pilot / partner) | Manual tabs only (no autoplay here); panel crossfade + slide 200 ms; swipe between tabs on mobile |
| 7 | **School admin desk demo** | Proof the product is real | Browser-framed console (real `/school` screens) with 3 clickable hotspots: Roster · Notices · Sync. Clicking one plays a short scripted demo (cursor uploads a CSV → groups appear → a notice is sent) | Plays when in view, once; replay button; static screenshots under reduced motion |
| 8 | **ROI calculator** | Personal payoff for the principal | Big card: 3 range sliders with number inputs (students, notices/month, fee cycles/year) → "hours saved per year" with a count-up, a small bar comparison (manual vs Kushol). **Formula and "an estimate, not a quote" always visible.** CTA "Get these hours back — join the pilot" | 400 ms count-up per change; instant under reduced motion |
| 9 | **Trust and safety** | Answer the parent's and principal's fear | Hierarchy diagram (City → Institution → Section) + 4 tiles: institution verification · each institution's data kept separate · Message request for outside contacts · role-based access and audit log. Dark deep-teal band for contrast | Nodes light up in sequence when in view |
| 10 | **Pilot programme** (replaces "testimonials" until real ones exist) | Action #1 | Left: what a pilot institution gets (onboarding, staff training, free basic communication — each `TODO: Confirm`), "২–৩টি প্রতিষ্ঠান" seat callout. Right: the pilot form (institution name, contact name, phone, city, students, message) | Inline validation, success state with illustration I-14 |
| 11 | **For partners and brands** | Action #2 | Illustration I-10 + pitch (school-scoped storefronts, targeted campaigns by city/class/section — "coming soon" where not live) + partner inquiry form | Chips animate the audience narrowing |
| 12 | **Get the app** | Action #3 | Illustration I-11, Google Play / App Store badges and QR. Until store links are live the badges show "শীঘ্রই আসছে / Coming soon" (disabled, not fake links) | Phone tilts slightly on pointer move (desktop only, ≤ 4°) |
| 13 | **FAQ** | Remove last objections | 5–7 questions in an accordion (setup needed, data safety, how groups are created, Excel import, how to join the pilot, cost, languages) | Height animation 250 ms |
| 14 | **Final CTA band** | Last push | Full-bleed deep-teal band: one line + **Join the pilot** + **Download app** | Background swirl-curve line slowly drifts (stops under reduced motion) |
| 15 | **Footer** | Navigation and legal | Logo (knockout when supplied), one-line blurb, links (sections, Download, Log in), contact email `TODO: Confirm`, Privacy, Terms, © year | — |
| — | **Mobile sticky CTA bar** | Keep the action in reach | Two buttons: **Join the pilot** · **Download**, safe-area aware | Slides up after the hero; hides when a form or the footer is visible |

## 7. Features section — auto + manual slider (the main ask)

**Layout — desktop ≥ 1024 px ("spotlight"):** left column = vertical list of feature tabs
(icon, title, one-line benefit, status chip); the active tab expands and shows a **progress bar
that fills for the autoplay duration**. Right column = large panel (24 px radius, teal-50
surface) with the feature's animated illustration, a 3-bullet benefit list and a small CTA. A
category filter row above: **সব · প্রতিষ্ঠান · শিক্ষক · অভিভাবক ও শিক্ষার্থী · পার্টনার**.

**Layout — tablet 640–1023 px:** category chips + one slide at a time with the next slide
peeking (≈ 12 %), arrows on the sides.

**Layout — mobile < 640 px:** horizontally swipeable cards (≈ 88 % width, scroll-snap, next card
peeking), illustration on top, text below; dots with the active dot showing autoplay progress;
category chips scroll horizontally.

**Behaviour:**

| Rule | Value |
| --- | --- |
| Autoplay | Advances every **6 s**, loops back to the first slide of the current category |
| Pauses when | Pointer hovers the slider · any control or slide has keyboard focus · user touches/drags · the slider is off-screen (IntersectionObserver) · the browser tab is hidden |
| Resumes | 6 s after the last interaction ends; **never resumes** after the user presses Pause |
| Manual | Previous/next arrows · dots or the tab list · swipe/drag with momentum and snap · ←/→ keys when focused · clicking a category chip jumps to its first slide |
| Pause / Play button | Always visible, labelled (WCAG 2.2.2) |
| Transition | 400 ms slide + fade; illustration animates in after the slide settles (≤ 1.2 s) |
| Reduced motion | No autoplay, no slide animation (instant swap), static illustrations; all manual controls stay |
| Accessibility | WAI-ARIA APG carousel pattern: region with `aria-roledescription="carousel"`, slides labelled "৩ / ১২ — …", live region polite only when manually changed, off while autoplaying; 44 px touch targets |

**Feature slides** (status = what the chip shows; the owner confirms each before launch —
`TODO: Confirm`):

| # | Feature (bn / en) | Category | Status chip | Illustration | Grounded in |
| --- | --- | --- | --- | --- | --- |
| F-1 | যাচাইকৃত স্কুল নেটওয়ার্ক / Verified school network | All, Institutions | Live in pilot | I-2 | modules 03, 04 |
| F-2 | স্বয়ংক্রিয় শ্রেণি ও শাখা গ্রুপ / Automatic class & section groups | Institutions, Teachers | Live in pilot | I-3 | 04 |
| F-3 | অফিশিয়াল নোটিশ বোর্ড ও পুশ নোটিফিকেশন / Official notices + push | All | Live in pilot | I-4 | 05, 06 |
| F-4 | নিরাপদ চ্যাট — ক্লাস, ক্লাব, মেসেজ রিকোয়েস্ট / Safe chat (class groups, clubs, DMs with message request; photo, PDF, voice) | Guardians & students, Teachers | Live in pilot | I-5 | 05 |
| F-5 | রোস্টার ইমপোর্ট ও LMS সিঙ্ক / Roster import (CSV/Excel) + LMS sync + year-end migration | Institutions | Pilot | I-3 | 14, 04 |
| F-6 | স্কুল অ্যাডমিন ডেস্ক / School admin desk on the web | Institutions | Live in pilot | I-6 | 07 |
| F-7 | এআই স্টাডি হাব — নোট স্ক্যানার ও অটো-সিটি / AI Study Hub (notes scanner, auto class tests) | Guardians & students, Teachers | Coming soon | I-7 | 08 |
| F-8 | শিক্ষকের জন্য দুর্বলতা বিশ্লেষণ / Pain Point Matrix for teachers | Teachers, Institutions | Coming soon | I-6 variant | 09 |
| F-9 | টিউশন মার্কেটপ্লেস / Tuition marketplace (verified tutors nearby) | Guardians & students | Coming soon | I-8 | 10 |
| F-10 | ক্যাম্পাস স্টোর / Campus store (books, uniforms, stationery) | Partners, Guardians & students | Coming soon | I-9 | 11 |
| F-11 | অনলাইনে ফি পরিশোধ / Fee payments (bKash, Nagad, SSLCommerz) with PDF receipts | Institutions, Guardians | Coming soon | I-6 variant | 12 |
| F-12 | টার্গেটেড ক্যাম্পেইন ও ইভেন্ট / Targeted campaigns & events | Partners | Coming soon | I-10 | 13 |

"Coming soon" slides use the same design with a muted accent chip and a "Notify me / join the
pilot" CTA — never present them as available today.

## 8. Motion system

| Token | Value | Use |
| --- | --- | --- |
| `motion.fast` | 150 ms | Hover, press, chip toggles |
| `motion.base` | 250 ms | Accordions, tabs, menus |
| `motion.slow` | 400 ms | Slides, count-ups, section reveals |
| `motion.scene` | ≤ 1.6 s | Illustration sequences (once per view) |
| Easing | `cubic-bezier(0.22, 1, 0.36, 1)` (ease-out-quint) for enters; ease-in-out for loops | — |
| Reveal | Fade + 16 px rise, stagger 60 ms, **once** per element | Below-the-fold content only |
| Idle loops | ≤ 6 px float, ≥ 5 s period, max 3 looping elements on screen | Hero chips, final band line |
| Parallax | ≤ 20 px, desktop pointer devices only | Hero and app-promo illustrations |
| Press | Scale 0.97 + darker fill | All buttons |

Rules: animate only `transform` and `opacity`; no scroll-jacking, no page-wide smooth-scroll
libraries; pause every loop when off-screen; no animation blocks reading or input; nothing flashes
more than 3 times a second. **`prefers-reduced-motion: reduce` → every autoplay off, reveals
instant, illustrations show their final frame, count-ups jump to the value.**

## 9. Responsive rules

| Breakpoint | Rule |
| --- | --- |
| 360 px (design here first) | One column; hero text then illustration; 16 px gutters; nothing overflows horizontally; sticky CTA bar |
| 640 px | Two-column grids for steps and trust tiles; slider shows a peek |
| 768 px | Tablet: header menu still a sheet; forms two-column where fields are short |
| 1024 px | Full nav; split hero; spotlight features layout; ROI card beside its copy |
| 1280 px+ | 1280 container; illustrations and bands bleed to the edges |

Touch targets ≥ 44 px; inputs ≥ 16 px font (no iOS zoom); safe-area insets respected; works in
portrait and landscape.

## 10. Copy and content rules (never fabricate)

- **No invented proof.** No testimonials, names, school names, logos, user counts, percentages,
  ratings or awards unless the owner supplies them. The current page's quotes (named
  headmaster, teacher, guardian), "100 % verified", "Zero spam", "99.8 % delivery",
  "Bangladesh's first", "bank-grade encryption", "data sovereignty compliance", "24/7 support"
  and the six-division "rolling out nationwide" strip are **removed** — or kept only if the owner
  confirms them in writing.
- **No "LLM/AI auto-grouping" claim.** Groups are created by rules from the roster and the
  hierarchy (modules 04, 14), not by an AI model. AI appears only in the "coming soon" AI Study
  Hub and Pain Point Matrix slides.
- **No end-to-end-encryption claim.** Messages are stored on the platform's servers.
- **Real numbers only:** the ROI calculator (with its formula and disclaimer) and the pilot seat
  count ("২–৩টি প্রতিষ্ঠান", from the business plan) are the only figures on the page.
- **Voice:** Bengali first, warm and direct, short sentences, verbs in CTAs
  ("পাইলটে যোগ দিন", "অ্যাপ ডাউনলোড করুন"). English is a faithful translation, not a different
  pitch. Bengali digits in Bengali copy.
- Unknown facts (contact email, store links, pilot benefits, price) are written as
  `TODO: Confirm` placeholders in the design, not guessed.

## 11. Quality bar

| Area | Requirement |
| --- | --- |
| Performance | LCP < 2.5 s on "Fast 3G" mobile, CLS < 0.1, INP < 200 ms; hero illustration inline SVG (no large raster); below-fold illustrations and Lottie/Rive lazy-loaded; images AVIF/WebP with explicit sizes; fonts subset (`bengali`, `latin`) with `font-display: swap` |
| Accessibility | WCAG 2.2 AA: contrast, visible focus rings, keyboard-complete sliders/tabs/comparison, labelled form fields with inline errors, `lang="bn"`/`lang="en"` set, decorative art `aria-hidden`, meaningful art with bn/en alt text |
| Bilingual | Every visible string in both languages; layouts tested with the longer Bengali strings; language toggle keeps scroll position |
| Theme | Light first; a dark variant follows the same tokens (`prefers-color-scheme`), illustrations get a dark-surface version or sit on a light card |
| SEO | One H1; semantic sections; Open Graph image per language; JSON-LD Organization |

## 12. Deliverables

**From a design tool:**

1. Desktop (1440 px) and mobile (390 px, checked at 360 px) frames for every section in §6, in
   Bengali, plus the hero, features and forms in English.
2. Component sheet with states: buttons, chips, status chips, feature slider (autoplaying with
   progress, paused, manual, reduced-motion), role tabs, comparison slider, ROI card (valid,
   invalid input), forms (empty, error, submitting, success), accordion, sticky CTA bar, mobile
   menu sheet, announcement bar.
3. The illustration set I-1…I-14 as layered SVG (and Lottie/Rive where noted) with static
   poster frames.
4. A motion spec (prototype or table) for the hero sequence, feature slider, how-it-works path,
   desk demo and count-up — with reduced-motion versions.
5. A list of every `TODO: Confirm` placeholder for the owner.

**From an AI coding agent working in `applications/web`** (additionally):

- Read `applications/web/AGENTS.md` first (this Next.js version differs from training data —
  read the guide in `node_modules/next/dist/docs/` before writing code).
- Colours, radii, fonts and motion only from `src/theme` (`tokens.ts` → `pnpm theme:generate` →
  `theme.css`); add the accent and motion tokens there, not as Tailwind palette classes
  (`sky-`, `purple-`, `emerald-`, `amber-` go).
- Every string in `src/i18n/bn.json` and `en.json` under `landing.*` (catalog parity test must
  pass); remove the fabricated keys listed in §10.
- Split `src/components/landing/home-page.tsx` into one component per section; keep the static
  parts as Server Components and make only the interactive parts (`FeatureSlider`,
  `BeforeAfter`, `RoleTabs`, `DeskDemo`, `RoiCalculator`, forms, sticky bar) client components.
- Use `framer-motion` (already a dependency) with `useReducedMotion`; no new carousel or
  animation library unless it is lighter than writing the slider (record the choice in
  module 07 `07-progress.md`).
- Keep the existing `RoiCalculator` formula (`ROI_ASSUMPTIONS`), `PilotForm`,
  `VendorInquiryForm` and `DownloadButtons` behaviour; restyle them.
- Update module 07's `04-frontend-tasks.md` §2.1 (layout), §5 (motion table) and §6
  (responsive) to match, and add unit tests for the slider (autoplay, pause conditions,
  keyboard, reduced motion).
- Agent-side checks only: `pnpm format:check`, `pnpm lint`, `pnpm typecheck`, `pnpm test`.
  Never start the dev server or a browser against it — the owner runs and reviews the page
  (Gate 1) and runs Playwright/Lighthouse.
