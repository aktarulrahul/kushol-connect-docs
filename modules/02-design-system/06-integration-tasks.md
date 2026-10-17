# Design System — Integration Tasks

**Module:** `02-design-system` · **Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner) · **Last updated:** 2026-09-30

`02-solution-approach.md §2` says *what* crosses this module's boundary (tokens, catalogs,
primitives — the product's visual API); this file is the **contract**. No cross-module import, lint
gate or external font dependency may exist in code unless it is declared here
(`docs/prompt/prompt-build.md` §6).

---

## 1. Integration Surface

| # | Counterparty | Direction | Mechanism | Failure is… |
| --- | --- | --- | --- | --- |
| I-1 | every module (`03-identity-access` … `14-lms-erp-sync`) | they call us | import from their own app's `src/theme` (tokens), `src/i18n` (`t()`) and primitive folders | build-time fatal (missing export); runtime degraded (fallback chains) — never fatal at runtime |
| I-2 | `01-foundations` | we call them | api contract + problem-code registry (no web/app scaffolding — 02 scaffolds its own repos) | degraded — UI builds on fixtures until the contract exists |
| I-3 | api → app/web | N/A — this module exchanges no server data (no REST/WS/FCM) |
| I-4 | Google Fonts (external) | outbound | build-time download only (`next/font/google`); app fonts bundled via `@expo-google-fonts` packages | degraded — fallback stacks; never a runtime fetch |

## 2. Exported Contract

```text
tokens    : semantic token set — color / space / radius / type / motion
            (CSS variables via Tailwind @theme on web · NativeWind theme on app)
i18n      : catalogs bn.json / en.json (schema: 03-backend-tasks §2)
            + t(key: CatalogKey, params?: Record<string, string | number>): string
components: web primitives (applications/web/src/components/ui/*)
            + RN mirrors (applications/app primitives) — minimal, documented props
brand     : <Logo/> component · app icon / splash / notification small icon (EAS config)
```

| Export | Callers | Returns | Throws | Notes |
| --- | --- | --- | --- | --- |
| Tokens (semantic) | every FE/AP task in `03`+ | token values/vars | — build-time | the only colour/size source (`DSN-BR-002`) |
| `t(key, params)` | every user-facing string | localized string | never (fallback requested locale → bn → key) | typed `CatalogKey`; bn default (`DSN-BR-003`) |
| Catalogs bn/en | `t()`; `03-identity-access` language UI | JSON per `03-backend-tasks §2` | — | parity CI-gated (`DSN-UT-001`) |
| Web primitives | `03`, `07`, later FE modules | React components | — | props minimal + documented; additive-first |
| RN primitives | `03`, `05`, `08`, `10`, `11` | RN components | — | mirror the web inventory (`05-app-tasks §2.2`) |
| `<Logo/>` + icon/splash | headers, landing (`07`), app config | component/assets | build fails if an asset is missing | usage rules: `docs/design-reference/README.md` §5 |

Rules: exports are typed and DTO-like (tokens/JSON/components — no app-internal types leak);
prop/signature changes are additive first; renames go deprecate → remove (lifecycle:
`02-solution-approach §3`).

## 3. Consumed Contracts

| We call | Owner | On failure |
| --- | --- | --- |
| api contract (`applications/api/openapi/openapi.yaml`) | `01-foundations` | fixtures keep the UI buildable; client generation waits for the spec |
| Google Fonts (build-time only) | external | web build fails loudly; escape hatch: vendor the subset woff2 (`02-solution-approach §8`) |
| npm: radix / zeego / lucide / @expo-google-fonts | external (pinned) | install-time failure — CI blocks |

## 4. Cache-Tag Contract

| Mutation | Revalidates |
| --- | --- |
| None — module 02 performs no server mutations | — |

| Read | Tagged with |
| --- | --- |
| None — no tagged reads; token/catalog changes ship as content-hashed rebuilt bundles | — |

## 5. External Systems

| System | Protocol | Auth / secret | Timeout | Retry | Degradation |
| --- | --- | --- | --- | --- | --- |
| Google Fonts | HTTPS, build-time only (`next/font/google`) | none (public endpoints) | build timeout | CI retry | fallback stack `"Hind Siliguri", "Noto Sans Bengali", system` · Inter → system-ui |
| Google Fonts (npm) | `@expo-google-fonts` packages, bundled at install | none | n/a | pnpm install retry | fonts in the binary — no runtime failure path |
| FCM · R2 · DeepSeek · SMS · payment gateways | N/A — none of these are touched by this module |

