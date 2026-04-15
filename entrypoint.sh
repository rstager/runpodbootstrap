#!/bin/bash
set -euo pipefail

# Idempotent — safe to run on first start and on every restart.
# Runs entirely as root with IS_SANDBOX=1.

BASHRC="/root/.bashrc"

# 1. Disable SSH StrictModes so key auth works even when /workspace can't be chowned
grep -qF 'StrictModes no' /etc/ssh/sshd_config || {
    echo 'StrictModes no' >> /etc/ssh/sshd_config
    service ssh restart 2>/dev/null || true
}

# 2. Source .env if present (secrets: HF_TOKEN, WANDB_KEY, GITHUB_TOKEN, etc.)
for env_file in /workspace/*/.env; do
    [ -f "$env_file" ] && { set -a; source "$env_file"; set +a; }
done

# 3. Patch .bashrc to auto-source .env files in every shell
BASHRC_MARKER="# cloud: auto-source project .env files"
if ! grep -qF "$BASHRC_MARKER" "$BASHRC" 2>/dev/null; then
    cat >> "$BASHRC" << 'BASHEOF'

# cloud: auto-source project .env files
for _env in /workspace/*/.env; do
    [ -f "$_env" ] && { set -a; source "$_env"; set +a; }
done
unset _env
BASHEOF
fi

# 4. Set IS_SANDBOX=1 so claude --dangerously-skip-permissions works as root
SANDBOX_MARKER="# cloud: IS_SANDBOX for claude root bypass"
if ! grep -qF "$SANDBOX_MARKER" "$BASHRC" 2>/dev/null; then
    cat >> "$BASHRC" << 'BASHEOF'

# cloud: IS_SANDBOX for claude root bypass
export IS_SANDBOX=1
BASHEOF
fi
export IS_SANDBOX=1

# 5. Install system utilities: tmux, vim
apt-get update -qq && apt-get install -y -qq tmux vim

# 6. Restore tmux config
cat > "$HOME/.tmux.conf" << 'EOF'
set -g mouse on
set -g default-terminal "xterm-256color"
EOF

# 7. Install Claude Code
CLAUDE_BASHRC_MARKER="# cloud: claude-code PATH"
export PATH="$HOME/.claude/bin:$PATH"
if ! command -v claude &>/dev/null; then
    curl -fsSL https://claude.ai/install.sh | bash
fi
if ! grep -qF "$CLAUDE_BASHRC_MARKER" "$BASHRC" 2>/dev/null; then
    cat >> "$BASHRC" << 'BASHEOF'

# cloud: claude-code PATH
export PATH="$HOME/.claude/bin:$PATH"
BASHEOF
fi

# 8. Install uv
UV_BASHRC_MARKER="# cloud: uv PATH"
export PATH="$HOME/.local/bin:$PATH"
if ! command -v uv &>/dev/null; then
    curl -fsSL https://astral.sh/uv/install.sh | sh
fi
if ! grep -qF "$UV_BASHRC_MARKER" "$BASHRC" 2>/dev/null; then
    cat >> "$BASHRC" << 'BASHEOF'

# cloud: uv PATH
export PATH="$HOME/.local/bin:$PATH"
BASHEOF
fi

# 9. Configure git credentials
if [ -n "${GITHUB_TOKEN:-}" ]; then
    git config --global credential.helper store
    echo "https://x-token:${GITHUB_TOKEN}@github.com" > ~/.git-credentials
    chmod 600 ~/.git-credentials
fi
git config --global user.name "${GIT_USER_NAME:-Roger}"
git config --global user.email "${GIT_USER_EMAIL:-rkstager@gmail.com}"

# 10. GPU check
echo "[entrypoint] GPU:"
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null \
    || echo "[entrypoint] WARNING: nvidia-smi failed"

# 11. Launch Claude in a background tmux session named "claude"
#     --dangerously-skip-permissions: no tool approval prompts
#     --remote-control: enables iOS app / remote access
#     Idempotent: skip if session already exists
if tmux has-session -t claude 2>/dev/null; then
    echo "[entrypoint] tmux session 'claude' already running — skipping launch"
else
    echo "[entrypoint] Starting Claude in tmux session 'claude'..."
    tmux new-session -d -s claude -c /root \
        "claude --dangerously-skip-permissions --remote-control"
    echo "[entrypoint] Claude session started — attach with: tmux attach -t claude"
fi

echo "[entrypoint] Bootstrap complete"
