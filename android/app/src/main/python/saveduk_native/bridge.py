"""Local, metadata-only media extraction for SaveDuk.

This module deliberately never downloads files and never reads browser cookies.
It returns short-lived media stream URLs to the Flutter layer, which downloads
them immediately and muxes separate audio/video streams locally.
"""

from __future__ import annotations

import json
import re
import sys
from urllib.parse import urlparse

import yt_dlp
from yt_dlp.utils import DownloadError


ALLOWED_HOSTS = (
    "youtube.com",
    "youtu.be",
    "instagram.com",
    "twitter.com",
    "x.com",
    "facebook.com",
    "fb.watch",
    "pinterest.com",
    "pinterest.ca",
    "pinterest.co.uk",
)

FORMAT_SELECTOR = (
    "bestvideo[ext=mp4][vcodec^=avc]+bestaudio[ext=m4a][acodec^=mp4a]"
    "/best[ext=mp4][vcodec^=avc]"
    "/best[ext=mp4]"
    "/best"
)


def extract(url: str, request_id: int = 0) -> str:
    """Return a JSON object describing one direct media stream or stream pair."""
    try:
        _validate_url(url)
        _debug(request_id, "started", host=urlparse(url).hostname or "unknown")
        options = {
            "format": FORMAT_SELECTOR,
            "noplaylist": True,
            "quiet": True,
            "no_warnings": True,
            "skip_download": True,
            "socket_timeout": 30,
            "extractor_retries": 1,
            "http_headers": {
                "User-Agent": (
                    "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 "
                    "Chrome/120.0 Mobile Safari/537.36"
                ),
            },
        }
        with yt_dlp.YoutubeDL(options) as downloader:
            info = downloader.extract_info(url, download=False)
        if not info:
            _debug(request_id, "no_media")
            return _error("No media was found at this link.")
        if info.get("is_live"):
            _debug(request_id, "live_media")
            return _error("Live streams are not supported.")
        response = _to_response(info)
        _debug(request_id, "success", separate_streams=bool(response["audio"]))
        return json.dumps(response, ensure_ascii=False)
    except ValueError as error:
        _debug(request_id, "validation_error", error_type=type(error).__name__)
        return _error(str(error))
    except DownloadError as error:
        _debug(request_id, "download_error", error_type=type(error).__name__)
        return _error(_friendly_error(error))
    except Exception as error:
        _debug(request_id, "unexpected_error", error_type=type(error).__name__)
        return _error(f"The extractor could not process this link (P{request_id}).")


def _validate_url(value: str) -> None:
    parsed = urlparse(value)
    if parsed.scheme != "https" or not parsed.hostname:
        raise ValueError("Only supported HTTPS links can be saved.")
    host = parsed.hostname.lower().rstrip(".")
    if not any(host == allowed or host.endswith("." + allowed) for allowed in ALLOWED_HOSTS):
        raise ValueError("This site is not supported.")


def _to_response(info: dict) -> dict:
    requested = info.get("requested_formats") or []
    if len(requested) >= 2:
        video = next((item for item in requested if item.get("vcodec") not in (None, "none")), None)
        audio = next((item for item in requested if item.get("acodec") not in (None, "none")), None)
        if video and audio:
            return _response(info, video, audio)
    return _response(info, info, None)


def _response(info: dict, video: dict, audio: dict | None) -> dict:
    if not video.get("url"):
        raise ValueError("No downloadable media stream was found.")
    title = str(info.get("title") or "saveduk-video")
    return {
        "title": title,
        "filename": _filename(title),
        "video": _stream(video, info),
        "audio": _stream(audio, info) if audio else None,
    }


def _stream(stream: dict, info: dict) -> dict:
    headers = stream.get("http_headers") or info.get("http_headers") or {}
    allowed_headers = {
        str(key): str(value)
        for key, value in headers.items()
        if str(key).lower() in {"user-agent", "referer", "origin"}
    }
    return {
        "url": stream["url"],
        "extension": str(stream.get("ext") or "mp4"),
        "headers": allowed_headers,
    }


def _filename(title: str) -> str:
    normalized = re.sub(r"[^A-Za-z0-9._-]+", "_", title).strip("._")
    return (normalized or "saveduk-video")[:120] + ".mp4"


def _friendly_error(error: Exception) -> str:
    message = str(error).strip()
    if "Unsupported URL" in message:
        return "This link is not supported."
    if "Private video" in message or "login" in message.lower():
        return "This media needs an account. Cookie import is not enabled."
    return "The source did not provide a downloadable media stream."


def _error(message: str) -> str:
    return json.dumps({"error": message})


def _debug(request_id: int, event: str, **fields: object) -> None:
    """Emit concise, safe diagnostics to the Flutter/ADB terminal."""
    details = " ".join(f"{key}={value}" for key, value in fields.items())
    print(
        f"SAVEDUK_EXTRACTOR request={request_id} event={event} {details}".rstrip(),
        file=sys.stderr,
        flush=True,
    )
