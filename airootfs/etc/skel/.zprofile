# DevOS: first-login welcome — print the MOTD once, before X starts.
if [[ ! -e ~/.config/devos/.welcomed ]]; then
  [[ -r /etc/motd ]] && cat /etc/motd
  mkdir -p ~/.config/devos && touch ~/.config/devos/.welcomed
  print -P '%F{yellow}Set your password now: run  passwd  (press Enter to continue)%f'
  read -r _
fi

# DevOS: TTY -> startx -> XFCE. Auto-start X on the first virtual terminal only.
if [[ -z ${DISPLAY:-} && ${XDG_VTNR:-0} -eq 1 ]]; then
  exec startx
fi
