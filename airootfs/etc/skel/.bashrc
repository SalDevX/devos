# ~/.bashrc - minimal version

# Only run if interactive shell
[[ $- != *i* ]] && return

# Simple prompt
PS1='(\W)$ '

# Aliases
alias ls='ls --color=auto'
#  alias X='startx'
alias X='SESSION=xfce startx'
alias D='SESSION=dwm startx'



# Minimal PATH additions if needed (adjust to your needs)
export PATH=$HOME/.local/bin:$PATH

# No complicated commands or exec redirections here

latest() {
    local count=20
    local folder="/"
    local old_path="$PATH"  # save PATH

    for arg in "$@"; do
        if [[ "$arg" =~ ^[0-9]+$ ]]; then
            count="$arg"
        elif [[ -d "$arg" ]]; then
            folder="$arg"
        fi
    done

    echo "📂 Searching in: $folder"
    echo "🔢 Showing $count most recently changed files..."
    echo

    /usr/bin/find "$folder" -xdev -type f -printf '%T@ %s %p\n' 2>/dev/null \
    | /usr/bin/sort -nr \
    | /usr/bin/head -n "$count" \
    | while read -r time size path; do
        timestamp=$(/usr/bin/date -d @"${time%%.*}" "+%Y-%m-%d %H:%M:%S")
        size_h=$(/usr/bin/numfmt --to=iec --suffix=B "$size" 2>/dev/null || echo "${size}B")
        echo "$timestamp | $size_h | $path"
    done

    export PATH="$old_path"  # restore PATH here at function end
}

# Run neofetch only on real TTYs and not inside TMUX
if [[ -z "$TMUX" && $(tty) =~ ^/dev/tty[0-9]+$ ]]; then
    neofetch | lolcat
fi

### shopt -s histappend

export HISTFILE=~/.config/bash/history
HISTSIZE=10000
HISTFILESIZE=20000

#export LIBVA_DRIVER_NAME=i965



export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.npm-global/bin:$PATH"
alias blender='~/Applications/blender-3.6-lts/blender'
