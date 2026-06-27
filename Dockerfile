# ClaudeClaw على Railway
# صورة تحتوي Bun + Node + Claude Code CLI + git ثم تشغّل الديمون.

FROM oven/bun:1-debian

# أدوات النظام: git (للـ preflight) + node/npm (لتثبيت Claude Code CLI) + ca-certificates
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git ca-certificates curl xz-utils \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g @anthropic-ai/claude-code \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# سورس ClaudeClaw: يُستنسخ وقت البناء (مستودعك يبقى نظيفاً — ملفات النشر فقط)
# لتثبيت إصدار محدّد، استبدل master بوسم/commit عبر ARG CLAW_REF
ARG CLAW_REF=master
RUN git clone --depth 1 --branch ${CLAW_REF} https://github.com/moazbuilds/claudeclaw.git /app/claudeclaw
WORKDIR /app/claudeclaw

# تصحيح ضروري: ClaudeClaw يجرّد CLAUDE_CODE_OAUTH_TOKEN من بيئة الـ claude الفرعية
# (cleanSpawnEnv). نحذف هذا السطر فقط ليمرّ توكن setup-token الطويل الأمد للمصادقة.
RUN sed -i '/"CLAUDE_CODE_OAUTH_TOKEN",/d' src/runner.ts \
    && echo "patched: CLAUDE_CODE_OAUTH_TOKEN passthrough enabled"

RUN bun install --frozen-lockfile || bun install

# سكربت الإقلاع
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# gosu for dropping privileges after fixing volume permissions at runtime
RUN apt-get update && apt-get install -y --no-install-recommends gosu && rm -rf /var/lib/apt/lists/*

# مستخدم غير root لتجاوز قيود Claude Code مع --dangerously-skip-permissions
RUN useradd --create-home --shell /bin/bash --uid 1001 claudeclaw

# مجلد البيانات الدائم (يُربط بـ Volume على Railway)
ENV HOME=/data
ENV CLAW_WORKDIR=/data/workspace
RUN mkdir -p /data/.claude /data/workspace \
    && chown -R claudeclaw:claudeclaw /data /app

# Do NOT set USER here — entrypoint starts as root to fix volume permissions, then drops to claudeclaw via gosu
WORKDIR /data/workspace
ENTRYPOINT ["/app/entrypoint.sh"]
