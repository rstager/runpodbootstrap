#!/bin/bash
set -euo pipefail

# Create user
mkdir -p /workspace/home/coder
if ! id coder &>/dev/null; then
    useradd -m -d /workspace/home/coder -s /bin/bash coder
    echo 'coder ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/coder
    chmod 0440 /etc/sudoers.d/coder
fi

mkdir -p /workspace/home/coder
chown coder:coder /workspace/home/coder

# SSH
mkdir -p /workspace/home/coder/.ssh
cp /root/.ssh/authorized_keys /workspace/home/coder/.ssh/ 2>/dev/null || true
chown -R coder:coder /workspace/home/coder/.ssh

echo "[entrypoint] Bootstrap complete"
