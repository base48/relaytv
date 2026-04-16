#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export PYTHONPATH="${PYTHONPATH:-app}"
BASE_URL="${BASE_URL:-http://127.0.0.1:8787}"
REBUILD_APP="${REBUILD_APP:-0}"
RUN_LIVE_CHECKS="${RUN_LIVE_CHECKS:-1}"
CONTROL_DELTA="${CONTROL_DELTA:-1}"
STARTUP_WAIT_SEC="${STARTUP_WAIT_SEC:-20}"
STARTUP_POLL_SEC="${STARTUP_POLL_SEC:-0.5}"
TELEMETRY_WAIT_SEC="${TELEMETRY_WAIT_SEC:-45}"
TELEMETRY_POLL_SEC="${TELEMETRY_POLL_SEC:-0.5}"
export BASE_URL CONTROL_DELTA STARTUP_WAIT_SEC STARTUP_POLL_SEC TELEMETRY_WAIT_SEC TELEMETRY_POLL_SEC

PYTHON_BIN="${PYTHON_BIN:-python3}"
PYTEST_BIN="${PYTEST_BIN:-python3 -m pytest}"

FOCUS_EXPR='runtime_capabilities_qt_runtime or runtime_capabilities_qt_runtime_backend_ready_without_ipc or runtime_capabilities_qt_runtime_does_not_report_mpv_ipc_source or status_runtime_fields_match_runtime_capabilities or status_reports_native_qt_playback_telemetry_source or status_native_qt_does_not_fallback_to_mpv_ipc_reporting or playback_state_reports_native_qt_fast_path or playback_state_falls_back_to_session_fast_path or ui_prefers_playback_state_fast_polling or pause_route_returns_native_ack_fields or resume_route_returns_native_ack_fields or seek_abs_route_returns_native_ack_fields or volume_route_returns_native_ack_fields or resume_session_returns_native_ack_fields or qt_shell_runtime_write_control_assigns_request_id or qt_shell_runtime_control_when_ipc_unavailable or mpv_command_prefers_qt_runtime_control_for_non_get_property or mpv_command_waits_for_qt_runtime_control_ack or mpv_command_returns_error_when_qt_runtime_control_ack_fails or updates_cache_after_success or prefers_qt_shell_runtime_when_available or mpv_get_skips_ipc_for_qt_runtime_backed_property or mpv_get_uses_stale_cache_for_qt_runtime_backed_property_without_ipc or mpv_get_many_skips_ipc_for_qt_runtime_backed_properties or wait_for_ipc_ready_accepts_qt_runtime_for_native_embed or start_mpv_qt_backend_embed_accepts_qt_runtime_without_ipc or video_output_healthy_uses_qt_runtime_output_state_without_ipc or audio_output_ready_uses_qt_runtime_output_state_without_ipc or audio_output_ready_accepts_degraded_native_runtime_without_ipc or load_stream_in_existing_mpv_uses_qt_runtime_control_without_ipc or mpv_get_many_uses_qt_runtime_playlist_state_without_ipc or prime_mpv_up_next_from_queue_uses_qt_runtime_control_without_ipc or mpv_get_skips_ipc_for_qt_runtime_track_list or jellyfin_runtime_selected_audio_stream_uses_qt_runtime_track_list_without_ipc or jellyfin_try_set_mpv_audio_track_uses_qt_runtime_track_list_without_ipc or qt_shell_runtime_snapshot_caches_track_list_when_stream_stable or qt_shell_runtime_snapshot_refreshes_track_list_when_aid_changes'

say() {
  printf '%s\n' "$*"
}

run_cmd() {
  say
  say "+ $*"
  "$@"
}

run_shell() {
  say
  say "+ $*"
  bash -lc "$*"
}

say "validate-native-qt-telemetry"
say " - root=$ROOT_DIR"
say " - base_url=$BASE_URL"
say " - rebuild_app=$REBUILD_APP"
say " - run_live_checks=$RUN_LIVE_CHECKS"
say " - startup_wait_sec=$STARTUP_WAIT_SEC"
say " - startup_poll_sec=$STARTUP_POLL_SEC"
say " - telemetry_wait_sec=$TELEMETRY_WAIT_SEC"
say " - telemetry_poll_sec=$TELEMETRY_POLL_SEC"

run_cmd "$PYTHON_BIN" -m py_compile \
  app/relaytv_app/player.py \
  app/relaytv_app/qt_shell_app.py \
  app/relaytv_app/routes.py \
  tests/test_qt_shell_backend.py

run_shell "env PYTHONPATH='$PYTHONPATH' $PYTEST_BIN -q tests/test_qt_shell_backend.py -k \"$FOCUS_EXPR\""

if [[ "$REBUILD_APP" == "1" ]]; then
  run_cmd docker compose up -d --build relaytv
fi

if [[ "$RUN_LIVE_CHECKS" != "1" ]]; then
  say
  say "Live checks skipped (RUN_LIVE_CHECKS=$RUN_LIVE_CHECKS)."
  exit 0
