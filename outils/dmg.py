# Réglages de l'image disque Majordome.dmg (lus par dmgbuild).
# La fenêtre montre l'app à gauche, le dossier Applications à droite, et une flèche entre les deux.
import os.path

application = defines.get("app", "build/Majordome.app")  # noqa: F821 (fourni par dmgbuild)
nom_app = os.path.basename(application)

format = "UDZO"
filesystem = "HFS+"
files = [application]
symlinks = {"Applications": "/Applications"}
icon = None
background = defines.get("fond", "build/dmg-fond.tiff")  # noqa: F821

window_rect = ((200, 140), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
arrange_by = None
icon_size = 112
text_size = 13
icon_locations = {
    nom_app: (165, 205),
    "Applications": (495, 205),
}
