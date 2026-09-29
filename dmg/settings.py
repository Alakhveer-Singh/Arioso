# dmgbuild settings for Arioso.dmg — used by build_app.sh.
# Layout matches make_background.py (660x400 window, app left, Applications right).
import os

app = defines.get("app", "build/Arioso.app")  # noqa: F821 (provided by dmgbuild)
here = os.path.dirname(os.path.abspath(__file__)) if "__file__" in dir() else "dmg"

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(app, "Contents/Resources/AppIcon.icns")
hide_extension = ["Arioso.app"]

background = os.path.join(here, "background.tiff")
window_rect = ((200, 140), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
text_size = 13
icon_locations = {
    "Arioso.app": (170, 190),
    "Applications": (490, 190),
}