fi

run_cmd "$PYTHON_BIN" - <<'PY'
import json
import os
import sys
import time
import urllib.error
import urllib.request

base = os.environ.get("BASE_URL", "http://127.0.0.1:8787").rstrip("/")
control_delta = float(os.environ.get("CONTROL_DELTA", "1"))
startup_wait_sec = max(0.0, float(os.environ.get("STARTUP_WAIT_SEC", "20")))
startup_poll_sec = max(0.1, float(os.environ.get("STARTUP_POLL_SEC", "0.5")))
telemetry_wait_sec = max(0.0, float(os.environ.get("TELEMETRY_WAIT_SEC", "45")))
telemetry_poll_sec = max(0.1, float(os.environ.get("TELEMETRY_POLL_SEC", "0.5")))


def req(path, body=None, *, method=None):
    data = None if body is None else json.dumps(body).encode()
    headers = {} if body is None else {"Content-Type": "application/json"}
    if method is None:
        method = "POST" if body is not None else "GET"
    req_obj = urllib.request.Request(base + path, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req_obj, timeout=8) as resp:
        return json.load(resp)


def wait_for_ready(path="/runtime/capabilities"):
    deadline = time.time() + startup_wait_sec
    last_exc = None
    while True:
        try:
            req(path)
            return
        except (urllib.error.URLError, ConnectionError, TimeoutError) as exc:
            last_exc = exc
            if time.time() >= deadline:
                raise SystemExit(f"service not ready at {base}{path}: {exc}") from exc
            time.sleep(startup_poll_sec)


def native_telemetry_ok(caps, status, fast):
    if caps.get("player_runtime_engine") != "qt_shell":
        return False, f"engine={caps.get('player_runtime_engine')!r}"
    if caps.get("native_qt_telemetry_source") != "qt_runtime":
        return False, f"source={caps.get('native_qt_telemetry_source')!r}"
    if not caps.get("native_qt_telemetry_selected"):
        return False, "selected=false"
    if not caps.get("native_qt_telemetry_available"):
        return False, "available=false"
    if status.get("playing"):
        if status.get("playback_telemetry_source") != "qt_runtime":
            return False, f"status_source={status.get('playback_telemetry_source')!r}"
        if fast.get("playback_telemetry_source") != "qt_runtime":
            return False, f"fast_source={fast.get('playback_telemetry_source')!r}"
        if not any(
            caps.get(key) is True
            for key in (
                "native_qt_mpv_runtime_playback_active",
                "native_qt_mpv_runtime_stream_loaded",
                "native_qt_mpv_runtime_playback_started",
            )
        ):
            return False, "runtime playback not active yet"
    return True, "ok"


def wait_for_native_telemetry():
    deadline = time.time() + telemetry_wait_sec
    last = None
    while True:
        caps = req("/runtime/capabilities")
        status = req("/status")
        fast = req("/playback/state")
        ok, reason = native_telemetry_ok(caps, status, fast)
        if ok:
            return caps, status, fast
        last = (caps, status, fast, reason)
        if time.time() >= deadline:
            caps, status, fast, reason = last
            raise SystemExit(
                "native Qt telemetry not ready: "
                f"{reason}; source={caps.get('native_qt_telemetry_source')!r} "
                f"selected={caps.get('native_qt_telemetry_selected')!r} "
                f"available={caps.get('native_qt_telemetry_available')!r} "
                f"status_playing={status.get('playing')!r} "
                f"fast_source={fast.get('playback_telemetry_source')!r}. "
                "If you rebuilt the container, start playback and rerun with REBUILD_APP=0."
            )
        time.sleep(telemetry_poll_sec)


wait_for_ready()
caps, status, fast = wait_for_native_telemetry()

print("runtime.player_runtime_engine", caps.get("player_runtime_engine"))
print("runtime.native_qt_telemetry_contract_version", caps.get("native_qt_telemetry_contract_version"))
print("runtime.native_qt_telemetry_source", caps.get("native_qt_telemetry_source"))
print("runtime.native_qt_telemetry_selected", caps.get("native_qt_telemetry_selected"))
print("runtime.native_qt_telemetry_available", caps.get("native_qt_telemetry_available"))
print("runtime.native_qt_telemetry_freshness", caps.get("native_qt_telemetry_freshness"))
print("runtime.native_qt_telemetry_last_control_request_id", caps.get("native_qt_telemetry_last_control_request_id"))
print("runtime.native_qt_telemetry_last_control_ok", caps.get("native_qt_telemetry_last_control_ok"))
print("runtime.native_qt_mpv_runtime_current_vo", caps.get("native_qt_mpv_runtime_current_vo"))
print("runtime.native_qt_mpv_runtime_current_ao", caps.get("native_qt_mpv_runtime_current_ao"))
print("runtime.native_qt_mpv_runtime_aid", caps.get("native_qt_mpv_runtime_aid"))
print("status.playback_telemetry_source", status.get("playback_telemetry_source"))
print("status.playback_telemetry_freshness", status.get("playback_telemetry_freshness"))
print("fast.playback_telemetry_source", fast.get("playback_telemetry_source"))
print("fast.playback_telemetry_freshness", fast.get("playback_telemetry_freshness"))
print("fast.playing", fast.get("playing"))
print("fast.position", fast.get("position"))
print("fast.duration", fast.get("duration"))
print("fast.volume", fast.get("volume"))
print("fast.mute", fast.get("mute"))
print("status.playing", status.get("playing"))
print("status.position", status.get("position"))
print("status.duration", status.get("duration"))
print("status.volume", status.get("volume"))
print("status.mute", status.get("mute"))