## 6. UI ↔ Server Seam

N/A for calls — module 02 defines no server calls. It fixes the seam conventions every other
module uses: server error codes map to `validation.*`/`errors.*` catalog keys resolved by `t()`
before display; primitives render whatever localized string they receive (plain text, never HTML);
pending/empty/error visuals come from the Skeleton/EmptyState/Toast primitives so every module's
seam looks and behaves identically.

## 7. Contract Stability

Catalog keys and token names are additive-first: never rename a shipped key (add new, deprecate old
≥ 1 release, then remove — `02-solution-approach §3`); token names stay semantic (`--color-primary`,
never a hex-derived name) so values can change the day the SVG lands (`verify` note,
`docs/design-reference/README.md` §2); primitive props are additive-first, and breaking changes
need an ADR note in this module's `07-progress.md`. The catalog JSON schema lives in
`03-backend-tasks §2` and is versioned with each app (web and app hold identical-schema copies).

## 8. Failure & Degradation Matrix

| Dependency down | What still works | User sees | Recovery |
| --- | --- | --- | --- |
| Google Fonts build fetch | app fully (bundled fonts); web dev with fallback stacks | slightly different type until fixed | retry CI / vendor woff2 |
| Missing catalog key | everything else | bn fallback or key literal + dev warning | add the key; `DSN-UT-001` prevents recurrence |
| Hind Siliguri missing a glyph | rest of the UI | system-Bengali fallback glyph | specimen test alerts; font-stack fix |
| NativeWind/Tailwind version mismatch | logic intact | unstyled/mis-styled UI | pinned versions; `DSN-IT-002` smoke |
| Logo asset missing | nothing — build fails | nothing ships | assets are in-repo; import check |

## 9. Test Plan

| ID | Test | Layer | Proves |
| --- | --- | --- | --- |
| `DSN-UT-001` | Catalog parity: schema, identical bn/en key sets, non-empty values, identical placeholders, namespace whitelist | Unit (CI) | `DSN-BR-001` — a missing bn or en key fails CI |
| `DSN-UT-002` | `t()` fallback chain never throws or returns empty | Unit | missing-key edge (`01-user-stories §7` #1) |
| `DSN-UT-003` | Web primitive render tests: focus/pressed/disabled states, bn +30% fixtures, accessible names | Unit (Vitest + Testing Library) | `DSN-US-005`, `DSN-US-003` |
| `DSN-UT-004` | RN primitive render tests (jest-expo): same fixtures | Unit | `DSN-US-005`, `DSN-US-003` |
| `DSN-UT-005` | Token reference pin: each app's `src/theme` values equal the canonical table in `docs/design-reference/README.md` (web and app repos each run it) | Unit (CI, per repo) | `DSN-BR-002`; web ↔ app drift (risk 6) |
| `DSN-IT-001` | Token-usage lint over `applications/web` + `applications/app`: no raw hex/px/font-family outside allowed paths | CI lint gate | `DSN-BR-002` |
| `DSN-IT-002` | Apps render themed + localized end-to-end (web Next build smoke; app root render with fonts/theme/locale) | Integration | `DSN-US-001`, `DSN-US-004` |
| `DSN-E2E-001` | Smoke: bn default renders and the en toggle works on web (Playwright) and app (Maestro); reduced-motion static splash checked | E2E (Playwright + Maestro) | `DSN-US-004`, `DSN-US-006` |

## 10. Task Checklist

- [x] `DSN-INT-001` — Catalog JSON schema + validator implemented in each app's `src/i18n`, wired into CI (with `03-backend-tasks §2`) — 2026-10-15
- [x] `DSN-INT-002` — Token-only ESLint rule active for `web` + `app` CI — 2026-10-15
- [x] `DSN-INT-003` — Exported contract (this file §2) published to consumers; `03-identity-access` consumes it first (smoke-proven by `DSN-IT-002`) — 2026-10-15
- [x] `DSN-UT-001` … `DSN-UT-005` — green in CI (in both the web and app repos where applicable) — 2026-10-15
- [x] `DSN-IT-001` … `DSN-IT-002` — green in CI — 2026-10-15
- [ ] `DSN-E2E-001` — green on web (Playwright) + app (Maestro)
