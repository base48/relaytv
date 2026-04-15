"""
RelayTV X11 overlay process manager.

Starts a transparent always-on-top overlay window (WebKitGTK) only when:
- XDG_SESSION_TYPE is x11 (not wayland)
- DISPLAY is set
- RELAYTV_X11_OVERLAY=1 (or true/yes/on)

The overlay loads a RelayTV-served page and subscribes to SSE notifications.
"""

from __future__ import annotations

import os
import subprocess
import sys
import threading
from typing import Optional

_OVERLAY_LOCK = threading.Lock()
_OVERLAY_PROC: Optional[subprocess.Popen] = None

def x11_session() -> bool:
    if os.getenv("XDG_SESSION_TYPE", "").strip().lower() == "wayland":
        return False
    return bool(os.getenv("DISPLAY"))

def overlay_enabled() -> bool:
    return os.getenv("RELAYTV_X11_OVERLAY", "0").strip().lower() in ("1", "true", "yes", "on")

def overlay_running() -> bool:
    global _OVERLAY_PROC
    return _OVERLAY_PROC is not None and _OVERLAY_PROC.poll() is None

def start_overlay() -> None:
    """Start overlay if enabled and X11 is available."""
    global _OVERLAY_PROC
    if not overlay_enabled() or not x11_session():
        return
    with _OVERLAY_LOCK:
        if overlay_running():
            return
        try:
            # Prefer module execution so it works in editable installs and within the package.
            _OVERLAY_PROC = subprocess.Popen(
                [sys.executable, "-m", "relaytv_app.overlay_app"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception:
            _OVERLAY_PROC = None

def stop_overlay() -> None:
    global _OVERLAY_PROC
    with _OVERLAY_LOCK:
        if not overlay_running():
            _OVERLAY_PROC = None
            return
        try:
            _OVERLAY_PROC.terminate()
            _OVERLAY_PROC.wait(timeout=2)
        except Exception:
            try:
                _OVERLAY_PROC.kill()
            except Exception:
                pass
        _OVERLAY_PROC = None
