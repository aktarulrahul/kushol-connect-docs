# Deployment & Operations — App Tasks (Mobile)

**Module:** `15-deployment-operations`
**Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner)
**Stack:** Expo SDK · expo-router · React Native · NativeWind tokens · TanStack Query · zustand · react-hook-form + zod · **EAS Build / Submit / Update**
**Last updated:** 2026-09-30

No product screens are added — the app side of this module is the **build & distribution pipeline**
(`eas.json`, channels, OTA policy) plus a smoke gate on the built APK. Distribution follows
`prd.md` §4B (Android APK direct, iOS via TestFlight) and `brd.md` §8 Phase 1. Assets (icon/splash)
come from 02; app runtime behaviour stays owned by 03/05/06.

---

## 1. Screen Inventory

None — infrastructure module; no routes are added. The ops surface is `eas.json` + CI wiring + the
distribution checklist (`DEPLOYMENT.md` §app).

## 2. Screen Breakdown

### 2.1 `EAS build profiles` — `eas.json` (app-level config, not a screen)

**Layout**

```json
{
  "build": {
    "development": { "developmentClient": true, "distribution": "internal",
                     "env": { "EXPO_PUBLIC_API_URL": "http://<lan-host>:8080" } },
    "preview":     { "distribution": "internal", "channel": "preview",
                     "env": { "EXPO_PUBLIC_API_URL": "https://api.<pilot-domain>" } },
    "production":  { "distribution": "store",   "channel": "production",
                     "env": { "EXPO_PUBLIC_API_URL": "https://api.<prod-domain>" } }
  },
  "submit": { "production": {} },
  "cli": { "appVersionSource": "remote" }
}
```

**Components**

| Component | Client/Server-driven | Notes |
| --- | --- | --- |
| Profile `development` | EAS cloud | Dev client; internal install only; never distributed to schools |
| Profile `preview` | EAS cloud | Internal APK for school pilots (`brd.md` §8 Phase 1); OTA channel `preview` |
| Profile `production` | EAS cloud | Play-ready AAB + direct APK; TestFlight submit via EAS Submit; OTA channel `production` |
| Icon/splash | Static | Wired from 02 assets for every profile (brand rules) |

**States**

| State | Behaviour |
| --- | --- |
| Queued / in progress | CI step waits; status surfaced in the release log (03 §2) |
| Build errored | Non-zero CI; fallback = documented local `eas build` path (06 §8 — never builds on the VPS) |
| Finished | Artifact registered; Maestro smoke runs before any distribution (OPS-AP-005) |

## 3. Forms & Input

None — no user input; profiles are code-reviewed config.

## 4. Data Flow

| Need | Mechanism |
| --- | --- |
| Runtime API URL per channel | `EXPO_PUBLIC_API_URL` baked per profile (table above) — never hardcoded elsewhere (FND-BR-002 discipline) |
| OTA updates | EAS Update, channel per profile; `runtimeVersion` policy = `appVersion`; JS-only fixes ride OTA, native/SDK changes require a store build |
| OTA rollout rule | canary `development` → `preview` (24 h) → `production`; bad bundle = republish previous (documented in DEPLOYMENT.md) |
| Push (prod) | FCM production credentials wired at the platform level (OPS-BE-013); app behaviour owned by 06 |

## 5. Motion Spec

N/A — this module adds no UI or animation.

## 6. Responsive & Device Behaviour

| Concern | Behaviour |
| --- | --- |
| Smoke gate on real artifact | Maestro smoke (login → section group → notice) runs against the built `preview` APK in CI — proves the *build* is sound on a low-end Android profile (360px, throttled network); UI coverage stays with owning modules |
| Distribution artifacts | `preview` APK (direct link for pilots) + `production` AAB/APK; TestFlight build for the internal group |
| Bengali content | Inherited from 02 fonts; verified by existing golden-path tests, re-run on the built APK |

## 7. Accessibility

N/A — no screens. The distribution checklist re-runs module-owned a11y checks (axe on web, Maestro
golden paths, bn/en verification) on the release artifact before sign-off.

## 8. Offline Behaviour

None — this module changes no app behaviour; offline surfaces are owned by 05-communication-engine
and unaffected by build/OTA wiring.

## 9. Task Checklist

- [ ] `OPS-AP-001` — `eas.json` profiles (development / preview / production) matching the table in §2.1
- [ ] `OPS-AP-002` — icon + splash from 02 wired into app config for all profiles
- [ ] `OPS-AP-003` — OTA channels + `runtimeVersion` policy + canary/republish-rollback policy documented (DEPLOYMENT.md)
- [ ] `OPS-AP-004` — per-channel `EXPO_PUBLIC_API_URL` env wiring (dev/preview/prod)
- [ ] `OPS-AP-005` — CI job: Maestro smoke on the built `preview` APK (low-end profile) before distribution
- [ ] `OPS-AP-006` — distribution checklist (TestFlight group + signed APK link + version/notes) added to `DEPLOYMENT.md`
