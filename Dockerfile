FROM ghcr.io/openclaw/openclaw:latest

USER root

# Install Python 3, pip, and sqlite3
RUN apt-get update && \
    apt-get install -y --no-install-recommends python3 python3-pip sqlite3 && \
    rm -rf /var/lib/apt/lists/*

# Copy project files
COPY --chown=node:node configs/ /opt/analyst/configs/
COPY --chown=node:node openclaw-config/ /opt/analyst/openclaw-config/
COPY --chown=node:node generate_starbucks_db.py /opt/analyst/generate_starbucks_db.py
COPY --chown=node:node requirements.txt /opt/analyst/requirements.txt

# Install Python dependencies
RUN pip3 install --no-cache-dir --break-system-packages -r /opt/analyst/requirements.txt

# Copy and prepare entrypoint
COPY --chown=node:node docker/entrypoint.sh /opt/analyst/entrypoint.sh
RUN chmod +x /opt/analyst/entrypoint.sh

USER node

EXPOSE 18789

HEALTHCHECK --interval=3m --timeout=10s \
    CMD node -e "fetch('http://127.0.0.1:18789/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["/opt/analyst/entrypoint.sh"]
