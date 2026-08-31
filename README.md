# SaveDuk ⚡

> **Monochrome, Privacy-First, On-Device Social Media Media Downloader & Gallery for Android**

SaveDuk is an Android mobile application engineered for saving media directly to your device gallery and offline library from supported platforms (YouTube, Instagram, X/Twitter, Facebook, Pinterest). 

SaveDuk operates **100% locally with zero server backend, zero proxy dependency, and zero cloud scraping services**. All link parsing, stream extraction, media downloading, stream remuxing, and gallery indexing happen directly on your Android device.

---

## 📸 Key Features

- 🔒 **100% On-Device Extraction**: No hosted servers, scraping APIs, or Cobalt dependencies. Link extraction is executed directly inside the app using an embedded Python 3.11 runtime (via Chaquopy) and cryptographically pinned `yt-dlp`.
- 📥 **Instant Share-to-Download**: Share any supported link from YouTube, Instagram, Facebook, X, or Pinterest directly into SaveDuk via the Android system share sheet.
- 🎞️ **Direct Remuxing Engine**: Remuxes separate high-definition video (AVC/MP4) and audio (AAC/M4A) streams locally using an embedded minimal FFmpeg binary without transcoding or quality loss.
- 📱 **Native Gallery Integration**: Automatically saves media files directly to the Android device photo/video gallery (`Gal` native bridge).
- 🗃️ **Built-in Offline Library**: Built-in SQLite database tracks download history, metadata (file size, creation timestamp, source platform), with quick playback and sharing options.
- 🖤 **Minimalist Industrial UI**: Designed with a high-contrast dark monochrome aesthetic, typography powered by Google Fonts, and smooth responsive layouts.

---

## 🏗️ Architecture & Pipeline

```
  [User Action]
        │
   ┌────┴──────────────────────────┐
   │ Share Sheet / Paste URL Input │
   └────┬──────────────────────────┘
        ▼
   [UrlParserService] ──► Normalizes & cleans tracking params (utm, igsh, fbclid)
        │
        ▼
   [MethodChannel: saveduk/extractor]
        │
        ▼
   [Android Native Layer (MainActivity.kt)]
        │
        ▼
   [Chaquopy Embedded Python Runtime] ──► (yt-dlp embedded)
        │                                  Extracts direct media stream URLs
        ▼
   [Flutter DownloadService (Dio)] ───► Concurrently downloads Video & Audio streams
        │
        ▼
   [MediaMuxerService (FFmpegKit)] ───► Remuxes Video + Audio into single MP4 container
        │
   ┌────┴──────────────────────────┐
   │                               │
   ▼                               ▼
[GalleryService (Gal)]     [DatabaseService (SQLite)]
Saves to Android Gallery   Indexes media in SaveDuk Library
```

---

## 🛠️ Tech Stack

| Layer | Technologies / Packages |
| :--- | :--- |
| **Framework** | [Flutter 3.x](https://flutter.dev) (Dart 3.x) |
| **Platform Target** | Android (API 24+ / Android 7.0 to Android 15+) |
| **On-Device Python Engine** | [Chaquopy](https://chaquo.com/chaquopy/) + Python 3.11 |
| **Stream Extractor** | [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) (Hash-pinned in `requirements.txt`) |
| **Media Remuxing** | [`ffmpeg_kit_flutter_new_min`](https://pub.dev/packages/ffmpeg_kit_flutter_new_min) |
| **Network & Transfer** | [`dio`](https://pub.dev/packages/dio) |
| **Gallery Storage** | [`gal`](https://pub.dev/packages/gal) |
| **Local Database** | [`sqflite`](https://pub.dev/packages/sqflite) |
| **File Management** | [`path_provider`](https://pub.dev/packages/path_provider), [`open_file`](https://pub.dev/packages/open_file) |
| **Sharing & System** | [`share_plus`](https://pub.dev/packages/share_plus) |

---

## 🌐 Supported Platforms

| Platform | URL Formats Supported |
| :--- | :--- |
| **YouTube** | Videos (`youtube.com/watch?v=`), Shorts (`youtube.com/shorts/`), Shortlinks (`youtu.be/`) |
| **Instagram** | Reels (`instagram.com/reel/`, `/reels/`), Posts (`instagram.com/p/`), Share Links (`/share/reel/`), IGTV (`/tv/`) |
| **Facebook** | Watch (`facebook.com/watch`), Reels (`facebook.com/reel/`, `facebook.com/share/r/`), Videos (`fb.watch/`, `/share/v/`) |
| **X / Twitter** | Status updates & media links (`twitter.com/*/status/*`, `x.com/*/status/*`) |
| **Pinterest** | Pins & video posts (`pinterest.com/pin/*`, `pinterest.ca/pin/*`, `pinterest.co.uk/pin/*`) |

---

## 🚀 Getting Started

### Prerequisites

- **Flutter SDK**: `>= 3.11.4`
- **Android SDK**: Minimum API 24 (`minSdk = 24`), Target API 34+
- **Android NDK**: `28.2.13676358` (or compatible version configured in `build.gradle.kts`)
- **Java**: JDK 17

### Installation & Run

1. **Clone the repository**:
   ```bash
   git clone https://github.com/Vedk020/SaveDuk.git
   cd SaveDuk
   ```

2. **Install Flutter dependencies**:
   ```bash
   flutter pub get
   ```

3. **Run on an Android device or emulator**:
   ```bash
   flutter run
   ```

4. **Build release APK**:
   ```bash
   flutter build apk --release
   ```

> **Note on Architectures**: The Android build supports `armeabi-v7a`, `arm64-v8a`, `x86`, and `x86_64` targets. Python 3.11 in Chaquopy ensures compatibility across both modern 64-bit and legacy 32-bit hardware.

---

## 🔒 Security & Privacy Model

1. **Zero Runtime Code Execution from the Web**: The app does **not** evaluate dynamic code downloaded from arbitrary endpoints. The extractor (`yt-dlp`) wheel is cryptographically pinned with its exact SHA-256 hash in [`android/app/requirements.txt`](android/app/requirements.txt).
2. **No Cookie Scraping**: SaveDuk performs unauthenticated extraction only and does not read, store, or transmit your browser cookies or credentials.
3. **Local-Only Processing**: Extracted direct stream URLs are consumed directly by your device's network stack and saved directly to your local storage.

---

## 📋 Action Plan & Improvement Roadmap

The following enhancements are prioritized for upcoming releases:

1. **Auto-Start Download on Share Intent**:
   - Resolve cold-start timing and buffering in `MainActivity.kt` and `main.dart` so sharing a link from an external app immediately triggers extraction and download without requiring manual confirmation.
2. **Brand Logo Integration**:
   - Embed the official `assets/images/logo.jpg` into the `HomeScreen` header and app shell for consistent visual branding.
3. **Robust Instagram & Facebook Extraction**:
   - Expand `UrlParserService` regular expressions to support modern Meta share URL schemes (`/share/r/`, `/share/v/`, `instagr.am`, query parameters).
   - Enhance the Python extraction bridge format selector and fallback mechanisms for progressive and carousel/entry media streams.
4. **Background Download Service with Ongoing Notifications**:
   - Implement Android Foreground Service (`flutter_foreground_task` or native service) with ongoing notification progress to ensure downloads and muxing complete even when the app is backgrounded or screen is turned off.

---

## 📄 License & Disclaimer

- SaveDuk uses the LGPL-licensed minimal build of FFmpeg via `ffmpeg_kit_flutter_new_min`.
- Only download media that you have permission or legal rights to save. Please review the relevant platform terms of service and copyright regulations before downloading or distributing content.
