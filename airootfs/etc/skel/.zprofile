# DevOS: TTY -> startx -> XFCE. Auto-start X on the first virtual terminal only.
# plymouth-quit-wait.service expects display-manager.service which never fires in
# our agetty+startx setup — quit Plymouth here so it releases the VT before X starts.
if [[ -z ${DISPLAY:-} && ${XDG_VTNR:-0} -eq 1 ]]; then
  pgrep -x plymouthd >/dev/null 2>&1 && plymouth deactivate 2>/dev/null
  clear
  startx &>/tmp/devos-startx.log
  pgrep -x plymouthd >/dev/null 2>&1 && plymouth quit 2>/dev/null
fi
