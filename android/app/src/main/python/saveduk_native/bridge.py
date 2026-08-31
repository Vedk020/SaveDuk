"""Local, metadata-only media extraction for SaveDuk.

This module deliberately never downloads files.  It returns short-lived media
stream URLs to the Flutter layer, which downloads them immediately and muxes
separate audio/video streams locally.

Cookie import is opt-in: the caller may supply a Netscape-format cookie file
or cookie header string so that Instagram, Facebook, and other sites that gate
content behind a login can be extracted.
"""

from __future__ import annotations

import json
import os
import re
import sys
from urllib.parse import urlparse

import yt_dlp
from yt_dlp.utils import DownloadError


ALLOWED_HOSTS = (
    "youtube.com",
    "youtu.be",
    "instagram.com",
    "instagr.am",
    "twitter.com",
    "x.com",
    "facebook.com",
    "fb.watch",
    "fb.gg",
    "fb.com",
    "fb.me",
    "m.facebook.com",
    "m.instagram.com",
    "pinterest.com",
    "pinterest.ca",
    "pinterest.co.uk",
)

# Hosts that typically need authentication for most content.
_AUTH_HOSTS = {
    "instagram.com",
    "instagr.am",
    "m.instagram.com",
    "facebook.com",
    "m.facebook.com",
    "fb.watch",
    "fb.gg",
    "fb.com",
    "fb.me",
}

FORMAT_SELECTOR = (
    "bestvideo[ext=mp4][vcodec^=avc]+bestaudio[ext=m4a][acodec^=mp4a]"
    "/bestvideo[ext=mp4]+bestaudio[ext=m4a]"
    "/best[ext=mp4][vcodec^=avc]"
    "/best[ext=mp4]"
    "/best"
)


