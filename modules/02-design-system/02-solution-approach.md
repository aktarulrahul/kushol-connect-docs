# Design System — Solution Approach

**Module:** `02-design-system` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

Written before any task list and any code (`docs/prompt/prompt-build.md` §4 step 1). The domain is **the product's visual API** — design tokens, bilingual string catalogs and UI primitives: the two things every screen in every app is made of.

---

## 1. Domain Model

### 1.1 Entities

| Entity | Description | Owned here? |
| --- | --- | --- |
| Design token (semantic) | Named theme value — `color.*`, `space.*`, `radius.*`, `type.*`, `motion.*`; source in each app's `src/theme`, compiled to Tailwind v4 `@theme` (web) and the NativeWind theme (app) | Yes |
| Color scale | 10-step tints/shades generated in code from deep teal `#095777` + paper/ink neutrals — never hand-picked per component (`design-reference` §2) | Yes |
| String catalog | `bn.json` / `en.json` in each app's `src/i18n`; flat dot-namespaced keys → `{bn, en}` values (schema: `03-backend-tasks §2`) | Yes |
| Translation key | Logical id `namespace.name`; namespaces (registry, one owner module each): `common`, `validation`, `errors`, `auth`, `verification`, `hierarchy`, `chat`, `notices`, `notifications`, `settings`, `landing`, `admin`, `school`, `vendor`, `ai`, `analytics`, `tuition`, `marketplace`, `commerce`, `payments`, `ads`, `events`, `sync`, `ops`. A module adding a namespace updates this registry in its Stage 3 docs sync | Yes |
| Web primitive | shadcn-style component hand-written in `applications/web/src/components/ui/`, token-styled, a11y-complete | Yes |
| RN primitive | NativeWind component mirroring the web inventory, on radix-primitives/zeego where useful | Yes |
| Brand asset | Logo lockup/monogram, app icon, splash, notification small icon — derived from `docs/design-reference/brand/` (files owner-supplied; usage owned here) | Yes (usage) |
| Icon set | lucide-react (web) / lucide-react-native (app) behind a thin token-sized wrapper | Yes (wrapper) |

### 1.2 Relationships

```text
docs/design-reference (brand truth — sampled palette, fonts, logo rules)
        │ encoded as
        ▼
applications/web (own repo)                         applications/app (own repo)
├─ src/theme tokens ──► Tailwind @theme             ├─ src/theme tokens ──► NativeWind theme
│    ──► src/components/ui/* ──► screens (07+)      │    ──► RN primitives ──► screens (03/05/08/…)
└─ src/i18n bn.json / en.json ──► t(key, params)    └─ src/i18n bn.json / en.json ──► t(key, params)
   (no shared package — each app encodes the same reference values; namespaces per §1.1)
```

No database sits under any of this — this module's `03-backend-tasks §1` records N/A (no database); the entities above are code and config, not rows.

### 1.3 Invariants

| ID | Invariant | Enforced by |
| --- | --- | --- |
| `DSN-BR-001` | Every catalog key resolves in bn and en; the key sets are identical | CI parity test (`DSN-UT-001`) |
| `DSN-BR-002` | No raw hex/px/font-family in app/web feature code | ESLint token-only rule (`DSN-INT-002`) |
| `DSN-BR-004` | Bengali never renders in Inter; `lang` tags always set | Type tokens; locale provider; render fixtures |
| `DSN-BR-006` | The logo is used only via `<Logo/>`, per `docs/design-reference/README.md` §5 | Component API (no raw `<Image>` of the logo in features) |
| `DSN-BR-007` | Every animation has a reduced-motion form | Motion tokens; motion-table review (`04 §5`, `05 §5`) |

## 2. Module Boundary

**Owns (writes):** each app's `src/theme` tokens + `src/i18n` catalogs + `t()` + catalog CI tests · `applications/web` `@theme` wiring, fonts, `src/components/ui/*` · `applications/app` NativeWind config, bundled fonts, RN primitives, icon/splash EAS config. **Module 02 owns no database tables** — tokens and catalogs are code/config (`03-backend-tasks §1` is N/A by design); data-model ownership stays with `01-foundations` (audit_log, jobs), `03-identity-access`, `04-organization-hierarchy`, `05-communication-engine`, `06-notifications` per `docs/modules/README.md`.

