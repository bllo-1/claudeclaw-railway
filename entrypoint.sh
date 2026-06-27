#!/usr/bin/env bash
set -euo pipefail

# ───────────────────────────────────────────────────────────────
# ClaudeClaw entrypoint لـ Railway
# يحقن بيانات الاعتماد + توكن الداشبورد، يبني settings.json، ثم يشغّل الديمون.
# ───────────────────────────────────────────────────────────────

HOME="${HOME:-/data}"
WORKDIR="${CLAW_WORKDIR:-/data/workspace}"
CLAW_DIR="$WORKDIR/.claude/claudeclaw"

# Fix volume permissions — Railway volumes are mounted as root.
# We run this as root, then drop to claudeclaw via gosu.
mkdir -p "$HOME/.claude" "$CLAW_DIR"
chown -R claudeclaw:claudeclaw "$HOME" /app
cd "$WORKDIR"

# 1) مصادقة Claude Code — طريقتان مدعومتان:
#    (أ) CLAUDE_CODE_OAUTH_TOKEN: توكن طويل الأمد من `claude setup-token` (المُوصى به).
#        يمرّ تلقائياً لعملية claude الفرعية (بعد تصحيح cleanSpawnEnv في الـ Dockerfile).
#    (ب) CLAUDE_CREDENTIALS_JSON: محتوى ~/.claude/.credentials.json كامل (يحوي refresh token).
if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  echo "[entrypoint] auth via CLAUDE_CODE_OAUTH_TOKEN (setup-token)"
elif [ -n "${CLAUDE_CREDENTIALS_JSON:-}" ]; then
  printf '%s' "$CLAUDE_CREDENTIALS_JSON" > "$HOME/.claude/.credentials.json"
  chmod 600 "$HOME/.claude/.credentials.json"
  echo "[entrypoint] auth via credentials.json"
elif [ -f "$HOME/.claude/.credentials.json" ]; then
  echo "[entrypoint] using existing credentials from volume"
else
  echo "[entrypoint] WARNING: no Claude auth provided — claude will be 'Not logged in'"
fi

# 2) توكن الداشبورد — ثبّته لتعرف كيف تدخل (وإلا يُولَّد عشوائياً ويُطبع في اللوق)
if [ -n "${WEB_TOKEN:-}" ]; then
  printf '%s\n' "$WEB_TOKEN" > "$CLAW_DIR/web.token"
  chmod 600 "$CLAW_DIR/web.token"
  echo "[entrypoint] web dashboard token set from WEB_TOKEN"
fi

# 3) بناء settings.json (يُدمج مع الافتراضيات). الـ tokens نفسها تُقرأ من البيئة.
#    مهم: من v1.0.26 لازم allowedUserIds غير فاضية وإلا الديمون يرفض الإقلاع مع بوت مفعّل.
PORT="${PORT:-4632}"
HEARTBEAT_ENABLED="${HEARTBEAT_ENABLED:-false}"
HEARTBEAT_INTERVAL="${HEARTBEAT_INTERVAL:-30}"

DISCORD_ALLOWED_USER_IDS="${DISCORD_ALLOWED_USER_IDS:-}"
DISCORD_LISTEN_CHANNELS="${DISCORD_LISTEN_CHANNELS:-}"
SLACK_ALLOWED_USER_IDS="${SLACK_ALLOWED_USER_IDS:-}"
SLACK_LISTEN_CHANNELS="${SLACK_LISTEN_CHANNELS:-}"

# نولّد settings.json بأمان عبر bun (يتعامل مع المصفوفات والاقتباس)
SETTINGS_FILE="$CLAW_DIR/settings.json" \
PORT="$PORT" HEARTBEAT_ENABLED="$HEARTBEAT_ENABLED" HEARTBEAT_INTERVAL="$HEARTBEAT_INTERVAL" \
DISCORD_ALLOWED_USER_IDS="$DISCORD_ALLOWED_USER_IDS" DISCORD_LISTEN_CHANNELS="$DISCORD_LISTEN_CHANNELS" \
SLACK_ALLOWED_USER_IDS="$SLACK_ALLOWED_USER_IDS" SLACK_LISTEN_CHANNELS="$SLACK_LISTEN_CHANNELS" \
bun -e '
  const fs = require("fs");
  const splitList = (s) => (s || "").split(",").map(x => x.trim()).filter(Boolean);
  const settings = {
    web: { enabled: true, host: "0.0.0.0", port: Number(process.env.PORT) || 4632 },
    heartbeat: {
      enabled: process.env.HEARTBEAT_ENABLED === "true",
      interval: Number(process.env.HEARTBEAT_INTERVAL) || 30,
    },
    discord: {
      allowedUserIds: splitList(process.env.DISCORD_ALLOWED_USER_IDS),
      listenChannels: splitList(process.env.DISCORD_LISTEN_CHANNELS),
    },
    slack: {
      allowedUserIds: splitList(process.env.SLACK_ALLOWED_USER_IDS),
      listenChannels: splitList(process.env.SLACK_LISTEN_CHANNELS),
    },
  };
  fs.writeFileSync(process.env.SETTINGS_FILE, JSON.stringify(settings, null, 2) + "\n");
  console.log("[entrypoint] wrote settings.json (web on 0.0.0.0:" + settings.web.port + ")");
'

# 4) بناء قائمة الأعلام بحسب ما هو مفعّل
FLAGS=(start --web --web-port "$PORT")

if [ "${ENABLE_DISCORD:-false}" = "true" ]; then
  if [ -z "${DISCORD_TOKEN:-}" ]; then echo "[entrypoint] ERROR: ENABLE_DISCORD=true لكن DISCORD_TOKEN فاضي"; exit 1; fi
  if [ -z "$DISCORD_ALLOWED_USER_IDS" ]; then echo "[entrypoint] ERROR: لازم DISCORD_ALLOWED_USER_IDS مع تفعيل Discord"; exit 1; fi
  FLAGS+=(--discord)
fi

if [ "${ENABLE_SLACK:-false}" = "true" ]; then
  if [ -z "${SLACK_BOT_TOKEN:-}" ] || [ -z "${SLACK_APP_TOKEN:-}" ]; then echo "[entrypoint] ERROR: Slack يحتاج SLACK_BOT_TOKEN و SLACK_APP_TOKEN"; exit 1; fi
  if [ -z "$SLACK_ALLOWED_USER_IDS" ]; then echo "[entrypoint] ERROR: لازم SLACK_ALLOWED_USER_IDS مع تفعيل Slack"; exit 1; fi
  FLAGS+=(--slack)
fi

echo "[entrypoint] starting: bun run /app/claudeclaw/src/index.ts ${FLAGS[*]}"
exec gosu claudeclaw bun run /app/claudeclaw/src/index.ts "${FLAGS[@]}"
