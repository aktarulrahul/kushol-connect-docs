# Brand files — Kushol Connect

> **2026-10-22 — NEW LOGO APPLIED.** `docs/logo/kusholConnect.png` (869 × 287, transparent) converted
> and deployed to every surface (web lockup, mobile splash lockup, emails). App icon set
> (icon / adaptive / themed / notification) regenerated from `docs/logo/icon.png`. Emails render
> the wordmark as styled text in the same colours (deep indigo `#3E3EA6` কুশল + periwinkle `#6C6CE0` CONNECT). High-res original
> archived at `docs/logo/kc-logo.jpg` (3584 × 1184).

The converted PNG is also the brand reference:

| File | What | Used on |
| --- | --- | --- |
| `kushol-connect-full-logo.png` | Full lockup: KO swirl monogram + Bengali wordmark "কুশল" + "CONNECT" (869 × 287, transparent) | Design reference, internal mockups |
| *(generated)* `icon.png` + `adaptive-icon.png` + `adaptive-icon-monochrome.png` + `notification-icon.png` | App icon set (1024² / 1024² safe-zone / 512² white themed / 96² white notification) — from `docs/logo/icon.png` | App icon, Android adaptive/themed icons, notifications |
| *(generated)* `splash-icon.png` | App flash / loading icon (500²) — from `docs/logo/icon.png` | Native splash (`app.json`) + the in-app `SplashReveal` overlay |

**Production still wants vector sources.** Please add:

| File | What | Used on |
| --- | --- | --- |
| `logo-lockup.svg` *(preferred)* | Full lockup as SVG, swirl gradient preserved, wordmark as paths (or `currentColor` where sensible) | Headers, landing page, splash — both platforms |
| `logo-monogram.svg` | The swirl mark alone on a square artboard | App icon, favicon, notification small icon, avatar placeholder, OG images |
| `logo-lockup-knockout.svg` | White/knockout version for indigo backgrounds | Splash screen, primary-button contexts, dark surfaces |

If only PNG exports exist, add them at 2× (≥ 1200px wide for the lockup, ≥ 512px for the
monogram) with transparent backgrounds.

Rules for using the logo: `../README.md` §5 (usage rules) and §2 (palette).
