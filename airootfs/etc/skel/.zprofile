# DevOS: TTY -> startx -> XFCE. Auto-start X on the first virtual terminal only.
# This is the LIVE-ISO login path (no display manager). On the INSTALLED system
# SDDM owns tty1 (Conflicts=getty@tty1), so this block never triggers there.
# plymouth-quit-wait.service expects display-manager.service which never fires in
# our agetty+startx setup — quit Plymouth here so it releases the VT before X starts.
if [[ -z ${DISPLAY:-} && ${XDG_VTNR:-0} -eq 1 ]]; then
  pgrep -x plymouthd >/dev/null 2>&1 && plymouth deactivate 2>/dev/null
  clear
  startx &>/tmp/devos-startx.log
  pgrep -x plymouthd >/dev/null 2>&1 && plymouth quit 2>/dev/null
  # X has exited. With no display manager, tty1 becomes visible for a moment on
  # the way out. If the system is shutting down/rebooting, clear it and idle
  # silently so no shell prompt or stray text flashes before the (dark) Plymouth
  # shutdown screen. On a normal logout the system is still "running", so we fall
  # through to the login shell as usual.
  clear
  [[ "$(systemctl is-system-running 2>/dev/null)" == stopping ]] && exec sleep 30
fi