**Reads from other modules (via their exported service functions only):**

| Module | What | Why not duplicated |
| --- | --- | --- |
| `01-foundations` | API contract (`applications/api/openapi/openapi.yaml`) and the problem-code registry | Web/app scaffolding is this module's own work (isolated repos, no shared package) |

**Cache keys / tags revalidated / consumed:** see `06-integration-tasks.md` §4 — none; everything here is static, content-hashed at build.

## 3. Lifecycle

No entity state machine. The only lifecycle worth naming is a **string key's**:

```text
drafted (one locale) ──parity ✅──▶ shipped ──replace──▶ deprecated ──zero refs──▶ removed
```

| From | Action | To | Guards | Side effects |
| --- | --- | --- | --- | --- |
| — | key added | shipped | bn + en in the same commit (`DSN-UT-001`) | typed key appears in `CatalogKey` |
| shipped | deprecate | deprecated | replacement key named in the PR | old key kept ≥ 1 release |
| deprecated | remove | — | lint: zero references remain | bundle shrinks |

## 4. Rendering & Caching

| Surface | Rendering | Cached read | Tags |
| --- | --- | --- | --- |
| Web tokens → `@theme` | Build-time CSS custom properties; zero runtime CSS-in-JS | Immutable hashed CSS bundle | none |
| Web fonts | `next/font/google` downloads + self-hosts subset woff2 at build | Next asset pipeline + browser cache | none |
| Web catalogs | Static JSON imports, bundled | Content-hashed chunk | none |
| App fonts/tokens/catalogs | Bundled in the binary (`@expo-google-fonts`, NativeWind compile-time, JSON imports) | n/a — on device | n/a |

## 5. Configuration — the two lists

| Owner can change in the admin | Fixed in code |
| --- | --- |
| Nothing at launch — module 02 ships no admin surface; per-user language selection arrives with `03-identity-access` onboarding | Palette + generated scales · font families/subsets · spacing/radius/type scales · motion durations/easings · namespace whitelist · fallback chain (requested locale → bn → key) · light theme |

## 6. Security

No entry points, no auth middleware, no tenant scope — **N/A: no server code and no tenant data exist in this module** (`03-backend-tasks §1` is all N/A). Security-relevant properties provided downstream: primitives render strings as plain text (never `dangerouslySetInnerHTML`), so feature screens inherit XSS-safe rendering; `src/theme`/`src/i18n` ship no secrets; web fonts are fetched from Google at build time via `next/font` and self-hosted — never from a runtime endpoint.

## 7. Accessibility & Motion

Primitives are built on Radix (web) and radix-primitives/zeego (app) so focus management, roles, keyboard interaction and announcements come from battle-tested heads. What is animated and why: press feedback (responsiveness), dialog/sheet enter-exit (spatial context), toast entry (feedback), skeleton shimmer (perceived progress), one-time splash reveal ≤ 900ms (brand). Every one has a reduced-motion static form (`DSN-BR-007`); per-element tables in `04-frontend-tasks §5` and `05-app-tasks §5`. Contrast targets WCAG 2.2 AA in the light theme in both languages; the logo's accessible name is "Kushol Connect — Home" (`docs/design-reference/README.md` §5).

## 8. Failure Scenarios & Recovery

| # | Failure | Detection | Impact | Recovery |
| --- | --- | --- | --- | --- |
| 1 | Font fetch fails at web build | Build error | Build blocked (loud, intentional) | Retry CI; if Google is down, vendor the subset woff2 into the repo (documented escape hatch) |
| 2 | Missing catalog key at runtime | Dev warning + `DSN-UT-001` gate | Label shows bn fallback or key literal | Add the key; the parity gate prevents recurrence |
| 3 | Raw hex/px slips into a feature PR | `DSN-INT-002` lint in CI | PR blocked | Import the semantic token |
| 4 | bn string overflows a control | Primitive fixtures (`DSN-UT-003`/`004`) | Clipped label caught pre-merge | Fix primitive sizing (min-height/wrap), not the screen |
| 5 | Glyph missing from Hind Siliguri | Specimen corpus test | Tofu on a rare glyph | Route that string through the system-Bengali fallback; file font issue |
| 6 | NativeWind/theme misconfiguration | App smoke render (`DSN-IT-002`) | Unstyled screens | Pinned versions + render test catch it |

