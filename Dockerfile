# syntax=docker/dockerfile:1.7
FROM ghcr.io/openclaw/openclaw:latest

USER root

ENV HOME=/home/node \
    OPENCLAW_STATE_DIR=/home/node/.openclaw \
    OPENCLAW_CONFIG_PATH=/home/node/.openclaw/openclaw.json \
    DEBIAN_FRONTEND=noninteractive \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# System deps (Python, MySQL client, matplotlib runtime libs).
# Cache mounts on /var/cache/apt and /var/lib/apt let BuildKit reuse the
# downloaded indexes/packages across rebuilds; the cache lives outside the
# image, so we don't need `rm -rf /var/lib/apt/lists/*` to keep the layer slim.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        python3 python3-pip default-mysql-client \
        libfreetype6 libpng16-16 libfontconfig1

# Python deps go BEFORE workspace/config files so edits to prompts, skills,
# or the entrypoint don't bust this layer. The pip cache mount keeps wheels
# warm across the rare requirements.txt change.
COPY --chown=node:node requirements.txt /opt/analyst/requirements.txt
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install -r /opt/analyst/requirements.txt

# Project files — small, change often, cheap to recopy.
COPY --chown=node:node configs/ /opt/analyst/configs/
COPY --chown=node:node openclaw-config/ /opt/analyst/openclaw-config/
COPY --chown=node:node generate_starbucks_db.py /opt/analyst/generate_starbucks_db.py
COPY --chown=node:node --chmod=0755 docker/entrypoint.sh /opt/analyst/entrypoint.sh

EXPOSE 18789

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s \
    CMD node -e "fetch('http://127.0.0.1:18789/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

# Stay root at entry so the entrypoint can chown the state volume (which Docker
# creates root-owned on first mount) before re-exec'ing as `node` via `su -p`.
ENTRYPOINT ["/opt/analyst/entrypoint.sh"]
