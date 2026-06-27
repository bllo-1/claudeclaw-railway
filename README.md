# ClaudeClaw on Railway 🚂🦞

Production-ready deployment of [ClaudeClaw](https://github.com/moazbuilds/claudeclaw) — an
OpenClaw-style autonomous agent built on Claude Code — as an always-on service on
[Railway](https://railway.app).

This repository contains the container image, entrypoint, and platform config that turn
ClaudeClaw (designed to run on a local machine) into a headless, 24/7 cloud service with a
persistent state volume, a web dashboard, scheduled (cron) jobs, and optional Discord/Slack bots.

> **Why this exists:** ClaudeClaw assumes an interactive local environment with a logged-in
> Claude Code session. Running it headless on a PaaS surfaces three real engineering problems —
> **authentication without a browser, persistent state across redeploys, and safe network exposure.**
> This repo solves all three.

---

## Architecture

```
┌────────────────────── Railway Service ──────────────────────┐
│  Docker image (Bun + Node + Claude Code CLI + git)           │
│                                                              │
│   entrypoint.sh                                              │
│     ├─ injects CLAUDE_CREDENTIALS_JSON → ~/.claude           │
│     ├─ seeds web.token (dashboard auth)                      │
│     ├─ generates settings.json (host 0.0.0.0 : $PORT)        │
│     └─ exec bun run claudeclaw start --web [--discord/slack] │
│                                                              │
│   claudeclaw daemon ──spawns──► claude CLI (subprocess)      │
│         │                                                    │
│         ├─ cron + heartbeat scheduler                        │
│         ├─ web dashboard  (Bearer-token gated)               │
│         └─ Discord / Slack bridges                           │
│                                                              │
│   Volume  →  /data   (credentials, sessions, jobs, logs)     │
└──────────────────────────────────────────────────────────────┘
```

## How the three hard problems are solved

| Problem | Solution |
|---|---|
| **Headless auth** | The daemon strips the ephemeral OAuth env token and relies on Claude Code's credential store. We inject the full `~/.claude/.credentials.json` (incl. refresh token) via the `CLAUDE_CREDENTIALS_JSON` env var and persist it on a volume, so `claude` refreshes automatically. |
| **Persistent state** | A Railway volume mounted at `/data` holds credentials, sessions, scheduled jobs, and logs across redeploys. |
| **Safe exposure** | The dashboard binds to `0.0.0.0:$PORT` and is gated by a `Bearer` token (`WEB_TOKEN`). Bot channels enforce a non-empty `allowedUserIds` allowlist (the daemon refuses to start otherwise). |

## Quick start

1. **Fork/deploy this repo on Railway** → New Project → Deploy from GitHub repo.
2. **Add a Volume** mounted at `/data` (Settings → Volumes).
3. **Set environment variables** (see below).
4. **Generate a public domain** (Settings → Networking) and open
   `https://<app>.up.railway.app/?token=<WEB_TOKEN>`.

### Required environment variables

| Variable | Purpose |
|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` | Long-lived token from `claude setup-token` (recommended). **Secret.** Passed through to the `claude` subprocess via a one-line patch to ClaudeClaw's `cleanSpawnEnv`. |
| `WEB_TOKEN` | Token that gates the web dashboard, e.g. `openssl rand -base64 32`. |

> Alternative to `CLAUDE_CODE_OAUTH_TOKEN`: set `CLAUDE_CREDENTIALS_JSON` to the full contents of your local `~/.claude/.credentials.json` (includes a refresh token). Use one or the other.

`PORT` is provided by Railway automatically — do **not** set it.

> **Note on `cleanSpawnEnv`:** ClaudeClaw deliberately strips `CLAUDE_CODE_OAUTH_TOKEN` from the spawned `claude` environment (to avoid stale 8-hour parent tokens). The `Dockerfile` applies a minimal `sed` patch that removes only that line, so a deliberate long-lived `setup-token` authenticates correctly.

### Optional features

| Variable | Purpose |
|---|---|
| `HEARTBEAT_ENABLED` / `HEARTBEAT_INTERVAL` | Enable periodic autonomous runs (minutes). |
| `ENABLE_DISCORD` + `DISCORD_TOKEN` + `DISCORD_ALLOWED_USER_IDS` | Discord bot (allowlist required). |
| `ENABLE_SLACK` + `SLACK_BOT_TOKEN` + `SLACK_APP_TOKEN` + `SLACK_ALLOWED_USER_IDS` | Slack bot (allowlist required). |

Pin a specific ClaudeClaw version with the `CLAW_REF` build arg (defaults to `master`).

## Files

| File | Role |
|---|---|
| `Dockerfile` | Bun + Node + Claude Code CLI + git; clones ClaudeClaw at build time. |
| `entrypoint.sh` | Injects credentials & token, generates `settings.json`, starts the daemon. |
| `railway.json` | Railway build/deploy config with `/api/health` healthcheck. |

## Security notes

- Start at the **read-only** security level in the dashboard; widen only as needed.
- Treat `CLAUDE_CREDENTIALS_JSON` and the dashboard URL+token as secrets.
- Review Anthropic's Terms of Service before running a subscription-authenticated agent 24/7 on a remote host.

## License

Deployment tooling: MIT. ClaudeClaw itself is MIT © moazbuilds.
