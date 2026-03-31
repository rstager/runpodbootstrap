#!/bin/bash
set -euo pipefail

# Idempotent — safe to run on first start and on every restart.

# 1. Install sudo if missing
if ! command -v sudo &>/dev/null; then
    apt-get update -qq && apt-get install -y -qq sudo
fi

# 2. Create coder user with home on /workspace (persists across pod restarts)
mkdir -p /workspace/home
if ! id coder &>/dev/null; then
    useradd -m -d /workspace/home/coder -s /bin/bash coder
fi

# 3. Grant passwordless sudo (idempotent — overwrites same file each run)
mkdir -p /etc/sudoers.d
echo 'coder ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/coder
chmod 0440 /etc/sudoers.d/coder

# 4. SSH — ensure coder can connect with the same key as root
mkdir -p /workspace/home/coder/.ssh
cp /root/.ssh/authorized_keys /workspace/home/coder/.ssh/authorized_keys 2>/dev/null || true
chown -R coder:coder /workspace/home/coder/.ssh 2>/dev/null || true
chmod 700 /workspace/home/coder/.ssh
chmod 600 /workspace/home/coder/.ssh/authorized_keys 2>/dev/null || true

echo "[entrypoint] Bootstrap complete"
