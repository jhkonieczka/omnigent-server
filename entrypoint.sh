#!/bin/sh
set -e
mkdir -p /data/.omnigent /data/projects
exec omnigent server --host 0.0.0.0 --port 6767 --agent /opt/agents/gp-proposals
