# SPDX-License-Identifier: GPL-3.0-only
import pytest


_YTDLP_PROVIDER_KEYS = (
    "YTDLP_FORMAT_YOUTUBE",
    "YTDLP_FORMAT_TWITCH",
    "YTDLP_FORMAT_TIKTOK",
    "YTDLP_FORMAT_RUMBLE",
    "YTDLP_FORMAT_BITCHUTE",
)


@pytest.fixture
def disable_arm_safe_ytdl(monkeypatch):
    monkeypatch.setenv("RELAYTV_ARM_ENFORCE_SAFE_YTDL_FORMAT", "0")


@pytest.fixture
def ytdlp_format_best(monkeypatch):
    monkeypatch.setenv("YTDLP_FORMAT", "best")
    for key in _YTDLP_PROVIDER_KEYS:
        monkeypatch.delenv(key, raising=False)


@pytest.fixture
def ytdlp_format_unset(monkeypatch):
    monkeypatch.delenv("YTDLP_FORMAT", raising=False)
    for key in _YTDLP_PROVIDER_KEYS:
        monkeypatch.delenv(key, raising=False)
