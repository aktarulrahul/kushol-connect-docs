# 13-b2b-ads-events — Remaining Gaps

| # | Gap | Reason | Impact | Next action |
| --- | --- | --- | --- | --- |
| G-1 | E2E + IT runs pending owner | Standing rule: agent never runs the app/containers | ADS-IT-001–006 + Playwright golden paths unexecuted | `make test-integration`; `pnpm test:e2e` |
| G-2 | `it_ads_test.go` not yet written | Context budget: the specs exist (06 §9) but the harness file didn't land this session | Moderation-gate/isolation/concurrency ITs unproven | Write the testcontainers file mirroring `it_commerce_test.go` |
| G-3 | Web seam stays on fixtures | 07's console session glue is still fixture-level (same boundary as 10/11/12) | Partner/admin screens can't hit the live api yet | One-file swap of `src/fixtures/ads.ts` when 07 lands |
| G-4 | Campaign builder + event editor screens simplified | Context budget: builders compressed to list + queue this pass | `/partner/ads/new`, `/partner/events/new`, `/partner/ads/[id]` analytics chart not built | Next pass: 4-step builder per 04 §2.2 with the audience-estimate endpoint |
| G-5 | Per-topic audience counts recorded as 0 | 04's `AudienceCount` export not wired into dispatch (degrades to unknown per edge 9) | Impressions don't carry real reach numbers yet | Wire 04's count export at dispatch; spend math already parameterised |
| G-6 | Native banner serving (`ADS-BE-015`, P1) deferred | P1 scope; needs the web-surface slots decision | No web native ad slots yet | Next web pass after OQ-3 |
| G-7 | Seed deferred | No seed vehicle (same decision as 10/11/12) | Fresh envs lack demo rows | Owner decides CLI vs dev migration |
| G-8 | Per-user frequency cap (`ADS-BE-012`) stubs to per-topic | Per-user cap needs the pseudized trailing-7d user-keyed lookup; push path is per-topic today | Cap enforced per topic, not per user | Land with the native-serving pass (pseudize helper already tested) |
