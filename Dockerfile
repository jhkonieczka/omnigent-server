# Omnigent Studio for the Go Painting franchise network (studio.gopainting.com). No secrets in this image:
# accounts, cookie secret and agent credentials arrive as environment variables; state lives on the /data volume.
FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends git curl ca-certificates && rm -rf /var/lib/apt/lists/*
# no bytecode at build time: a .pyc temp file vanishing between layers broke the first build (containerd lstat)
ENV PYTHONDONTWRITEBYTECODE=1 UV_COMPILE_BYTECODE=0
RUN pip install --no-cache-dir uv && uv tool install "omnigent==0.16.0" && find /root/.local/share/uv -name "__pycache__" -type d -prune -exec rm -rf {} +
ENV PATH="/root/.local/bin:${PATH}" HOME=/data OMNIGENT_HOME=/data/.omnigent
COPY agents /opt/agents
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && mkdir -p /data
VOLUME ["/data"]
EXPOSE 6767
CMD ["/entrypoint.sh"]
