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
chmod 700 /workspace/home/coder/.ssh
chmod 600 /workspace/home/coder/.ssh/authorized_keys 2>/dev/null || true

# 5. Disable SSH StrictModes so key auth works even when /workspace can't be chowned
grep -qF 'StrictModes no' /etc/ssh/sshd_config || echo 'StrictModes no' >> /etc/ssh/sshd_config
service ssh restart 2>/dev/null || true


# From here: run as coder
su - coder << 'CODER_EOF'
set -euo pipefail
BASHRC="$HOME/.bashrc"

# 6. Source .env if present (secrets: HF_TOKEN, WANDB_KEY, GITHUB_TOKEN, etc.)
for env_file in "$HOME"/*/.env; do
    [ -f "$env_file" ] && { set -a; source "$env_file"; set +a; }
done

# 7. Patch .bashrc to auto-source .env files in every shell
BASHRC_MARKER="# cloud: auto-source project .env files"
if ! grep -qF "$BASHRC_MARKER" "$BASHRC" 2>/dev/null; then
    cat >> "$BASHRC" << 'BASHEOF'

# cloud: auto-source project .env files
for _env in "$HOME"/*/.env; do
    [ -f "$_env" ] && { set -a; source "$_env"; set +a; }
done
unset _env
BASHEOF
fi

# 8. Install system utilities: tmux, vim
sudo apt-get update -qq && sudo apt-get install -y -qq tmux vim

# 9. Restore tmux config
cat > "$HOME/.tmux.conf" << 'EOF'
set -g mouse on
set -g default-terminal "xterm-256color"
EOF

# 10. Install Claude Code
CLAUDE_BASHRC_MARKER="# cloud: claude-code PATH"
if ! command -v claude &>/dev/null; then
    curl -fsSL https://claude.ai/install.sh | bash
fi
if ! grep -qF "$CLAUDE_BASHRC_MARKER" "$BASHRC" 2>/dev/null; then
    cat >> "$BASHRC" << 'BASHEOF'

# cloud: claude-code PATH
export PATH="$HOME/.claude/bin:$PATH"
BASHEOF
fi
export PATH="$HOME/.claude/bin:$PATH"

# 11. Install uv
UV_BASHRC_MARKER="# cloud: uv PATH"
if ! command -v uv &>/dev/null; then
    curl -fsSL https://astral.sh/uv/install.sh | sh
fi
if ! grep -qF "$UV_BASHRC_MARKER" "$BASHRC" 2>/dev/null; then
    cat >> "$BASHRC" << 'BASHEOF'

# cloud: uv PATH
export PATH="$HOME/.local/bin:$PATH"
BASHEOF
fi
export PATH="$HOME/.local/bin:$PATH"

# 12. Configure git credentials
if [ -n "${GITHUB_TOKEN:-}" ]; then
    git config --global credential.helper store
    echo "https://x-token:${GITHUB_TOKEN}@github.com" > ~/.git-credentials
fi
git config --global user.name "${GIT_USER_NAME:-Roger}"
git config --global user.email "${GIT_USER_EMAIL:-rkstager@gmail.com}"

# 13. GPU check
echo "[entrypoint] GPU:"
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null \
    || echo "[entrypoint] WARNING: nvidia-smi failed"

# 14. Disk check
for vol in /workspace "$HOME/data" "$HOME/scratch"; do
    [ -d "$vol" ] && echo "[entrypoint] $vol: $(df -h "$vol" | tail -1 | awk '{print $4}') free"
done

# 15. Launch Claude in a background tmux session named "claude"
#     --dangerously-skip-permissions: no tool approval prompts
#     --remote-control: enables iOS app / remote access
#     Idempotent: skip if session already exists
if tmux has-session -t claude 2>/dev/null; then
    echo "[entrypoint] tmux session 'claude' already running — skipping launch"
else
    echo "[entrypoint] Starting Claude in tmux session 'claude'..."
    tmux new-session -d -s claude -c "$HOME" \
        "claude --dangerously-skip-permissions --remote-control"
    echo "[entrypoint] Claude session started — attach with: tmux attach -t claude"
fi

CODER_EOF

echo "[entrypoint] Bootstrap complete"
tail -f /dev/null
