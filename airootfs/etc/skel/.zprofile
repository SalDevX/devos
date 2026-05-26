# DevOS: TTY -> startx -> XFCE. Auto-start X on the first virtual terminal only.
if [[ -z ${DISPLAY:-} && ${XDG_VTNR:-0} -eq 1 ]]; then
  exec startx
fi
