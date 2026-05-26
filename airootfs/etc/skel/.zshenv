# ────────────── ~/.zshenv ──────────────
# Loaded for EVERY zsh instance — interactive, non-interactive, scripts.
# Keep this lean: only what scripts and tools need.
# Never produce output here (breaks scp, rsync, etc.)

# ── Cargo (must come before PATH build) ──
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

# ── XDG Base Dirs ──
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"

# ── PATH ──
typeset -U path  # zsh deduplicates automatically
path=(
  "$HOME/go/bin"
  "$HOME/bin"
  "$HOME/.local/bin"
  "$HOME/.cargo/bin"
  "$HOME/.npm-global/bin"
  "$HOME/.local/share/gem/ruby/3.3.0/bin"
  "/usr/local/sbin"
  "/usr/local/bin"
  "/usr/bin"
  "/bin"
  "/sbin"
  $path
)
export PATH

# ── Core env ──
export LANG="en_US.UTF-8"
export EDITOR="nvim"
export VISUAL="nvim"
export GPG_TTY="$(tty)"

# ── Tmux ──
export TMUX_PLUGIN_MANAGER_PATH="$HOME/.tmux/plugins"
export TMUX_CONF="$HOME/.tmux/.tmux.conf"

# ── Audio ──
export LADSPA_PATH="/usr/lib/ladspa"

# ── Misc ──
export XAUTHORITY="$HOME/.Xauthority"
export REGISTRATION_CODE="unixlike"

# ── Secrets (gitignored) ──
[[ -f "$HOME/.zshenv.secret" ]] && source "$HOME/.zshenv.secret"
