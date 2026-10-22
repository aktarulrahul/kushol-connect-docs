# Command Center Web — Solution Approach

**Module:** `07-command-center-web` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

Written **before** any task list and any code (`docs/prompt/prompt-build.md` §4 step 1).

---

## 1. Domain Model

### 1.1 Entities

| Entity | Description | Owned here? |
| --- | --- | --- |
| `landing_leads` | Public funnel capture: `type ∈ pilot_registration\|vendor_inquiry\|download_click`, contact, school/city, message, `status ∈ new\|contacted\|converted\|archived`, source + utm | Yes (api + web screens) |
| `vendor_accounts` | Partner/company record with Super-Admin approval lifecycle `pending → approved\|rejected`, `approved ⇄ suspended`; consumed by module 11 | Yes (api + web screens) |
| `AuditLog` (read model) | 01's append-only `audit_log`, read-only viewer | No — 01 owns |
| `User` / `VerificationRequest` | 03 identities + join queue evidence | No — 03 owns |
| `City` / `School` / `Section` / `MigrationRun(+Items)` | 04 hierarchy + migration | No — 04 owns |
| `Notice` / `MediaAsset` / custom `ChatGroup` | 05 notices, attachments, club groups | No — 05 owns |
| Revenue/campaign data | 11/12/13 exports | No — placeholder states only |

### 1.2 Relationships

```text
landing_leads.type = vendor_inquiry ──1:1──▶ vendor_accounts (pending)   [created together]
vendor_accounts ──approved──▶ module 11 storefront access (later consumer)
landing_leads ──converted──▶ 04 school (manual pipeline step, explicit)
admin screens ──REST──▶ 03 verification · 04 tenants/migration · 05 notices/media/clubs · 01 audit
/school dashboard ──GET /institution/stats──▶ 04 counts + 03 pending + 05 notices (this module aggregates)
```

### 1.3 Invariants

| ID | Invariant | Enforced by |
| --- | --- | --- |
| `WEB-INV-001` | A lead's `status` only moves forward along `new → contacted → converted\|archived`; `new` is never re-entered | api service transition table |
| `WEB-INV-002` | A `vendor_accounts` row exists iff its inquiry lead exists (same transaction) | api service tx |
| `WEB-INV-003` | Only `approved` partners get non-shell portal access; shell state always reflects server status | api + `/partner` gating |
| `WEB-INV-004` | Web renders data only from the generated client; no direct DB access from any Server Component/Action | ESLint boundary + CI |
| `WEB-INV-005` | Destructive UI actions always pass through a confirm step that names the object and the consequence | Shared `ConfirmDialog` primitive usage rule |

## 2. Module Boundary

