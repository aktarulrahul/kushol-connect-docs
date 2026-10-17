# Secret-rotation runbook (OPS-BE-011)

All secrets live only in `/opt/kushol/env/*.env` (root-owned, chmod 600 — `prepare-host.sh`
enforces it). Rotation never touches the repo or CI. Default expectation: < 5 min impact or a
scheduled window. After ANY rotation: `ops/deploy.sh` restart (or `compose up -d`) + redaction
probe + a one-line change-log entry in `state/releases.log`.

| Credential | Where | Rotation steps | Impact |
| --- | --- | --- | --- |
| `JWT_SECRET` | `env/api.env` | generate 32B → update → `docker compose up -d api worker` → all sessions invalidate (users re-login) | brief; announce |
| `DATABASE_URL` password | Neon console → `env/api.env` | rotate in Neon first, keep the old role valid through the overlap, update env, restart api/worker, then revoke the old role | zero-downtime with overlap |
| `ERP_SECRET_KEY` (14) | `env/api.env` | ⚠ decrypts existing ERP secrets — rotate via a re-encrypt job, not in place; until that ships, rotate = re-register endpoints (show-once new secrets) | endpoint re-registration |
| `PAYMENTS_WEBHOOK_SECRET` | `env/api.env` | change the sandbox gateway secret + env + restart; real gateways: rotate in the dashboard first | webhook gap < 1 min |
| `R2_*` (media) | `env/api.env` | new token in CF dashboard → update env → restart api → revoke old token | uploads pause seconds |
| `FCM_SERVICE_ACCOUNT_JSON` / `FCM_PROJECT_ID` | `env/api.env` | new service-account key → env → restart; devices unaffected (token push model) | none |
| `SMTP_*` / SMS gateway keys | `env/api.env` | provider-side rotate → env → restart | OTP send pause seconds |
| `EXPO_TOKEN` (CI/EAS) | GitHub secret + `eas.json`-side login | rotate in expo.dev → update the GitHub secret → revoke old | CI only |
| Docker Hub pull token / deploy SSH keys | host `~/.ssh`, GitHub | keygen → authorized_keys append → test → remove old | deploys pause |
| `ERP endpoint secrets` (schools') | 14 DB (versioned) | School Admin self-serve: `POST /school/erp/endpoints/{id}/rotate-secret` (24 h overlap) | none |
