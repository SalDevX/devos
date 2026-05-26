# ────────────── ~/.zshrc ──────────────
# Interactive shells only.
# .zshenv has already loaded — PATH and env vars are set.

# ────────────── POWERLEVEL10K INSTANT PROMPT ──────────────
# Must be first — no output before this block.
if [[ -r "${XDG_CACHE_HOME}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ────────────── HISTORY ──────────────
HISTFILE="$HOME/.zsh_history"
HISTSIZE=20000
SAVEHIST=20000
setopt SHARE_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS
setopt EXTENDED_HISTORY       # save timestamp + duration

# ────────────── COMPLETION ──────────────
autoload -Uz compinit
compinit -d "${XDG_CACHE_HOME}/zcompdump-${ZSH_VERSION}"

zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'    # case-insensitive
zstyle ':completion:*' menu select                       # arrow-key menu
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}" # colored completions
zstyle ':completion:*:descriptions' format '%B%d%b'

# ────────────── PLUGINS (Arch packages) ──────────────
# Install: sudo pacman -S zsh-autosuggestions zsh-syntax-highlighting zsh-theme-powerlevel10k
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# ────────────── PROMPT ──────────────
source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

# ────────────── COLORIZE (chroma) ──────────────
export ZSH_COLORIZE_TOOL=chroma
export ZSH_COLORIZE_CHROMA_FORMATTER=terminal256
export ZSH_COLORIZE_STYLE=catppuccin-frappe

# ────────────── SYNTAX HIGHLIGHTING COLORS ──────────────
ZSH_HIGHLIGHT_STYLES[command]="fg=#83a598,bold"
ZSH_HIGHLIGHT_STYLES[alias]="fg=#b8bb26,bold"
ZSH_HIGHLIGHT_STYLES[builtin]="fg=#fe8019,bold"
ZSH_HIGHLIGHT_STYLES[function]="fg=#8ec07c,bold"
ZSH_HIGHLIGHT_STYLES[reserved-word]="fg=#fb4934,bold"
ZSH_HIGHLIGHT_STYLES[precommand]="fg=#d79921,bold"
ZSH_HIGHLIGHT_STYLES[commandseparator]="fg=#bdae93"
ZSH_HIGHLIGHT_STYLES[globbing]="fg=#d3869b"
ZSH_HIGHLIGHT_STYLES[redirection]="fg=#b16286,bold"
ZSH_HIGHLIGHT_STYLES[comment]="fg=#3c3836,italic"
ZSH_HIGHLIGHT_STYLES[error]="fg=#fb4934,bold,underline"
ZSH_HIGHLIGHT_STYLES[command-substitution]="fg=#fe8019"
ZSH_HIGHLIGHT_STYLES[single-hyphen-option]="fg=#b8bb26"
ZSH_HIGHLIGHT_STYLES[double-hyphen-option]="fg=#b8bb26"
ZSH_HIGHLIGHT_STYLES[path]="fg=#87CEEB"
ZSH_HIGHLIGHT_STYLES[variable]="fg=#8ec07c"
ZSH_HIGHLIGHT_STYLES[default]="fg=#bdae93"

# ────────────── KEYBINDINGS ──────────────
bindkey -e                         # emacs mode (default)
bindkey '^R' history-incremental-search-backward
bindkey '^[[A' history-search-backward   # up arrow: history search
bindkey '^[[B' history-search-forward    # down arrow: history search

# sudo widget: press ESC ESC to prepend sudo (replaces OMZ sudo plugin)
_sudo-command-line() {
  [[ -z $BUFFER ]] && zle up-history
  if [[ $BUFFER == sudo\ * ]]; then
    LBUFFER="${LBUFFER#sudo }"
  else
    LBUFFER="sudo $LBUFFER"
  fi
}
zle -N _sudo-command-line
bindkey '\e\e' _sudo-command-line

# copypath: copy current directory to clipboard (replaces OMZ copypath plugin)
copypath() { pwd | tr -d '\n' | xclip -selection clipboard && echo "Copied: $(pwd)" }

# copybuffer: copy current command line to clipboard (replaces OMZ copybuffer plugin)
zle -N copybuffer
copybuffer() { echo -n "$BUFFER" | xclip -selection clipboard }
bindkey '^O' copybuffer

# ────────────── DIRENV ──────────────
eval "$(direnv hook zsh)"

# ────────────── FZF ──────────────
# Install: sudo pacman -S fzf
[[ -f /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh
[[ -f /usr/share/fzf/completion.zsh ]] && source /usr/share/fzf/completion.zsh
bindkey '^R' fzf-history-widget   # override default with fzf

# ────────────── ALIASES — Navigation ──────────────
alias ll='ls -la'
alias lsh='ls | pr -T -w $(tput cols) -3'
alias duh='du -sh -- * 2>/dev/null | pr -T -w $(tput cols) -3'
alias c='clear'

# ────────────── ALIASES — Zsh ──────────────
alias zshconfig="nvim ~/.zshrc"
alias sz='source ~/.zshrc'
alias xz='exec zsh'

# ────────────── ALIASES — Git ──────────────
alias gst='git status'           # gs conflicts with ghostscript
alias dotfiles='git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'

# ────────────── ALIASES — System ──────────────
alias neo='neofetch | lolcat'
alias blame='systemd-analyze blame'
alias ccache='sudo /usr/local/bin/clean_caches'

# ────────────── ALIASES — Display ──────────────
alias panel='xfce4-panel --preferences'
alias dp1off='xrandr --output eDP1 --off'
alias dunstr='killall dunst; dunst &'

# ────────────── ALIASES — Audio ──────────────
alias mixer='alsamixer -D equal'
alias pulseon='pulseaudio --start'
alias stop-pulse="systemctl --user stop pulseaudio.service pulseaudio.socket"
alias jackpulse='pactl load-module module-jack-sink; pactl load-module module-jack-source'
alias boosteq='/home/user/audio-scripts/structured-project-eq-plus/build/guitar_eq_plus-ui'
alias super='/home/user/.local/bin/toggle-reaper-mode.sh'

# ────────────── ALIASES — Network & Security ──────────────
alias Networking='sudo systemctl start NetworkManager.service firewalld.service'
alias firewall='sudo /usr/local/bin/daw-firewall-toggle'
alias torbrowser='firejail --private --private-etc=hosts,ssl /opt/tor-browser/start-with-system-tor.sh'

# ────────────── ALIASES — Tools ──────────────
alias ytdownload='yt-dlp -x --audio-format wav'
alias Wine='flatpak run org.winehq.Wine wine'
alias default.target='sudo systemctl set-default graphical.target'
alias gimp='UBUNTU_MENUPROXY=0 gimp'
alias inkscape='UBUNTU_MENUPROXY=0 inkscape'

# ────────────── ALIASES — QEMU/VMs ──────────────
alias debian='qemu-system-x86_64 \
  -enable-kvm -m 2048 -smp 2 \
  -hda ~/debian-tor-vm.qcow2 \
  -boot c -vga virtio \
  -display gtk,gl=on \
  -device usb-ehci,id=ehci \
  -device usb-tablet \
  -device usb-kbd \
  -net user,hostfwd=tcp::19050-:9050 \
  -net nic'

# ────────────── FUNCTIONS ──────────────

# Navigate with yazi and cd into selected directory
zcd() {
  local cwd_file="/tmp/yazi-cwd"
  yazi --cwd-file "$cwd_file" "$@"
  if [[ -f "$cwd_file" && -r "$cwd_file" ]]; then
    local new_dir="$(<"$cwd_file")"
    if [[ -d "$new_dir" ]]; then
      cd "$new_dir" 2>/dev/null || echo "⚠️  Permission denied: $new_dir"
    fi
    rm -f "$cwd_file"
  fi
}

# Open yazi (z is cleaner without OMZ conflict)
z() { yazi "$@" }

# Launch brave-beta if not already running
web() {
  if pgrep -f "brave" >/dev/null; then
    echo "Brave is already running"
  else
    echo "Launching brave-beta..."
    nohup brave-beta >/dev/null 2>&1 &
    disown
  fi
}

# Search history by pattern
hist() { history | grep -E "^[[:space:]]*[0-9]+[[:space:]]+$1" }

# Find N most recently modified files in a directory
latest() {
  local count=20 folder="/"
  for arg in "$@"; do
    [[ "$arg" =~ ^[0-9]+$ ]] && count="$arg"
    [[ -d "$arg" ]] && folder="$arg"
  done
  echo "📂 Searching in: $folder (top $count)"
  find "$folder" -xdev -type f -printf '%T@ %s %p\n' 2>/dev/null \
    | sort -nr \
    | head -n "$count" \
    | while read -r time size path; do
        timestamp=$(date -d "@${time%%.*}" "+%Y-%m-%d %H:%M:%S")
        size_h=$(numfmt --to=iec --suffix=B "$size" 2>/dev/null || echo "${size}B")
        echo "$timestamp | $size_h | $path"
      done
}

# ────────────── STARTUP MESSAGE ──────────────
