# Omnigent Studio for the Go Painting franchise network (studio.gopainting.com).
# The server is also the HOST (Jay 2026-10-05): Claude Code runs here on the corporate seat, the proposal kit is
# cloned here, and the franchise credentials are server-held. Franchisees never hold a Claude login or a key.
# No secrets in this image: everything arrives as environment variables; state lives on the /data volume.
FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends git curl ca-certificates gnupg ripgrep jq tmux procps && rm -rf /var/lib/apt/lists/*
# Node 20 + Claude Code (the claude-native harness drives the real CLI)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt-get install -y --no-install-recommends nodejs && rm -rf /var/lib/apt/lists/* \
 && npm install -g @anthropic-ai/claude-code@latest && npm cache clean --force
# no bytecode at build time: a .pyc temp file vanishing between layers broke the first build (containerd lstat)
ENV PYTHONDONTWRITEBYTECODE=1 UV_COMPILE_BYTECODE=0
RUN pip install --no-cache-dir uv openpyxl pypdf requests && uv tool install "omnigent==0.17.0" \
 && find /root/.local/share/uv -name "__pycache__" -type d -prune -exec rm -rf {} +
ENV PATH="/root/.local/bin:${PATH}" HOME=/data OMNIGENT_HOME=/data/.omnigent
# SameSite=None cookie + CORS allow-list so the engine workspace (proposals.gopainting.com) can frame and drive this
# Studio with the owner's login (the same local patch Jay's droplet carries; upstream it)
COPY patch_samesite.py /opt/patch_samesite.py
RUN python3 /opt/patch_samesite.py "$(find /root/.local/share/uv/tools/omnigent -type d -path '*/site-packages/omnigent' | head -1)"
COPY agents /opt/agents
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && mkdir -p /data
VOLUME ["/data"]
EXPOSE 6767
CMD ["/entrypoint.sh"]
