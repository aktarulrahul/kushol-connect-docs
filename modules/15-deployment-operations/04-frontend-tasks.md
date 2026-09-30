# Deployment & Operations — Frontend Tasks

**Module:** `15-deployment-operations`
**Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner)
**Stack:** Next.js App Router · TypeScript strict · Tailwind v4 tokens · shadcn/ui · Motion · RHF + Zod
**Last updated:** 2026-09-30

Design tokens come only from `packages/shared`; every user-facing ops string ships in Bengali + English
via the `ops.*` catalog (the web side of this module's language split — runbooks stay English). Most of
this module is infra (03/05/06); the web surface is deliberately small but real: prod build hardening,
security headers, a CWV budget gate, and the maintenance banner + page.

---

## 1. Screen Inventory

| # | Route | Screen | Rendering | Access |
| --- | --- | --- | --- | --- |
| 1 | `/maintenance` (Nginx-served static, bypasses Next) | Maintenance page | Static file | Public |
| 2 | `/` (landing, owned by 07) | Ops hardening target: headers + CWV budget in prod | Server Component | Public |
| 3 | global (root layout) | Maintenance banner | Client Component | Public + all admin roles |

## 2. Screen Breakdown

### 2.1 `Maintenance page` — `/maintenance` (static)

**Layout**

```text
┌──────────────────────────────┐   centred column, paper bg, brand mark
│        [কুশল mark]            │   H1: ops.maintenance.title (bn default)
│  নিয়মিত রক্ষণাবেক্ষণ চলছে      │   body: ops.maintenance.body
│  We'll be back shortly.       │   lang toggle link: bn ⇄ en (?lang=)
│  [বাংলা | English]            │   no nav, no forms — nothing to fail
└──────────────────────────────┘
```

**Components**

| Component | Server/Client | Notes |
| --- | --- | --- |
| BrandMark | Static | From 02 assets; clear-space rules respected |
| MaintenanceMessage | Static | Strings baked from `packages/shared` `ops.*` at page build; bn default, `?lang=en` variant file |
| LanguageToggle | Static link | Two prebuilt files (bn/en) — works without JS, served by Nginx |

**States**

| State | Behaviour |
| --- | --- |
| Planned maintenance | `ops.maintenance.title/body` — scheduled-window copy |
| Unplanned incident | Variant copy `ops.maintenance.incident` (bn/en) — swapped by rebuilding the static pair |
| Recovery | Page is `no-store`; flag removal restores the app instantly, no cache purge |

### 2.2 `Maintenance banner` — global (root layout)

**Components**

| Component | Server/Client | Notes |
| --- | --- | --- |
| OpsBanner | Client | Rendered only when `NEXT_PUBLIC_MAINTENANCE_MODE=true` at build; `role="status"`, dismissible, sticky top |
| — strings — | — | `ops.maintenance.banner` (bn: `রক্ষণাবেক্ষণ চলছে…` / en: `Maintenance in progress…`) from `packages/shared` |

**States**

| State | Behaviour |
| --- | --- |
| Flag off (default) | Component tree-pruned at build — zero bundle cost |
| Flag on | Banner above all content; full contrast AA on paper; both languages verified |
| Reduced motion | Entrance animation suppressed — static appearance |

## 3. Forms

None — no forms on ops surfaces (the page must work with JS disabled and nothing to submit).

## 4. Data Flow

| Need | Mechanism |
| --- | --- |
| Banner flag | Build-time env `NEXT_PUBLIC_MAINTENANCE_MODE` baked into the standalone output — no runtime fetch, survives api outages |
| Ops strings | Imported from `packages/shared` `ops.*` catalogs (bn default + en) — build-time check that both exist before the flag can ship |
| Maintenance page | Fully static pair of files (bn/en) under `deploy/`, served by Nginx — no Next, no api involvement |
| Health/monitoring | None — UI never polls ops state (uptime checker owns detection, 03 §2) |

## 5. Motion Spec

| Element | Variant / technique | Trigger | Communicates | Reduced motion |
| --- | --- | --- | --- | --- |
| OpsBanner entrance | 150 ms slide-down + fade | Flag on, first mount | "System state changed" | Static appearance |
| Maintenance page | none | — | — | n/a — always static |

## 6. Responsive Behaviour

| Surface | < 640 | 640–1023 | ≥ 1024 |
| --- | --- | --- | --- |
| OpsBanner | Full-width, text wraps to 2 lines, dismiss reachable | Single line | Single line, content max-width |
| Maintenance page | Centred single column, 360px-safe | Centred column | Centred column, generous whitespace |

## 7. Accessibility

- [ ] Landmarks, one `h1`, heading order (maintenance page)
- [ ] Banner `role="status"` (polite announcement); dismiss control labelled in bn/en
- [ ] Keyboard path complete (banner dismiss; page has a single lang-toggle link)
- [ ] Contrast AA in bn and en, both themes where the banner appears
- [ ] Motion: reduced-motion variant verified (static banner/page)
- [ ] `lang` attribute correct per served language (bn default)

## 8. Design-System Compliance

`docs/design-reference/README.md` holds for both surfaces: tokens from `packages/shared` only,
Hind Siliguri (bn) + Inter (en), logo clear-space; `ops.*` strings verified in both languages before
the maintenance flag may ship (build-time check, OPS §6 validation).

## 9. Task Checklist

- [ ] `OPS-FE-001` — web standalone Dockerfile output verified in CI (build + boot + `/` 200) — with OPS-BE-002
- [ ] `OPS-FE-002` — CSP + security headers via HestiaCP/Nginx template (HSTS, X-Content-Type-Options, frame-ancestors, CSP enforce) — with OPS-BE-006
- [ ] `OPS-FE-003` — Lighthouse CI on prod landing: CWV budget green gate (perf/a11y/bp/SEO ≥ thresholds recorded in DEPLOYMENT.md)
- [ ] `OPS-FE-004` — OpsBanner component + `ops.maintenance.*` bn/en strings in `packages/shared` (+ build-time catalog check)
- [ ] `OPS-FE-005` — static bn/en maintenance page wired to the Nginx flag (`no-store`, no-JS safe)
