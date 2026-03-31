#!/bin/bash
set -euo pipefail

# Create coder user with home on /workspace (persists across restarts)
mkdir -p /workspace/home
if ! id coder &>/dev/null; then
    useradd -m -d /workspace/home/coder -s /bin/bash coder
    echo 'coder ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/coder
    chmod 0440 /etc/sudoers.d/coder
fi

# SSH — copy root's authorized_keys so coder can connect
mkdir -p /workspace/home/coder/.ssh
cp /root/.ssh/authorized_keys /workspace/home/coder/.ssh/ 2>/dev/null || true
chown -R coder:coder /workspace/home/coder/.ssh 2>/dev/null || true
chmod 700 /workspace/home/coder/.ssh
chmod 600 /workspace/home/coder/.ssh/authorized_keys 2>/dev/null || true

echo "[entrypoint] Bootstrap complete"
