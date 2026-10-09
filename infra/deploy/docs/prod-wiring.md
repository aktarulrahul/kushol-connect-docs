# Part B production wiring checklist (OPS-BE-013)

Env-only cutovers; each line is logged (date + by whom) in `state/releases.log` when done.
Every item lands in `/opt/kushol/env/*.env` (chmod 600) followed by `docker compose up -d`.

| # | Cutover | Source of truth | Done |
| --- | --- | --- | --- |
| 1 | Neon **prod** project/branch created; `DATABASE_URL` (pooled) into `env/api.env`; `migrate up` | owner console | ☐ |
| 2 | R2 production bucket + `R2_ACCOUNT_ID/ACCESS_KEY_ID/SECRET_KEY/BUCKET` (05) + versioned `kushol-backups` bucket (15) | CF dashboard | ☐ |
| 3 | FCM prod service account → `FCM_SERVICE_ACCOUNT_JSON`/`FCM_PROJECT_ID` (06 seam); test push after restart | Firebase console | ☐ |
| 4 | Gateway sandbox→prod: SSLCommerz first (`12` cutover list: store IDs + hashes + webhook URL `https://api.kusholconnect.com/api/v1/webhooks/{gateway}`) — env names per 12 `§8.1` | merchant dashboards `TODO: Confirm` | ☐ |
| 5 | SMS/SMTP production accounts (`env/api.env`) + `noreply@` rate limit check (G-10) | providers | ☐ |
| 6 | Web env: `NEXT_PUBLIC_API_URL`/`NEXT_PUBLIC_SITE_URL` build args on `main` (already in CI) | — | ☐ |
| 7 | `EXPO_TOKEN` + EAS credentials for store builds (app repo) | expo.dev | ☐ |
| 8 | Backups + uptime monitor wired per `docs/backups.md` §1 | — | ☐ |
