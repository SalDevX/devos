# DevOS: first-login welcome — skip entirely in the live ISO, show once on installed system.
if [[ ! -e ~/.config/devos/.welcomed ]] && ! grep -q 'archiso' /proc/cmdline 2>/dev/null; then
  [[ -r /etc/motd ]] && cat /etc/motd
  mkdir -p ~/.config/devos && touch ~/.config/devos/.welcomed
  print -P '%F{yellow}Set your password now: run  passwd  (press Enter to continue)%f'
  read -r _
fi

# DevOS: TTY -> startx -> XFCE. Auto-start X on the first virtual terminal only.
if [[ -z ${DISPLAY:-} && ${XDG_VTNR:-0} -eq 1 ]]; then
  exec startx
fi
