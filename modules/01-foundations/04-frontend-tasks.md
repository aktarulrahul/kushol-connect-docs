# Foundations — Frontend Tasks

**Module:** `01-foundations`
**Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner)
**Stack:** Next.js App Router · TypeScript strict · Tailwind v4 tokens · shadcn/ui · Motion · Embla · RHF + Zod
**Last updated:** 2026-09-30

This module ships **no web screens** — only the web repo foundation (`FND-FE-001`, owner
instruction 2026-09-30: "complete 01-foundations for api, web and app"). `docs/design-reference/README.md`
becomes binding from 02-design-system onward: tokens, fonts, bn/en catalogs and primitives belong to
02; landing and Command Center screens to 07-command-center-web.

---

## 1. Screen Inventory

N/A — no routes in this module. Web routes (`/`, `/download`, `/login`, `/admin/*`, `/school/*`,
`/vendor/*`) are specified by their feature modules (03, 07+).

## 2. Screen Breakdown

N/A — no screens to break down; see §1.

## 3. Forms

N/A — no forms. Zod form schemas mirror contract shapes from 03-identity-access onward.

## 4. Data Flow

N/A for screens; the mechanism is fixed here for later modules: Server Component / Server Action →
generated `openapi-fetch` client (the web repo's own `src/api`) → api. Web never touches the database or
hand-written API types.

## 5. Motion Spec

N/A — no UI motion. Convention for all later modules: every motion row needs a reduced-motion
variant (template rule carried into 02/07 specs).

## 6. Responsive Behaviour

N/A — no surfaces. Web targets: 640 / 1024 breakpoints per template; admin usable at tablet width.

## 7. Accessibility

N/A — no screens; axe/WCAG 2.2 AA gates apply from 02-design-system (web primitives) onward.

## 8. Design-System Compliance

N/A — tokens, Hind Siliguri/Inter and catalogs arrive with 02-design-system in the web repo's
`src/theme` / `src/i18n`.

## 9. Task Checklist

- [x] `FND-FE-001` — Web repo scaffold in `applications/web` (own git repo, branch `module/01-foundations`): Next.js 16 App Router (`output: "standalone"`), TypeScript 6 strict, Tailwind v4 (plain `@import`, no tokens), ESLint 10 flat with boundary rules (`process.env` only in `src/env.ts`; `fetch`/`openapi-fetch` only in `src/api`) + Prettier, Vitest + Playwright + axe (1280/768), `sync:api-spec` + `generate:api` (openapi-typescript → `src/api/schema.gen.ts`, `createApiClient` on openapi-fetch with `Accept-Language`), `contracts:check`, zod env module, GitHub Actions gate; placeholder `/` (brand name only) — was 02 `DSN-FE-000` — 2026-09-30
