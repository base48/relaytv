"""
RelayTV X11 Overlay App (transparent always-on-top browser window)

This is intentionally small and dependency-light: GTK + WebKitGTK.

Runs ONLY on X11. On Wayland or DRM/KMS, RelayTV should fall back to mpv OSD.
"""

from __future__ import annotations

import argparse
import os
import sys

from .debug import get_logger


logger = get_logger("overlay")

def _eprint(*a: object) -> None:
    logger.info(" ".join(str(part) for part in a))

def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)

    ap = argparse.ArgumentParser(description="RelayTV X11 Overlay (WebKitGTK)")
    ap.add_argument("--url", default=os.getenv("RELAYTV_OVERLAY_URL", "http://127.0.0.1:8787/x11/overlay"))
    ap.add_argument("--click-through", action="store_true", default=os.getenv("RELAYTV_OVERLAY_CLICKTHROUGH", "0").strip().lower() in ("1","true","yes","on"))
    args = ap.parse_args(argv)

    try:
        import gi
        gi.require_version("Gtk", "3.0")

        # Prefer WebKitGTK 4.1 (Ubuntu 24.04 / newer Debian). Fall back to 4.0 if needed.
        try:
            gi.require_version("WebKit2", "4.1")
        except ValueError:
            gi.require_version("WebKit2", "4.0")

        from gi.repository import Gtk, WebKit2, GLib, Gdk
    except Exception as e:
        _eprint("RelayTV overlay requires GTK3 + WebKitGTK (PyGObject).")
        _eprint("Install (Ubuntu 24.04+ / newer Debian): apt-get install -y python3-gi gir1.2-gtk-3.0 gir1.2-webkit2-4.1")
        _eprint("Install (older Debian/Ubuntu): apt-get install -y python3-gi gir1.2-gtk-3.0 gir1.2-webkit2-4.0")
        _eprint("Error:", e)
        return 2

    # Must be on X11 for the always-on-top transparent overlay semantics we rely on.
    if os.getenv("XDG_SESSION_TYPE", "").strip().lower() == "wayland":
        _eprint("Wayland session detected; X11 overlay disabled.")
        return 3
    if not os.getenv("DISPLAY"):
        _eprint("No DISPLAY set; X11 overlay disabled.")
        return 3

    win = Gtk.Window(title="RelayTV Overlay")
    win.set_decorated(False)
    win.set_keep_above(True)
    win.set_skip_taskbar_hint(True)
    win.set_skip_pager_hint(True)
    win.set_accept_focus(False)
    win.set_app_paintable(True)

    # Transparency
    screen = win.get_screen()
    rgba = screen.get_rgba_visual()
    if rgba is not None:
        win.set_visual(rgba)

    def _on_draw(_w, cr):
        cr.set_source_rgba(0, 0, 0, 0)
        cr.set_operator(0)  # CLEAR
        cr.paint()
        return False

    win.connect("draw", _on_draw)

    # WebView
    view = WebKit2.WebView()
    settings = view.get_settings()
    settings.set_property("enable-webgl", False)
    settings.set_property("enable-plugins", False)
    settings.set_property("enable-write-console-messages-to-stdout", False)
    # Ensure a transparent page background if supported.
    try:
        view.set_background_color(Gdk.RGBA(0, 0, 0, 0))
    except Exception:
        pass

    win.add(view)

    def _go_fullscreen():
        try:
            win.fullscreen()
        except Exception:
            pass
        return False

    GLib.idle_add(_go_fullscreen)

    def _on_key(_w, ev):
        # Escape closes overlay.
        try:
            keyval = ev.keyval
        except Exception:
            return False
        if keyval == Gdk.KEY_Escape:
            Gtk.main_quit()
            return True
        return False

    win.connect("key-press-event", _on_key)

    # Optional click-through: make the window input-transparent to mouse events.
    # This only works on X11 and requires an X11 window to exist (after realize).
    def _enable_click_through():
        if not args.click_through:
            return
        try:
            gdk_win = win.get_window()
            if not gdk_win:
                return
            # Empty input shape region -> all input passes through.
            region = Gdk.Region()  # empty
            gdk_win.input_shape_combine_region(region, 0, 0)
        except Exception:
            pass

    win.connect("realize", lambda *_: _enable_click_through())

    # Close behavior
    win.connect("destroy", lambda *_: Gtk.main_quit())

    view.load_uri(args.url)

    win.show_all()
    Gtk.main()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
