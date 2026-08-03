# SaveDuk

SaveDuk is an Android-only, monochrome mobile gallery for saving media from supported links. Paste a link, or share it directly from another app, and SaveDuk stores the completed file both in the device gallery and its own library.

## On-device extraction

SaveDuk has no hosted backend, proxy, Cobalt dependency, or `SAVEDUK_BACKEND_URL` setting. On Android it embeds Python 3.11 through Chaquopy and a pinned `yt-dlp` wheel. The native bridge returns direct media streams to Flutter; Flutter downloads them immediately and uses a locally bundled FFmpeg implementation to remux separate MP4/M4A streams before saving to the gallery.

The extractor package is pinned with its SHA-256 in [android/app/requirements.txt](android/app/requirements.txt). The app does not download or execute extractor code at runtime. Updates therefore ship in a reviewed, signed Android app release until an immutable release source and signing key are configured for a verified updater.

Cookie import is not implemented: extraction is unauthenticated by default and no browser cookies are read or stored.

The Android build has a minimum API level of 24. Python 3.11 is intentionally selected so `armeabi-v7a` and `x86` devices remain supported. The FFmpeg component is the LGPL minimal maintained fork pinned to `ffmpeg_kit_flutter_new_min` 3.5.5; review its license and update cadence before distribution.

Only download media you have permission to save, and choose distribution after reviewing the relevant platform terms, copyright rules, and store policies.

## Run the app

```sh
flutter run
```

Android supports receiving shared text links. Select SaveDuk from a supported app's Share menu, or paste a link in the GET tab.