**Owns (writes):** `landing_leads`, `vendor_accounts` tables + their endpoints; the web route
tree (`/`, `/download`, `/admin/*`, `/institution/*`, `/partner`), per-role layouts + middleware, ROI
config constant, SEO suite, portal shells and nav; `landing`/`school`/`partner` catalog namespaces
(additive to 02's whitelist, parity-gated).

**Reads from other modules (via their exported service functions only):**

| Module | What | Why not duplicated |
| --- | --- | --- |
| 01 | `audit.Record`, `audit_log` scoped reads, error envelope, `/healthz` | Append-only store + infra live in 01 |
| 03 | session auth chain (`auth.Authenticate/RequireRole`), verification queue endpoints, `GET /institution/users` | Identity + verification rules are 03's |
| 04 | `POST/PATCH /admin/schools`, `POST /admin/cities`, picker reads, `POST /institution/sections*`, migration create/get/commit, counts | Hierarchy truth lives in 04 |
| 05 | notices CRUD/pin, media presign/confirm, custom-group approval | Communication semantics live in 05 |
| 02 | tokens, primitives, `LocaleProvider`/`t()` | One visual API |

**Cache keys / tags revalidated / consumed:** see `06-integration-tasks.md` §4.

## 3. Lifecycle

```text
landing_leads:  NEW ──contact──▶ CONTACTED ──won──▶ CONVERTED
                   └──────────────────────archived──▶ ARCHIVED
vendor_accounts: PENDING ──approve──▶ APPROVED ──suspend──▶ SUSPENDED ──(re-approve)──▶ APPROVED
                      └──reject──▶ REJECTED ──(re-approve, OQ-5)──▶ APPROVED
migration (04-owned, driven by this module's wizard):
                DRAFT ──zero-ERROR preview──▶ PREVIEWED ──commit──▶ COMMITTING ──▶ COMMITTED
```

| From | Action | To | Guards | Side effects |
| --- | --- | --- | --- | --- |
| lead `new` | Super Admin marks contacted/converted/archived | per transition table | role + transition validity (INV-001) | audit-logged |
| `PENDING` partner | approve / reject(reason) | `APPROVED` / `REJECTED` | Super Admin; reason ≥ 10 chars on reject | audit; `/partner` state changes |
| `APPROVED` partner | suspend(reason) | `SUSPENDED` | Super Admin; reason required | audit; portal access revoked |
| run `DRAFT` | zero-ERROR preview (`dryRun:false`) | `PREVIEWED` | 04 re-validates items | none applied |
| run `PREVIEWED` | commit | `COMMITTING → COMMITTED` | 04 worker; 5/hour/school | new-session sections live; audit (04) |

## 4. Rendering & Caching

| Surface | Rendering | Cached read | Tags |
| --- | --- | --- | --- |
| `/` landing sections | Static generation + ISR (content editable without redeploy) | CDN + Next data cache | `landing:content` |
| `/download` | Static + ISR (flag-gated link readiness) | CDN | `landing:content` |
| `/login` | Dynamic (03 screen) | no-store | — |
| `/admin/*` | Dynamic, Super Admin layout, server auth gate; tables hydrate via TanStack Query | no-store (admin reads never cached) | mutations revalidate `admin:*` |
| `/institution/*` | Dynamic, School Admin layout; tables via TanStack Query; migration status via poll | no-store | mutations revalidate `school:{id}:stats`, reuse 05's `notices:*` |
| `/partner` | Dynamic, gated shell (pending/approved state from api) | no-store | — |
| Locale bn/en | Cookie-stored preference; RSC reads it for first paint | — | — |

## 5. Configuration — the two lists

| Owner can change in the admin | Fixed in code |
| --- | --- |
| *(Phase 1: none in-UI — dashboard/config surfaces come with modules 11–13; noted so scope does not creep)* | `ROI_ASSUMPTIONS` (minutes per notice / per fee student — single constant, `TODO: Confirm` values) |
| Launch-city flag filter is server config (04) surfaced in admin cities list | Rate limits (`leads` class: 10/h/IP create, 3/min burst) |
| Download URL readiness flag (`NEXT_PUBLIC_DOWNLOAD_URLS_READY`) | Route structure, role→layout mapping, middleware order |
| Contact email/phone in the footer (catalog keys, content change) | Formula shape of the ROI estimate; bn-first assembly of the notice body |

## 6. Security

- **Public surface:** `POST /api/v1/leads` and `POST /api/v1/partner/register` are the only
  unauthenticated writes — zod-validated (shared schemas), rate-limited in the `leads` class, no
  PII beyond contact fields, store nothing else; utm/source derived server-side.
- **Portal auth:** middleware checks session-cookie **presence only** for redirects; every real
  decision (authenticate → role claims → tenant scope) happens api-side via 03's chain — the web is
  never the authority. Mutations carry the `X-CSRF-Token` header (03 sessions).
- **Tenant scope:** School Admin screens send no `schoolId`; scope comes from claims server-side
  (`WEB-BR-008`). Super Admin routes require the role claim in the layout gate and again at the api.
- **Validation:** every form and every Route Handler re-validates with the same zod schemas from
  each app's `src/i18n`; server errors map RFC-7807 codes → `validation.*`/`errors.*` catalog keys.
- **Privacy:** lead data is contact-minimal; the audit viewer is read-only; no secrets in client
  bundles (`NEXT_PUBLIC_*` limited to site URL + download flag).
- **Tenant-scope rule per table:** `landing_leads` platform-wide (Super Admin reads; public writes
  create rows with no tenant), `vendor_accounts` platform-wide (Super Admin lifecycle), all
  rendered school data scoped by claim.

## 7. Accessibility & Motion

Motion is purposeful only: the ROI result counts up so the eye lands on the payoff; wizard panels
slide to show progression; toasts/confirm dialogs use standard enter transitions. Every animation
has a `prefers-reduced-motion` static variant. Portals are keyboard-complete: TanStack tables
support full tab/arrow navigation with visible focus, wizards manage focus per step and restore it
on dialog close, the locale toggle announces the language change. Details in `04` §5/§7; axe
(WCAG 2.2 AA) gates every screen in CI.

## 8. Failure Scenarios & Recovery

| # | Failure | Detection | Impact | Recovery |
| --- | --- | --- | --- | --- |
| 1 | api down / 503 | fetch errors at RSC or client | Landing static/ISR still serves; portals show error boundary with retry + request id; lead submit retries, input kept | User retries; no silent loss |
| 2 | Neon cold start (slow first query) | api latency | Slower first portal load; skeletons show | Warm-up ping (15); TTL caches soften reads |
| 3 | `CONFLICT` on stale rows (partner decided elsewhere, run committed, request decided) | RFC-7807 status | Row-level refresh message; list revalidates | Self-heals on refetch |
| 4 | R2 attachment failure in composer | presign/confirm 5xx | Publish blocked with retry copy; text-only notice still possible | Retry upload |
| 5 | Migration commit job stuck `COMMITTING` | status page poll shows non-terminal run | Banner explains "applying…"; no double commit (api guards) | 04 worker resumes/alerts |
| 6 | Rate limit hit on public forms | `RATE_LIMITED` problem | Polite copy, cooldown shown | Auto after window |

## 9. Performance

- Landing CWV budgets on 3G-fast: LCP < 2.5 s (static HTML, hero image priority + AVIF/WebP, fonts
  self-hosted via `next/font` with `bengali`+`latin` subsets), CLS < 0.1 (reserved media boxes,
  no layout-shifting banners), INP < 200 ms (calculator math is trivial, hydration kept small).
- Portals: dynamic but cheap — paged tables (25/page), TanStack Query caching, no chart lib until
  modules 09/12 (Recharts is *their* dependency).
- Bundle: new deps for web are TanStack Table + TanStack Query (tree-shaken, ~12 kB gzip both) and
  nothing else beyond module 02 primitives; landing route ships no admin JS.

## 10. Alternatives Considered

### Option A — Server Components + Server Actions (RSC-first) · Option B — client-rendered SPA calling api

| | A | B |
| --- | --- | --- |
| Advantages | SEO-native landing; server-side auth gate before any HTML; smallest client JS; api errors typed from generated client | Simpler mental model for dense interactive tables; one rendering mode |
| Disadvantages | Two rendering modes to keep straight; Server Actions must still route through the generated api client | Terrible SEO without a second SSR layer; auth gating shifts to client; larger bundles |
| Complexity / weight | Low-medium; uses Next.js App Router as intended | High double-layer for the funnel |

**Recommendation:** A — landing is static/ISR, portals dynamic RSC behind the layout gate;
TanStack Query only where tables need client interactivity. SPA rejected primarily on SEO and
auth-gate grounds.

### Option C — TanStack Table · Option D — AG Grid

| | C | D |
| --- | --- | --- |
| Advantages | Headless, MIT, composes with module 02 table shell; keyboard-complete by default | Enterprise features (pivots, Excel export) out of the box |
| Disadvantages | We wire selection/keyboard ourselves (small, spec'd) | License cost + ~120 kB+ weight for features Phase 1 does not need |
| Complexity / weight | Low | High (license audit + bundle on a BDT-15k-class audience's network) |

**Recommendation:** C — AG Grid rejected on license weight (`tech-stack.md` pins TanStack Table).

### Option E — ISR for landing · Option F — fully static

| | E | F |
| --- | --- | --- |
| Advantages | Copy/OG changes go live without redeploy; still CDN-fast | Absolute simplest |
| Disadvantages | Tag machinery to maintain (small) | Every copy tweak = rebuild/deploy; slows bilingual content fixes |
| Complexity / weight | Low | Lowest |

**Recommendation:** E with `landing:content` tags; revisit only if ISR shows no benefit by module 15. **ADR:** record the RSC/ISR decisions in this module's `07-progress.md`.

## 11. Assumptions & Risks

| # | Assumption / risk | Impact if wrong | Mitigation |
| --- | --- | --- | --- |
| 1 | 03/04/05 endpoints land their contracts before 07 UI wiring | Portal screens stubbed at build | Specs frozen at Phase-1 review; 07 consumes only generated types |
| 2 | Additive count exports (04/03/05 → stats) agreed | Dashboard cards degrade to queue-derived counts | Declared in `06` §3 with owners; fallback computed from existing list endpoints |
| 3 | ROI assumptions (OQ-1) may over/under-claim | Trust damage with principals | Formula + assumptions on-screen; estimate label; Rahul confirms values |
| 4 |_bn-first assembled notice body (OQ-4) renders awkwardly in app | Readability complaint | Fixed separator + caps; 05/app review at Phase-1 contract review |
| 5 | Partner flow value depends on module 11 arriving | Approved partners sit in a shell | Shell explains roadmap; 07 keeps leads pipeline useful independently |
| 6 | Shared VPS budget tight (2 vCPU) | Portal SSR latency spikes | Static/ISR landing, paged tables, no SSR-heavy client trees; budgets tested in module 15 |
