# DevOS: graphical login is handled by SDDM (display-manager.service), which
# launches the XFCE session directly and owns the Plymouth->session and
# session->shutdown handoffs. This file intentionally does NOT auto-start X on
# console login anymore. If you ever need X without the display manager (e.g.
# SDDM disabled), run `startx` by hand.
