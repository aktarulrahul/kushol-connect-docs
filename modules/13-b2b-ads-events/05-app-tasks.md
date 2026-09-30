# B2B Ads & Events — App Tasks (Mobile)

**Module:** `13-b2b-ads-events`
**Status:** 📝 Spec drafted 2026-09-30 · **Owner:** Rahul (product owner)
**Stack:** N/A — module 13 covers `api` + `web` only (README row 13); no app screens are built here
**Last updated:** 2026-09-30

> `docs/design-reference/README.md` and `docs/tech-stack.md` (app table) remain binding for any
> app surface that a future scope amendment adds. Today this module ships **no mobile screens**.

---

## 1. Screen Inventory

N/A — no app screens in module 13 (README scope: `api` `web`). App-relevant behaviour is explicit:

| # | Concern | Where it actually happens |
| --- | --- | --- |
| 1 | Sponsored push delivery | Module 06: dispatch payloads (`type=campaign`, class `campaigns`) arrive on the same hierarchy topics, carry the server-injected "স্পনসর্ড / Sponsored" label in bn + en, and deep-link per 06's route map |
| 2 | In-app native ad slots | **Recorded gap** — needs a future module amendment (Open Questions #3); no RN ad component exists in this scope |
| 3 | Event discovery / tickets in-app | **Recorded gap** — events surface via 06 push deep links today; an in-app event listing + ticket purchase surface requires the same amendment (`TODO: Confirm`) |

## 2. Screen Breakdown

N/A — no screens built in this module. The three concerns above are the complete app-side story;
any future native-slot or events surface must be specified in an amended module before code.

## 3. Forms & Input

N/A — no app forms. Campaign/event creation is vendor-portal web only (04 §3); ticket actions are
web-first until the amendment lands.

## 4. Data Flow

| Need | Mechanism |
| --- | --- |
| Sponsored push | 06 `BroadcastTopic` → expo-notifications; label + payload owned by 13's dispatch, rendering by 06/02 |
| Deep-link tap | 06's route map routes the tap (event/campaign target); unknown types fall back to the home tab (06 §7) |
| Click tracking | Landing route calls `POST /api/v1/ads/track/click` (pseudized) — no app-side storage |
| Native banner / event purchase | None — recorded gap |

## 5. Motion Spec

N/A — no app UI in this module. (Push presentation motion is module 06/02's.)

## 6. Responsive & Device Behaviour

N/A — no app UI. (When the amendment lands: 360px-first, Hind Siliguri for bn ad copy, no blocking
loads per the repo standards.)

## 7. Accessibility

- [ ] N/A — no app UI here. Push a11y (labels, bn typography, reading order) is covered by 06's
      checklist; sponsored label is text, never colour-only.

## 8. Offline Behaviour

None — requires connectivity for the tracked surfaces. Sponsored pushes cache in the OS tray like
any notification; tap without network shows the standard offline screen. No queueing is introduced
by this module.

## 9. Task Checklist

- [ ] `ADS-AP-001` Verify labelled sponsored push renders via 06 (bn + en label, deep link resolves) on a 360px device — ____
- [ ] `ADS-AP-002` Track the native-slot + in-app-events **gap**: amendment drafted and approved before any app ad UI is built — ____
- [ ] `ADS-AP-003` Verify push deep-link tap → click tracking round-trip (pseudized) — ____