## 9. Performance

- Fonts: subset woff2 (`bengali` for Hind Siliguri, `latin` for Inter), `display: swap`; both families together budgeted ≤ ~150KB — measured at build (`verify`, revisit when subsets land).
- No runtime CSS-in-JS anywhere: Tailwind v4 compiles `@theme` to custom properties; NativeWind compiles class names at build.
- App cold start: fonts load from the binary; splash held only until `useFonts` resolves — no network on first launch.
- Bundle impact: Radix/zeego primitives and lucide icons tree-shake per component; catalogs are one JSON pair shared by both apps.
- Web CWV: landing budgets (green) asserted by `07-command-center-web`'s Playwright runs on this foundation (`docs/persona.md` performance row).

## 10. Alternatives Considered

### Option A — shadcn-style hand-written primitives · Option B — prebuilt UI kit (MUI/Ant-class)

| | A | B |
| --- | --- | --- |
| Advantages | Full token control; bn-first sizing baked in; components live in-repo; no theme-override fights | Faster initial scaffold; batteries included |
| Disadvantages | We write and maintain each primitive | Re-theming a kit to a custom Bengali-first brand is slower than building 14 small primitives; heavier bundle; a11y states need the same work anyway |
| Complexity / weight | Low — Radix/zeego heads do the hard parts | Medium-heavy runtime + override CSS |

**Recommendation:** A — also already binding in `docs/tech-stack.md` (web and app component rows). **ADR:** record in this module's `07-progress.md`.

### Option C — NativeWind · Option D — plain StyleSheet + theme object

| | C | D |
| --- | --- | --- |
| Advantages | Same class/token mental model as web; shared Tailwind config; compile-time output | Zero extra dependency; fully explicit objects |
| Disadvantages | One more translation layer to keep pinned | Every token re-declared RN-side; drift from web is easy and silent |
| Complexity / weight | Small runtime, compile-time styles | Trivial runtime, high duplication |

**Recommendation:** C — one token language across both platforms (`docs/tech-stack.md` app table binds it); risk handled by pinned versions + `DSN-IT-002` smoke. **ADR:** in `07-progress.md`.

### Option E — single catalog pair (`bn.json`/`en.json`) · Option F — per-module catalogs merged at build

| | E | F |
| --- | --- | --- |
| Advantages | One parity check; one import; dot-namespaces already give modular authoring | Smaller diffs per module; crisp per-namespace ownership |
| Disadvantages | File grows as modules 03–14 land | Merge/typing tooling complexity now, for a problem not yet real |
| Complexity / weight | Trivial | Medium tooling |

**Recommendation:** E — single pair with the eight namespaces; split per-module if a file passes ~2,000 keys (recorded threshold; revisit with an ADR). **ADR:** in `07-progress.md`.

## 11. Assumptions & Risks

| # | Assumption / risk | Impact if wrong | Mitigation |
| --- | --- | --- | --- |
| 1 | Vector logo files arrive before production release | Icon/splash stay on the PNG fallback (soft at some sizes) | Open Question 1; gap recorded; `<Logo/>` + EAS assets make the swap a one-commit change |
| 2 | Sampled palette matches the final SVG | Brand colours shift slightly | All colour flows through tokens — single-file update; `verify` note until then |
| 3 | Hind Siliguri covers the launch Bengali corpus incl. Bengali numerals | Rare glyphs fall back | Specimen tests (`DSN-UT-003`/`004`); fallback stack per `DSN-BR-004` |
| 4 | bn strings stay ≤ +30% vs en | Overflow in tight controls | Primitives sized bn-first; fixture strings at +30% |
| 5 | NativeWind stays compatible with the pinned Tailwind version | Styling breaks on upgrade | Version pins (`docs/tech-stack.md`) + `DSN-IT-002` |
| 6 | Web and app hold separate copies of tokens and catalogs (isolated repos, owner decision 2026-09-30) | The two apps drift apart (colour, copy, namespaces) | Canonical values stay in `docs/design-reference/README.md`; each repo's token test pins its values to that table (`DSN-UT-005`); namespace registry stays in §1.1; shared namespaces (`common`, `errors`, `validation`) reviewed in both repos in the same change |
