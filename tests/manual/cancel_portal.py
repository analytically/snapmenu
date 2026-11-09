#!/usr/bin/python3
"""Click Cancel on Snapmenu's native GTK portal chooser via accessibility.

GTK's file chooser does not consistently bind Escape to Cancel. Clicking its
actual button tests the user-visible path without relying on screen coordinates.
"""
import time

import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi


def cancel_button(node):
    if node.get_role_name() == "button" and node.get_name() == "Cancel":
        return node
    for index in range(node.get_child_count()):
        found = cancel_button(node.get_child_at_index(index))
        if found is not None:
            return found
    return None


for _ in range(50):
    desktop = Atspi.get_desktop(0)
    for index in range(desktop.get_child_count()):
        app = desktop.get_child_at_index(index)
        if app.get_name() != "xdg-desktop-portal-gtk":
            continue
        for window_index in range(app.get_child_count()):
            window = app.get_child_at_index(window_index)
            title = window.get_name()
            if not title.startswith("Snapmenu ·"):
                continue
            button = cancel_button(window)
            if button is not None and button.do_action(0):
                print("clicked Cancel on " + title)
                raise SystemExit(0)
    time.sleep(0.1)

raise SystemExit("Snapmenu portal Cancel button did not appear")