engine = caps.get("player_runtime_engine")
if engine != "qt_shell":
    raise SystemExit(f"expected player_runtime_engine=qt_shell, got {engine!r}")
if caps.get("native_qt_telemetry_contract_version") != "v1":
    raise SystemExit("native Qt telemetry contract version mismatch")
if caps.get("native_qt_telemetry_source") != "qt_runtime":
    raise SystemExit("native Qt telemetry source is not qt_runtime")
if not caps.get("native_qt_telemetry_selected"):
    raise SystemExit("native Qt telemetry is not selected")
if not caps.get("native_qt_telemetry_available"):
    raise SystemExit("native Qt telemetry is not available")
if status.get("playback_telemetry_source") not in ("qt_runtime", "none"):
    raise SystemExit(f"unexpected playback telemetry source: {status.get('playback_telemetry_source')!r}")
if status.get("playing") and fast.get("playback_telemetry_source") != "qt_runtime":
    raise SystemExit(f"unexpected fast playback telemetry source: {fast.get('playback_telemetry_source')!r}")

def assert_ack_response(name, resp, *, expect_action=None):
    if resp.get("ok") is not True:
        raise SystemExit(f"{name} route failed: {resp!r}")
    request_id = str(resp.get("request_id") or "")
    if not request_id.startswith("qtctl-"):
        raise SystemExit(f"{name} route missing native Qt request id: {resp!r}")
    if resp.get("ack_observed") is not True:
        raise SystemExit(f"{name} route did not observe native Qt ack: {resp!r}")
    if expect_action is not None and expect_action != str(resp.get("ack_reason") or ""):
        raise SystemExit(f"{name} route ack reason mismatch: {resp!r}")
    return request_id


def assert_runtime_ack(request_id, *, action):
    time.sleep(0.9)
    post_caps = req("/runtime/capabilities")
    print(f"post.{action}.native_qt_telemetry_last_control_action", post_caps.get("native_qt_telemetry_last_control_action"))
    print(f"post.{action}.native_qt_telemetry_last_control_request_id", post_caps.get("native_qt_telemetry_last_control_request_id"))
    print(f"post.{action}.native_qt_telemetry_last_control_ok", post_caps.get("native_qt_telemetry_last_control_ok"))
    print(f"post.{action}.native_qt_telemetry_last_control_error", post_caps.get("native_qt_telemetry_last_control_error"))
    post_req_id = str(post_caps.get("native_qt_telemetry_last_control_request_id") or "")
    if post_req_id != request_id:
        raise SystemExit(f"native Qt runtime ack mismatch after {action}: expected {request_id!r}, got {post_req_id!r}")
    if post_caps.get("native_qt_telemetry_last_control_ok") is not True:
        raise SystemExit(f"native Qt runtime ack failed after {action}: {post_caps.get('native_qt_telemetry_last_control_error')!r}")
    return post_caps


volume_resp = req("/volume", {"delta": control_delta})
print("control.volume_up", volume_resp)
volume_req_id = assert_ack_response("volume", volume_resp, expect_action="control_acknowledged")
post_caps = assert_runtime_ack(volume_req_id, action="volume")
print("post.volume.native_qt_mpv_runtime_volume", post_caps.get("native_qt_mpv_runtime_volume"))

active_for_pause = bool(status.get("playing")) and fast.get("position") is not None
if active_for_pause:
    pause_resp = req("/pause", method="POST")
    print("control.pause", pause_resp)
    pause_req_id = assert_ack_response("pause", pause_resp, expect_action="control_acknowledged")
    if pause_resp.get("paused") is not True:
        raise SystemExit(f"pause route did not report paused=true: {pause_resp!r}")
    assert_runtime_ack(pause_req_id, action="pause")

    resume_resp = req("/resume", method="POST")
    print("control.resume", resume_resp)
    resume_req_id = assert_ack_response("resume", resume_resp, expect_action="control_acknowledged")
    if resume_resp.get("paused") is not False:
        raise SystemExit(f"resume route did not report paused=false: {resume_resp!r}")
    assert_runtime_ack(resume_req_id, action="resume")
else:
    print("control.pause_resume_skipped", "playback_not_active")

req("/volume", {"delta": -control_delta})
print("validate-native-qt-telemetry: PASS")
PY
