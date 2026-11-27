# MARVIN Autonomous Cloud — Implementation Plan

## Product goal

MARVIN is a continuously running, cloud-hosted YouTube operations agent. The owner's computer may be offline while MARVIN continues its scheduled work. The owner reviews a monthly report and can pause the system at any time.

This document is an implementation plan, not a claim that cloud hosting, video rendering, account linking, or publishing already works.

## Operating policy

- Default operation: autonomous for routine research, ideation, scripting, asset generation, editing, scheduling, publishing, analytics collection, and iteration after the owner explicitly connects and authorizes the relevant account.
- No credentials in browser storage, source code, Git history, logs, or ordinary job records. Use a server-side secrets manager and official OAuth flows with least-privilege scopes.
- No bypassing platform rules, rate limits, copyright checks, monetization rules, or account security checks.
- Financial autonomy is bounded: the owner sets a monthly spending cap and a per-action cap. MARVIN may spend only within the remaining approved budget. It must not raise its own limits, borrow, transfer funds, withdraw money, or purchase financial products.
- Revenue reporting must distinguish estimated platform revenue from money actually paid out. MARVIN cannot guarantee earnings.
- Pause and alert on suspected account compromise, unexpected charges, repeated policy failures, missing authorization, or spend-limit exhaustion.
- Keep an immutable audit trail for publishing actions, spending, account changes, and agent decisions. Provide a kill switch and a monthly exportable report.

## Target cloud architecture

1. **Control plane** — authenticated owner dashboard, configuration, permissions, budget limits, pause/resume, and audit log.
2. **Orchestrator** — durable workflow engine with retries, timeouts, idempotency keys, and scheduled jobs.
3. **Agent runtime** — planner and task-specific agents for research, scripts, production, quality review, publishing, and analytics. Agents receive only the tools and permissions needed for their task.
4. **Production workers** — isolated workers for text, voice, image/video generation, rendering, captions, and packaging. Heavy GPU work is a separate worker pool and may scale to zero when idle.
5. **Data layer** — managed relational database for jobs and state; object storage for source assets and final media; backups and retention policies.
6. **Integration layer** — official YouTube APIs and other explicitly enabled providers, using OAuth tokens stored server-side and refreshed securely.
7. **Observability** — health checks, structured logs, cost metering, failure alerts, and monthly performance reports.

## Learning loop

- Collect permitted analytics and production-quality signals.
- Compare results against a documented baseline and channel-specific goals.
- Propose and test bounded changes (topics, hooks, pacing, thumbnails, titles, timing) using small experiments.
- Keep a record of each experiment, its cost, and measured result.
- Roll back changes that reduce quality or trigger policy/copyright risks.
- Do not self-modify production code or grant itself new permissions. Model/prompt changes go through versioned evaluations and a safe rollout.

## Delivery phases

### Phase 1 — Make the current prototype cloud-ready
- Separate configuration from code and add environment validation.
- Replace browser-only/local-file assumptions with authenticated server APIs.
- Add persistent job state, migrations, audit events, and health endpoints.
- Add automated tests for authorization, retries, budget enforcement, and job recovery.

### Phase 2 — Deploy a private control plane and worker
- Deploy to a managed cloud service/VM with TLS, authentication, backups, monitoring, and a private database.
- Keep development and production environments separate.
- Configure worker concurrency and hard resource/cost limits.

### Phase 3 — Production pipeline
- Add real voice/media providers and rendering workers.
- Save every generated asset and final export to private object storage.
- Add automated quality checks for duration, audio, captions, visual integrity, and duplicate content.

### Phase 4 — Account integrations and autonomous publishing
- Connect YouTube through official OAuth only after the owner explicitly authorizes it.
- Start with private/unlisted test uploads, then enable public scheduling once the workflow is verified.
- Respect API quotas, platform policies, copyright checks, and monetization requirements.

### Phase 5 — Analytics and bounded optimization
- Collect channel analytics on a schedule.
- Run controlled experiments and maintain a decision log.
- Generate monthly reports with published videos, views, retention where available, revenue estimates vs. payouts, expenses, and net results.

## Current repository status

The existing ai-studio branch is an early local prototype. It has a React/Vite dashboard, a local Node API, Ollama text generation, and a local job queue. It does not yet provide cloud hosting, durable multi-user authentication, video rendering, voice generation, OAuth, or automatic YouTube publishing. Do not present the prototype as a deployed autonomous service.

## Decisions intentionally deferred

- Cloud provider and region.
- Monthly operating budget and maximum spend per action.
- Media generation providers and GPU requirements.
- Account/channel identity and OAuth scopes.
- Retention period for source assets and generated media.

These must be selected based on actual cost, hardware/provider availability, privacy requirements, and the owner's account permissions.

## Private license verification (development branch)

The API now includes `POST /api/license/verify`. It is deliberately fail-closed:
- The endpoint returns HTTP 503 until both `MARVIN_LICENSE_PEPPER` and a non-empty `MARVIN_LICENSES_JSON` allowlist are configured on the server.
- License keys are never stored in this repository. The allowlist contains HMAC-SHA256 digests, not plaintext keys.
- Each record supports `status` (`active` or another non-active value), optional `plan`, optional `licenseId`, and optional ISO-8601 `expiresAt`.
- Unknown, revoked, and expired keys are rejected. The endpoint has a per-source-IP in-memory attempt limit; production deployment should also use an edge/WAF rate limit.
- The hash helper reads a key from standard input and prints only its digest: `MARVIN_LICENSE_PEPPER='...' npm run hash:license`. Do not put real keys or the pepper in shell history, source files, GitHub Actions logs, or chat. Use a managed secret store for deployment.
- This endpoint is not yet deployed and is not connected to the existing Roblox script or its current public key list. Existing users therefore keep their current access path unchanged. Do not switch clients until a private host, secret configuration, migration plan, and end-to-end client test are ready.
- The in-memory allowlist is suitable only as an initial integration step; production should move license records to a durable private database with an audited admin workflow, revocation, and backup.