def _normalize_cookie_file(cookie_path: str) -> str:
    """Ensure cookie_path contains a valid Netscape cookie format."""
    if not cookie_path or not os.path.isfile(cookie_path):
        return ""
    try:
        with open(cookie_path, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read().strip()
        if not content:
            return ""
        if "\t" in content and ("# Netscape" in content or "TRUE" in content or "FALSE" in content):
            return cookie_path

        # Convert raw key=value or cookie header string to Netscape format
        lines = ["# Netscape HTTP Cookie File"]
        items = re.split(r"[;\r\n]+", content)
        for item in items:
            item = item.strip()
            if not item or "=" not in item or item.startswith("#"):
                continue
            name, _, val = item.partition("=")
            name = name.strip()
            val = val.strip()
            if not name:
                continue
            for domain in (".instagram.com", ".facebook.com"):
                lines.append(f"{domain}\tTRUE\t/\tTRUE\t2147483647\t{name}\t{val}")

        normalized_path = cookie_path + ".netscape"
        with open(normalized_path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        return normalized_path
    except Exception as e:
        _debug(0, "cookie_normalize_error", detail=str(e))
        return cookie_path


def extract(url: str, request_id: int = 0, cookie_path: str = "") -> str:
    """Return a JSON object describing one direct media stream or stream pair.

    Args:
        url: The media page URL.
        request_id: Opaque caller-supplied ID for log correlation.
        cookie_path: Optional filesystem path to a Netscape-format cookie
            file.  When present and the file exists, it is forwarded to
            yt-dlp so that authenticated content can be extracted.
    """
    try:
        _validate_url(url)
        host = urlparse(url).hostname or "unknown"
        _debug(request_id, "started", host=host)

        # Normalize cookie file if present
        effective_cookie_path = _normalize_cookie_file(cookie_path) if cookie_path else ""

        options = {
            "format": FORMAT_SELECTOR,
            "noplaylist": True,
            "quiet": True,
            "no_warnings": True,
            "skip_download": True,
            "socket_timeout": 30,
            "extractor_retries": 2,
            "extractor_args": {
                "instagram": {
                    "api": ["graphql", "web"],
                },
                "youtube": {
                    "player_client": ["android", "web"],
                },
            },
        }

        # Pass cookie file when available.
        if effective_cookie_path and os.path.isfile(effective_cookie_path):
            options["cookiefile"] = effective_cookie_path
            _debug(request_id, "cookies_loaded", path=effective_cookie_path)

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
        return _error(_friendly_error(error, url, cookie_path))
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
    # Unwrap playlist / carousel entries (e.g. Instagram carousels).
    entries = info.get("entries")
    if entries:
        first = None
        for entry in entries:
            if entry:
                first = entry
                break
        if first:
            info = first

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
    artist = str(info.get("artist") or info.get("creator") or info.get("uploader") or info.get("channel") or "")
    track = str(info.get("track") or "")
    album = str(info.get("album") or "")
    thumbnail = str(info.get("thumbnail") or (info.get("thumbnails") and info["thumbnails"][-1].get("url")) or "")
    duration = int(info.get("duration") or 0)
    return {
        "title": title,
        "filename": _filename(title),
        "track": track,
        "artist": artist,
        "album": album,
        "thumbnail": thumbnail,
        "duration": duration,
        "video": _stream(video, info),
        "audio": _stream(audio, info) if audio else None,
    }


def search_tracks(query: str, limit: int = 10, request_id: int = 0) -> str:
    """Search YouTube for music tracks and return structured search results."""
    try:
        _debug(request_id, "search_started", query=query)
        options = {
            "format": "bestaudio/best",
            "noplaylist": True,
            "quiet": True,
            "no_warnings": True,
            "skip_download": True,
            "socket_timeout": 15,
            "extract_flat": "in_playlist",
        }
        with yt_dlp.YoutubeDL(options) as ydl:
            results = ydl.extract_info(f"ytsearch{limit}:{query}", download=False)
        entries = results.get("entries") or []
        tracks = []
        for e in entries:
            if not e:
                continue
            t_id = str(e.get("id") or "")
            t_title = str(e.get("title") or "Unknown Title")
            t_artist = str(e.get("uploader") or e.get("channel") or e.get("artist") or "Unknown Artist")
            t_thumb = str(e.get("thumbnail") or (e.get("thumbnails") and e["thumbnails"][-1].get("url")) or "")
            t_dur = int(e.get("duration") or 0)
            tracks.append({
                "id": t_id,
                "title": t_title,
                "artist": t_artist,
                "album": "",
                "thumbnail": t_thumb,
                "duration": t_dur,
                "url": f"https://www.youtube.com/watch?v={t_id}" if t_id else "",
            })
        _debug(request_id, "search_success", count=len(tracks))
        return json.dumps({"tracks": tracks}, ensure_ascii=False)
    except Exception as error:
        _debug(request_id, "search_error", detail=str(error))
        return json.dumps({"error": str(error), "tracks": []})


def _stream(stream: dict, info: dict) -> dict:
    headers = stream.get("http_headers") or info.get("http_headers") or {}
    allowed_headers = {
        str(key): str(value)
        for key, value in headers.items()
        if str(key).lower() in {"user-agent", "referer", "origin", "cookie"}
    }
    return {
        "url": stream["url"],
        "extension": str(stream.get("ext") or "mp4"),
        "headers": allowed_headers,
    }


def _filename(title: str) -> str:
    normalized = re.sub(r"[^A-Za-z0-9._-]+", "_", title).strip("._")
    return (normalized or "saveduk-video")[:120] + ".mp4"


def _friendly_error(error: Exception, url: str = "", cookie_path: str = "") -> str:
    message = str(error).strip()
    host = urlparse(url).hostname or "" if url else ""
    host_bare = host.lower().replace("www.", "").replace("m.", "").rstrip(".")
    needs_auth = host_bare in _AUTH_HOSTS or any(host_bare.endswith("." + h) for h in _AUTH_HOSTS)

    if "Unsupported URL" in message:
        return "This link is not supported."
    if "empty media response" in message.lower() or "login" in message.lower() or "private" in message.lower():
        if needs_auth and not (cookie_path and os.path.isfile(cookie_path)):
            return "Instagram/Facebook requires authentication. Tap 'Cookies' in the top right to add your session cookie."
        if needs_auth:
            return "Extraction failed. The session cookie may have expired — please update it in Cookies settings."
        return "This media needs an account and cookie import is not configured."
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



