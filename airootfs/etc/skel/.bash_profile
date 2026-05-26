# DevOS: load .profile/.bashrc, then auto-start X on the first virtual terminal.
[[ -f ~/.profile ]] && . ~/.profile
[[ -f ~/.bashrc ]] && . ~/.bashrc
if [[ -z ${DISPLAY:-} && ${XDG_VTNR:-0} -eq 1 ]]; then
  exec startx
fi
